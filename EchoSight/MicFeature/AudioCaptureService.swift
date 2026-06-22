import AVFoundation
import Accelerate
import Combine
import Foundation

struct AudioSample {
    let buffer: AVAudioPCMBuffer
    let rms: Float
    let sampleRate: Float
    let timestamp: Date
}

final class AudioCaptureService: ObservableObject {
    let sampleSubject = PassthroughSubject<AudioSample, Never>()
    @Published var rmsLevel: Float = 0
    @Published var isRunning: Bool = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private let processingQueue = DispatchQueue(label: "echosight.audio.capture")
    private var wasRunningBeforeInterruption = false
    private var lastRMSPublishAt = Date.distantPast

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func requestPermission() async -> Bool {
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        error = nil

        if !configureSessionWithFallbacks() {
            return false
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processingQueue.async {
                self?.process(buffer: buffer)
            }
        }

        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
            return true
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            return false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    private func configureSession(category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) -> Bool {
        do {
            try session.setPreferredSampleRate(44_100)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setCategory(category, mode: mode, options: options)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            return true
        } catch {
            self.error = "Unable to start microphone session: \(error.localizedDescription)"
            return false
        }
    }

    private func configureSessionWithFallbacks() -> Bool {
        let attempts: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.record, .measurement, [.duckOthers]),
            (.record, .default, []),
            (.playAndRecord, .default, [.defaultToSpeaker]),
            (.playAndRecord, .voiceChat, [.defaultToSpeaker])
        ]

        for (category, mode, options) in attempts {
            if configureSession(category: category, mode: mode, options: options) {
                return true
            }
        }
        return false
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let copy = copyBuffer(buffer) else { return }
        let rms = computeRMS(copy)
        let sampleRate = Float(copy.format.sampleRate)
        let sample = AudioSample(buffer: copy, rms: rms, sampleRate: sampleRate, timestamp: Date())
        sampleSubject.send(sample)
        if sample.timestamp.timeIntervalSince(lastRMSPublishAt) >= 1.0 / 15.0 {
            lastRMSPublishAt = sample.timestamp
            DispatchQueue.main.async {
                self.rmsLevel = rms
            }
        }
    }

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameLength))
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = min(max((db + 50) / 50, 0), 1)
        return normalized
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: buffer.format.sampleRate,
                                          channels: buffer.format.channelCount,
                                          interleaved: false) else {
            return nil
        }
        let copied = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity)
        copied?.frameLength = buffer.frameLength
        guard let copied,
              let src = buffer.floatChannelData,
              let dst = copied.floatChannelData else { return nil }
        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)
        for channel in 0..<channels {
            dst[channel].assign(from: src[channel], count: frames)
        }
        return copied
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard isRunning else { return }
        stop()
        _ = start()
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasRunningBeforeInterruption = isRunning
            stop()
        case .ended:
            if wasRunningBeforeInterruption {
                _ = start()
            }
            wasRunningBeforeInterruption = false
        @unknown default:
            break
        }
    }
}
