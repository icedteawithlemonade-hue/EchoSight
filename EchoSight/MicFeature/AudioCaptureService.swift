import AVFoundation
import Accelerate
import Combine
import Foundation

// One microphone chunk passed through the audio pipeline.
// It includes the copied buffer, loudness, sample rate, and timestamp.
struct AudioSample {
    // Copied audio buffer so downstream services can safely read it later.
    let buffer: AVAudioPCMBuffer
    // Normalized loudness 0...1.
    let rms: Float
    // Needed by FFT code to convert bins to Hz.
    let sampleRate: Float
    // Used for throttling and recent-event windows.
    let timestamp: Date
}

// Owns microphone permission, AVAudioSession setup, interruption handling,
// and a background queue so audio work does not freeze SwiftUI.
final class AudioCaptureService: ObservableObject {
    // Combine stream that MicViewModel subscribes to.
    let sampleSubject = PassthroughSubject<AudioSample, Never>()
    // Lightweight loudness value for UI meters.
    @Published var rmsLevel: Float = 0
    // Reflects AVAudioEngine running state.
    @Published var isRunning: Bool = false
    // Error string shown by MicViewModel when setup fails.
    @Published var error: String?

    // AVAudioEngine owns the live microphone graph.
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    // Audio tap work is moved off the realtime callback thread.
    private let processingQueue = DispatchQueue(label: "echosight.audio.capture")
    // Used to resume after phone calls/Siri/audio interruptions.
    private var wasRunningBeforeInterruption = false
    // Throttles rmsLevel publishes so SwiftUI does not redraw for every buffer.
    private var lastRMSPublishAt = Date.distantPast

    init() {
        // Route change covers headphones, Bluetooth devices, speaker changes, etc.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        // Interruption covers phone calls, Siri, or another app taking audio.
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
        // Async wrapper around AVAudioSession's callback permission API.
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        // Resume on main because callers often update UI right after.
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    func start() -> Bool {
        // Starting twice should be harmless.
        guard !isRunning else { return true }
        error = nil

        // Try several audio session setups because devices/simulators differ.
        if !configureSessionWithFallbacks() {
            return false
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        // Install a microphone tap; each callback receives a short audio buffer.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processingQueue.async {
                // Process outside the audio callback for safety.
                self?.process(buffer: buffer)
            }
        }

        do {
            // engine.start begins live capture.
            try engine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
            return true
        } catch {
            // Store a user-readable error for MicViewModel.
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            return false
        }
    }

    func stop() {
        // Stop only if running to avoid AVAudioEngine tap errors.
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
            // 44.1kHz and small IO buffer are good defaults for responsive analysis.
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
        // First attempt is best for analysis; later attempts are compatibility fallbacks.
        let attempts: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.record, .measurement, [.duckOthers]),
            (.record, .default, []),
            (.playAndRecord, .default, [.defaultToSpeaker]),
            (.playAndRecord, .voiceChat, [.defaultToSpeaker])
        ]

        for (category, mode, options) in attempts {
            // Return as soon as one audio session configuration succeeds.
            if configureSession(category: category, mode: mode, options: options) {
                return true
            }
        }
        return false
    }

    private func process(buffer: AVAudioPCMBuffer) {
        // Copy first because AVAudioEngine can reuse its original buffer memory.
        guard let copy = copyBuffer(buffer) else { return }
        let rms = computeRMS(copy)
        let sampleRate = Float(copy.format.sampleRate)
        let sample = AudioSample(buffer: copy, rms: rms, sampleRate: sampleRate, timestamp: Date())
        // Send full sample to EQ, sound event detection, and transcription.
        sampleSubject.send(sample)
        if sample.timestamp.timeIntervalSince(lastRMSPublishAt) >= 1.0 / 15.0 {
            // UI loudness updates are limited to 15 FPS.
            lastRMSPublishAt = sample.timestamp
            DispatchQueue.main.async {
                self.rmsLevel = rms
            }
        }
    }

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        // RMS is a standard single-number loudness measure.
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameLength))
        // Convert amplitude to dB, then map roughly -50dB...0dB into 0...1.
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = min(max((db + 50) / 50, 0), 1)
        return normalized
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // Create a non-interleaved Float32 buffer matching the source format.
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
            // Copy each channel's raw samples.
            dst[channel].assign(from: src[channel], count: frames)
        }
        return copied
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        // Restart capture so the engine uses the new input/output route.
        guard isRunning else { return }
        stop()
        _ = start()
    }

    @objc private func handleInterruption(_ notification: Notification) {
        // Pause capture during interruptions and resume if we were running before.
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            // Save state so we know whether to restart after interruption.
            wasRunningBeforeInterruption = isRunning
            stop()
        case .ended:
            // Resume only if the user had been listening before.
            if wasRunningBeforeInterruption {
                _ = start()
            }
            wasRunningBeforeInterruption = false
        @unknown default:
            break
        }
    }
}
