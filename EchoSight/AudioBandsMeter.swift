import Foundation
import AVFoundation
import Accelerate
import Combine
import SwiftUI
import CoreHaptics
import UIKit

// AudioBandsMeter powers the standalone mic visualizer.
// It captures microphone audio, converts it into five frequency bands, and can
// trigger haptics so sound has a tactile representation.
final class AudioBandsMeter: ObservableObject {
    // Published for UI. Each band is normalized 0...1 for simple bar drawing.
    @Published var bands: [Float] = Array(repeating: 0, count: 5)   // 0...1
    // Lets the view show whether microphone capture is active.
    @Published var isRunning: Bool = false
    // True after a baseline noise calibration window finishes.
    @Published var calibrated: Bool = false
    // Higher sensitivity lowers spike thresholds.
    @Published var sensitivity: Float = 1.0  // 0.6...1.8 typical

    // Audio
    // AVAudioEngine delivers microphone buffers.
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()

    // FFT (classic vDSP)
    // FFT size must be a power of two; 1024 is a good real-time compromise.
    private let fftSize: Int = 1024          // must be power of 2
    private var log2n: vDSP_Length { vDSP_Length(log2(Float(fftSize))) }
    private var fftSetup: FFTSetup?

    private var window: [Float] = []
    private var windowed: [Float] = []
    private var real: [Float] = []
    private var imag: [Float] = []
    private var mags: [Float] = []

    // 5 bands: Low / Low-mid / Mid / High-mid / High
    // Six edges define five frequency ranges.
    private let bandEdges: [Float] = [80, 250, 700, 2000, 6000, 12000] // 6 edges -> 5 bands

    // Calibration
    // Baseline tracks normal room noise for each band.
    private var baseline: [Float] = Array(repeating: 0, count: 5)
    private var baselineAccum: [Float] = Array(repeating: 0, count: 5)
    private var baselineCount: Int = 0
    private var calibratingUntil: Date?

    // Smoothing
    private let smoothingAlpha: Float = 0.20

    // Spike detection
    private var aboveSince: [Date?] = Array(repeating: nil, count: 5)
    private var lastAlertAt: [Date] = Array(repeating: .distantPast, count: 5)
    private var lastGlobalAlert: Date = .distantPast

    private let minHoldTime: TimeInterval = 0.25
    private let perBandCooldown: TimeInterval = 1.2
    private let globalCooldown: TimeInterval = 0.35

    private let baseThreshold: Float = 0.20
    private let hysteresis: Float = 0.08

    private let haptics = HapticsManager()

    init() {
        // FFT setup
        // vDSP_create_fftsetup builds reusable FFT lookup data for speed.
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        // Window (Hann)
        // Hann window reduces frequency artifacts at buffer edges.
        window = Array(repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        windowed = Array(repeating: 0, count: fftSize)

        // Split complex buffers are size fftSize/2
        real = Array(repeating: 0, count: fftSize / 2)
        imag = Array(repeating: 0, count: fftSize / 2)
        mags = Array(repeating: 0, count: fftSize / 2)
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    // MARK: - Permissions + start/stop

    func requestPermissionAndStart() {
        // Permission is required before AVAudioEngine can read the microphone.
        switch session.recordPermission {
        case .granted:
            start()
        case .denied:
            stop()
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.start() }
                }
            }
        @unknown default:
            stop()
        }
    }

    func start() {
        guard !isRunning else { return }

        do {
            // Measurement mode keeps audio processing clean for analysis.
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        // Tap delivers exactly fftSize frames so each callback maps to one FFT.
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer, sampleRate: Float(format.sampleRate))
        }

        do {
            try engine.start()
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            stop()
        }
    }

    func stop() {
        // Remove tap before stopping to prevent callbacks after shutdown.
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false)
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Calibration

    func calibrate(seconds: TimeInterval = 2.0) {
        // Start a short window where we average bands into the baseline.
        baselineAccum = Array(repeating: 0, count: 5)
        baselineCount = 0
        calibratingUntil = Date().addingTimeInterval(seconds)
        calibrated = false
    }

    // MARK: - Processing

    private func process(buffer: AVAudioPCMBuffer, sampleRate: Float) {
        // Processing pipeline: mic samples -> window -> FFT -> magnitudes -> bands.
        guard let fftSetup else { return }
        guard let channel = buffer.floatChannelData?.pointee else { return }
        let n = Int(buffer.frameLength)
        guard n >= fftSize else { return }

        // Copy first fftSize samples into Swift array + window them: windowed = samples * window
        // vDSP_vmul does elementwise multiplication
        windowed.withUnsafeMutableBufferPointer { wOut in
            window.withUnsafeBufferPointer { win in
                vDSP_vmul(channel, 1, win.baseAddress!, 1, wOut.baseAddress!, 1, vDSP_Length(fftSize))
            }
        }

        // Pack real signal into split complex using "even/odd" packing trick:
        // Treat windowed as interleaved complex numbers (real=even, imag=odd)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)

        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
            }
        }

        // FFT in-place
        // Real-input FFT converts time-domain audio into frequency bins.
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        // Magnitude squared
        mags.withUnsafeMutableBufferPointer { mPtr in
            vDSP_zvmags(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(fftSize / 2))
        }

        // Compute 5 bands
        let newBands = computeBands(from: mags, sampleRate: sampleRate)

        // Smooth for UI
        // Exponential smoothing prevents bars from jumping too harshly.
        var smoothed = bands
        for i in 0..<5 {
            smoothed[i] = (1 - smoothingAlpha) * smoothed[i] + smoothingAlpha * newBands[i]
        }

        // Calibration update
        // Average smoothed band values until the calibration deadline.
        if let until = calibratingUntil {
            if Date() < until {
                baselineCount += 1
                for i in 0..<5 { baselineAccum[i] += smoothed[i] }
            } else {
                calibratingUntil = nil
                if baselineCount > 0 {
                    for i in 0..<5 { baseline[i] = baselineAccum[i] / Float(baselineCount) }
                    calibrated = true
                }
            }
        }

        // Spike detection
        // Haptic spikes are based on smoothed values so feedback is not noisy.
        detectSpikesAndHaptics(smoothed)

        DispatchQueue.main.async {
            // @Published values should be changed on the main queue.
            self.bands = smoothed
        }
    }

    private func computeBands(from mags: [Float], sampleRate: Float) -> [Float] {
        // Convert FFT bin magnitudes into five user-friendly frequency bands.
        let binHz = sampleRate / Float(fftSize)
        var bandVals = Array(repeating: Float(0), count: 5)

        for b in 0..<5 {
            let f0 = bandEdges[b]
            let f1 = bandEdges[b + 1]
            // Translate frequency range into FFT bin range.
            let i0 = max(1, Int(f0 / binHz))
            let i1 = min(mags.count - 1, Int(f1 / binHz))
            if i1 <= i0 { continue }

            // Stable sum: just use a loop (avoids API mismatch on vDSP.sum signatures)
            var sum: Float = 0
            for i in i0..<i1 { sum += mags[i] }

            // Compress & normalize (tune divisor if needed)
            // log10 compression keeps loud sounds from instantly maxing the UI.
            let compressed = log10(1 + sum)
            let normalized = min(1, compressed / 6.0)

            bandVals[b] = normalized
        }

        return bandVals
    }

    private func detectSpikesAndHaptics(_ current: [Float]) {
        // Detect sudden band increases compared with the calibrated baseline.
        let now = Date()
        // Global cooldown prevents multiple bands from firing haptics at once.
        let globalReady = now.timeIntervalSince(lastGlobalAlert) > globalCooldown

        for i in 0..<5 {
            // If not calibrated, baseline is zero and the meter still works.
            let base = calibrated ? baseline[i] : 0
            let delta = current[i] - base

            // Sensitivity lowers/raises the needed increase over baseline.
            let threshold = baseThreshold / max(0.3, sensitivity)

            if delta > threshold {
                // First frame above threshold starts the hold timer.
                if aboveSince[i] == nil { aboveSince[i] = now }

                let held = now.timeIntervalSince(aboveSince[i]!) >= minHoldTime
                let cooled = now.timeIntervalSince(lastAlertAt[i]) >= perBandCooldown

                if held && cooled && globalReady {
                    // Fire only after the sound has stayed above threshold.
                    lastAlertAt[i] = now
                    lastGlobalAlert = now
                    fireHaptic(forBand: i, strength: delta)
                }
            } else if delta < max(0, threshold - hysteresis) {
                // Hysteresis prevents rapid on/off flicker near the threshold.
                aboveSince[i] = nil
            }
        }
    }

    private func fireHaptic(forBand band: Int, strength: Float) {
        // Convert sound strength into a haptic intensity range.
        let intensity = min(1, max(0.2, strength * 1.5))

        // Lower bands use fewer/softer pulses; higher bands feel sharper/faster.
        switch band {
        case 0: haptics.pulse(intensity: intensity, sharpness: 0.2, count: 1, spacing: 0.0)   // Low
        case 1: haptics.pulse(intensity: intensity, sharpness: 0.4, count: 2, spacing: 0.12)  // Low-mid
        case 2: haptics.pulse(intensity: intensity, sharpness: 0.7, count: 3, spacing: 0.10)  // Mid (speech-ish)
        case 3: haptics.pulse(intensity: intensity, sharpness: 0.9, count: 2, spacing: 0.06)  // High-mid
        default: haptics.pulse(intensity: intensity * 0.9, sharpness: 1.0, count: 4, spacing: 0.05) // High
        }
    }
}

// Small wrapper around Core Haptics with a UIKit fallback for devices that
// do not support custom haptic patterns.
final class HapticsManager {
    // Core Haptics supports custom pulses; UIKit fallback works on more devices.
    private var engine: CHHapticEngine?
    private let fallback = UINotificationFeedbackGenerator()

    init() { prepare() }

    private func prepare() {
        // Simulator or older devices may not support Core Haptics.
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    func pulse(intensity: Float, sharpness: Float, count: Int, spacing: TimeInterval) {
        // If custom haptics are unavailable, give a simple warning tap instead.
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine else {
            DispatchQueue.main.async { self.fallback.notificationOccurred(.warning) }
            return
        }

        var events: [CHHapticEvent] = []
        for k in 0..<max(1, count) {
            // Each event is a short transient pulse in the pattern.
            let t = Double(k) * spacing
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: t))
        }

        do {
            // Start the pattern immediately.
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // If the engine failed, prepare again for the next pulse.
            prepare()
        }
    }
}
