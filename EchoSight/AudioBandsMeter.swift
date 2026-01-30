import Foundation
import AVFoundation
import Accelerate
import Combine
import SwiftUI
import CoreHaptics
import UIKit

final class AudioBandsMeter: ObservableObject {
    // Published for UI
    @Published var bands: [Float] = Array(repeating: 0, count: 5)   // 0...1
    @Published var isRunning: Bool = false
    @Published var calibrated: Bool = false
    @Published var sensitivity: Float = 1.0  // 0.6...1.8 typical

    // Audio
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()

    // FFT (classic vDSP)
    private let fftSize: Int = 1024          // must be power of 2
    private var log2n: vDSP_Length { vDSP_Length(log2(Float(fftSize))) }
    private var fftSetup: FFTSetup?

    private var window: [Float] = []
    private var windowed: [Float] = []
    private var real: [Float] = []
    private var imag: [Float] = []
    private var mags: [Float] = []

    // 5 bands: Low / Low-mid / Mid / High-mid / High
    private let bandEdges: [Float] = [80, 250, 700, 2000, 6000, 12000] // 6 edges -> 5 bands

    // Calibration
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
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        // Window (Hann)
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
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
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
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false)
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Calibration

    func calibrate(seconds: TimeInterval = 2.0) {
        baselineAccum = Array(repeating: 0, count: 5)
        baselineCount = 0
        calibratingUntil = Date().addingTimeInterval(seconds)
        calibrated = false
    }

    // MARK: - Processing

    private func process(buffer: AVAudioPCMBuffer, sampleRate: Float) {
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
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        // Magnitude squared
        mags.withUnsafeMutableBufferPointer { mPtr in
            vDSP_zvmags(&split, 1, mPtr.baseAddress!, 1, vDSP_Length(fftSize / 2))
        }

        // Compute 5 bands
        let newBands = computeBands(from: mags, sampleRate: sampleRate)

        // Smooth for UI
        var smoothed = bands
        for i in 0..<5 {
            smoothed[i] = (1 - smoothingAlpha) * smoothed[i] + smoothingAlpha * newBands[i]
        }

        // Calibration update
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
        detectSpikesAndHaptics(smoothed)

        DispatchQueue.main.async {
            self.bands = smoothed
        }
    }

    private func computeBands(from mags: [Float], sampleRate: Float) -> [Float] {
        let binHz = sampleRate / Float(fftSize)
        var bandVals = Array(repeating: Float(0), count: 5)

        for b in 0..<5 {
            let f0 = bandEdges[b]
            let f1 = bandEdges[b + 1]
            let i0 = max(1, Int(f0 / binHz))
            let i1 = min(mags.count - 1, Int(f1 / binHz))
            if i1 <= i0 { continue }

            // Stable sum: just use a loop (avoids API mismatch on vDSP.sum signatures)
            var sum: Float = 0
            for i in i0..<i1 { sum += mags[i] }

            // Compress & normalize (tune divisor if needed)
            let compressed = log10(1 + sum)
            let normalized = min(1, compressed / 6.0)

            bandVals[b] = normalized
        }

        return bandVals
    }

    private func detectSpikesAndHaptics(_ current: [Float]) {
        let now = Date()
        let globalReady = now.timeIntervalSince(lastGlobalAlert) > globalCooldown

        for i in 0..<5 {
            let base = calibrated ? baseline[i] : 0
            let delta = current[i] - base

            let threshold = baseThreshold / max(0.3, sensitivity)

            if delta > threshold {
                if aboveSince[i] == nil { aboveSince[i] = now }

                let held = now.timeIntervalSince(aboveSince[i]!) >= minHoldTime
                let cooled = now.timeIntervalSince(lastAlertAt[i]) >= perBandCooldown

                if held && cooled && globalReady {
                    lastAlertAt[i] = now
                    lastGlobalAlert = now
                    fireHaptic(forBand: i, strength: delta)
                }
            } else if delta < max(0, threshold - hysteresis) {
                aboveSince[i] = nil
            }
        }
    }

    private func fireHaptic(forBand band: Int, strength: Float) {
        let intensity = min(1, max(0.2, strength * 1.5))

        switch band {
        case 0: haptics.pulse(intensity: intensity, sharpness: 0.2, count: 1, spacing: 0.0)   // Low
        case 1: haptics.pulse(intensity: intensity, sharpness: 0.4, count: 2, spacing: 0.12)  // Low-mid
        case 2: haptics.pulse(intensity: intensity, sharpness: 0.7, count: 3, spacing: 0.10)  // Mid (speech-ish)
        case 3: haptics.pulse(intensity: intensity, sharpness: 0.9, count: 2, spacing: 0.06)  // High-mid
        default: haptics.pulse(intensity: intensity * 0.9, sharpness: 1.0, count: 4, spacing: 0.05) // High
        }
    }
}

final class HapticsManager {
    private var engine: CHHapticEngine?
    private let fallback = UINotificationFeedbackGenerator()

    init() { prepare() }

    private func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    func pulse(intensity: Float, sharpness: Float, count: Int, spacing: TimeInterval) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine else {
            DispatchQueue.main.async { self.fallback.notificationOccurred(.warning) }
            return
        }

        var events: [CHHapticEvent] = []
        for k in 0..<max(1, count) {
            let t = Double(k) * spacing
            let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [i, s], relativeTime: t))
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            prepare()
        }
    }
}
