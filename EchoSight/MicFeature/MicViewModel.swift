import Combine
import Foundation

// Tiny helper to cap high-frequency UI updates, such as EQ bars.
// Without throttling, every audio buffer would redraw SwiftUI and feel laggy.
private final class UpdateThrottle: @unchecked Sendable {
    // Minimum time between allowed updates.
    private let interval: TimeInterval
    // Lock makes the throttle safe from the background processing queue.
    private let lock = NSLock()
    private var lastRun = Date.distantPast

    nonisolated init(interval: TimeInterval) {
        self.interval = interval
    }

    func shouldRun(at date: Date = Date()) -> Bool {
        // Return true only when enough time passed since the previous publish.
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
    // Coordinates the Mic feature:
    // - starts/stops microphone capture
    // - sends buffers to FFT, sound detection, and live captions
    // - publishes small, throttled updates that SwiftUI can render smoothly
    @Published var isListening: Bool = false
    @Published var transcriptLines: [String] = []
    @Published var fullTranscript: String = ""
    @Published var recentEvents: [SoundEvent] = []
    @Published var eqBands: [Float] = Array(repeating: 0, count: 5)
    @Published var errorBanner: String?
    @Published var noisyMode: Bool = false {
        didSet {
            // Noisy mode loosens sound event thresholds for loud environments.
            soundEventService.noisyMode = noisyMode
        }
    }

    // Audio capture is the source of all mic buffers.
    private let audioService = AudioCaptureService()
    // nonisolated services can be used from the processing queue.
    nonisolated private let eqAnalyzer = EQAnalyzer()
    nonisolated private let transcriptionService = LiveTranscriptionService()
    nonisolated private let soundEventService = SoundEventService()
    // Background queue keeps FFT and event detection away from MainActor.
    nonisolated private let processingQueue = DispatchQueue(label: "echosight.mic.processing")
    // EQ bars publish at 15 FPS even though audio buffers arrive faster.
    nonisolated private let eqPublishThrottle = UpdateThrottle(interval: 1.0 / 15.0)
    // Combine subscriptions live as long as the view model.
    private var cancellables = Set<AnyCancellable>()
    // Keep only recent events so the UI stays small and readable.
    private let maxEvents = 5
    private let eventWindowSeconds: TimeInterval = 12
    private var lastLoggedTranscriptLine = ""
    private var lastTranscriptLogAt = Date.distantPast

    init() {
        bindServices()
    }

    func toggleListening() {
        // Single UI button toggles between start and stop.
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        // Permissions are async, so start flow runs inside a Task.
        Task { [weak self] in
            await self?.startListeningFlow()
        }
    }

    func stopListening() {
        // Stop both raw audio capture and speech recognition.
        audioService.stop()
        transcriptionService.stop()
        isListening = false
    }

    private func startListeningFlow() async {
        // Clear previous error before attempting a fresh start.
        errorBanner = nil
        let micGranted = await audioService.requestPermission()
        guard micGranted else {
            errorBanner = "Microphone access denied. Enable it in Settings."
            isListening = false
            return
        }
        let speechGranted = await transcriptionService.requestPermission()
        guard speechGranted else {
            // Speech permission is separate from microphone permission on iOS.
            errorBanner = "Speech recognition access denied. Enable it in Settings."
            isListening = false
            return
        }

        let audioStarted = audioService.start()
        if !audioStarted {
            // AudioCaptureService stores the detailed start error.
            errorBanner = audioService.error ?? "Unable to start microphone."
            isListening = false
            return
        }

        let speechStarted = transcriptionService.start()
        if !speechStarted {
            // The mic can still show EQ/events even if speech recognition fails.
            errorBanner = transcriptionService.error ?? "Speech recognition unavailable."
        }

        isListening = audioStarted
    }

    private func bindServices() {
        // Local constants avoid repeated actor hops inside Combine closures.
        let eqAnalyzer = self.eqAnalyzer
        let soundEventService = self.soundEventService
        let transcriptionService = self.transcriptionService

        audioService.sampleSubject
            .receive(on: processingQueue)
            .sink { [weak self] sample in
                // One audio sample fans out to EQ, sound events, and transcription.
                let bands = eqAnalyzer.process(buffer: sample.buffer, sampleRate: sample.sampleRate)
                let event = soundEventService.process(bands: bands, rms: sample.rms, timestamp: sample.timestamp)
                let shouldPublishBands = self?.eqPublishThrottle.shouldRun(at: sample.timestamp) ?? false

                // Speech recognition expects the same audio buffers.
                transcriptionService.appendAudioBuffer(sample.buffer)

                Task { @MainActor in
                    guard let self else { return }
                    if shouldPublishBands {
                        // Publish throttled EQ data for smooth bars.
                        self.eqBands = bands
                    }
                    if let event {
                        // Event gets displayed, logged, and optionally sent as an assist alert.
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
                // Keep full transcript for detail and formatted lines for compact UI.
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
                // Bubble speech errors into one banner.
                guard let self, let error, !error.isEmpty else { return }
                self.errorBanner = error
            }
            .store(in: &cancellables)

        audioService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                // Bubble audio capture errors into the same banner.
                guard let self, let error, !error.isEmpty else { return }
                self.errorBanner = error
            }
            .store(in: &cancellables)

        audioService.$isRunning
            .receive(on: DispatchQueue.main)
            // Audio service is source of truth for listening state.
            .assign(to: &$isListening)
    }

    private func appendEvent(_ event: SoundEvent) {
        // Append then trim to a recent rolling window.
        var updated = recentEvents
        updated.append(event)
        let cutoff = Date().addingTimeInterval(-eventWindowSeconds)
        updated = updated.filter { $0.timestamp >= cutoff }
        if updated.count > maxEvents {
            // Keep the newest maxEvents items.
            updated = Array(updated.suffix(maxEvents))
        }
        recentEvents = updated
    }

    private func formatLines(from transcript: String) -> [String] {
        // Prefer explicit newlines from the recognizer if present.
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
        // If there is one long line, wrap it into readable chunks.
        let words = singleLine.split(separator: " ")
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            if candidate.count > 38 {
                // Start a new caption line before text gets too wide.
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
        // Avoid logging tiny duplicate transcript updates every recognition callback.
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
