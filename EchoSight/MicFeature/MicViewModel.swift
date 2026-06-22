import Combine
import Foundation

private final class UpdateThrottle: @unchecked Sendable {
    private let interval: TimeInterval
    private let lock = NSLock()
    private var lastRun = Date.distantPast

    nonisolated init(interval: TimeInterval) {
        self.interval = interval
    }

    func shouldRun(at date: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard date.timeIntervalSince(lastRun) >= interval else { return false }
        lastRun = date
        return true
    }
}

// README: MicViewModel data flow
// 1) AudioCaptureService captures mic buffers and RMS on a background queue.
// 2) Buffers feed EQAnalyzer (FFT) + SoundEventService for local detection.
// 3) Buffers also feed LiveTranscriptionService for streaming captions.
// 4) MicViewModel merges updates on the main actor for SwiftUI binding.

@MainActor
final class MicViewModel: ObservableObject {
    @Published var isListening: Bool = false
    @Published var transcriptLines: [String] = []
    @Published var fullTranscript: String = ""
    @Published var recentEvents: [SoundEvent] = []
    @Published var eqBands: [Float] = Array(repeating: 0, count: 5)
    @Published var errorBanner: String?
    @Published var noisyMode: Bool = false {
        didSet {
            soundEventService.noisyMode = noisyMode
        }
    }

    private let audioService = AudioCaptureService()
    nonisolated private let eqAnalyzer = EQAnalyzer()
    nonisolated private let transcriptionService = LiveTranscriptionService()
    nonisolated private let soundEventService = SoundEventService()
    nonisolated private let processingQueue = DispatchQueue(label: "echosight.mic.processing")
    nonisolated private let eqPublishThrottle = UpdateThrottle(interval: 1.0 / 15.0)
    private var cancellables = Set<AnyCancellable>()
    private let maxEvents = 5
    private let eventWindowSeconds: TimeInterval = 12
    private var lastLoggedTranscriptLine = ""
    private var lastTranscriptLogAt = Date.distantPast

    init() {
        bindServices()
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        Task { [weak self] in
            await self?.startListeningFlow()
        }
    }

    func stopListening() {
        audioService.stop()
        transcriptionService.stop()
        isListening = false
    }

    private func startListeningFlow() async {
        errorBanner = nil
        let micGranted = await audioService.requestPermission()
        guard micGranted else {
            errorBanner = "Microphone access denied. Enable it in Settings."
            isListening = false
            return
        }
        let speechGranted = await transcriptionService.requestPermission()
        guard speechGranted else {
            errorBanner = "Speech recognition access denied. Enable it in Settings."
            isListening = false
            return
        }

        let audioStarted = audioService.start()
        if !audioStarted {
            errorBanner = audioService.error ?? "Unable to start microphone."
            isListening = false
            return
        }

        let speechStarted = transcriptionService.start()
        if !speechStarted {
            errorBanner = transcriptionService.error ?? "Speech recognition unavailable."
        }

        isListening = audioStarted
    }

    private func bindServices() {
        let eqAnalyzer = self.eqAnalyzer
        let soundEventService = self.soundEventService
        let transcriptionService = self.transcriptionService

        audioService.sampleSubject
            .receive(on: processingQueue)
            .sink { [weak self] sample in
                let bands = eqAnalyzer.process(buffer: sample.buffer, sampleRate: sample.sampleRate)
                let event = soundEventService.process(bands: bands, rms: sample.rms, timestamp: sample.timestamp)
                let shouldPublishBands = self?.eqPublishThrottle.shouldRun(at: sample.timestamp) ?? false

                transcriptionService.appendAudioBuffer(sample.buffer)

                Task { @MainActor in
                    guard let self else { return }
                    if shouldPublishBands {
                        self.eqBands = bands
                    }
                    if let event {
                        self.appendEvent(event)
                        ActivityHistoryStore.shared.add(.sound, title: event.type.displayName, detail: "Confidence \(Int(event.confidence * 100))%")
                        AssistAlertCenter.shared.alert(.sound, message: event.type.displayName)
                    }
                }
            }
            .store(in: &cancellables)

        transcriptionService.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self else { return }
                self.fullTranscript = transcript
                self.transcriptLines = self.formatLines(from: transcript)
                if let latestLine = self.transcriptLines.last {
                    self.logTranscriptIfNeeded(latestLine)
                }
            }
            .store(in: &cancellables)

        transcriptionService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self, let error, !error.isEmpty else { return }
                self.errorBanner = error
            }
            .store(in: &cancellables)

        audioService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self, let error, !error.isEmpty else { return }
                self.errorBanner = error
            }
            .store(in: &cancellables)

        audioService.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isListening)
    }

    private func appendEvent(_ event: SoundEvent) {
        var updated = recentEvents
        updated.append(event)
        let cutoff = Date().addingTimeInterval(-eventWindowSeconds)
        updated = updated.filter { $0.timestamp >= cutoff }
        if updated.count > maxEvents {
            updated = Array(updated.suffix(maxEvents))
        }
        recentEvents = updated
    }

    private func formatLines(from transcript: String) -> [String] {
        let rawLines = transcript.split(whereSeparator: \.isNewline).map { String($0) }
        if rawLines.count >= 3 {
            return Array(rawLines.suffix(3))
        }
        if rawLines.count == 2 {
            return rawLines
        }
        guard let singleLine = rawLines.first, !singleLine.isEmpty else {
            return []
        }
        let words = singleLine.split(separator: " ")
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            if candidate.count > 38 {
                lines.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return Array(lines.suffix(3))
    }

    private func logTranscriptIfNeeded(_ line: String) {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let now = Date()
        guard cleaned != lastLoggedTranscriptLine || now.timeIntervalSince(lastTranscriptLogAt) > 4 else {
            return
        }
        lastLoggedTranscriptLine = cleaned
        lastTranscriptLogAt = now
        ActivityHistoryStore.shared.add(.transcript, title: "Live Caption", detail: cleaned)
    }
}
