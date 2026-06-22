import Foundation

// Lightweight local sound-event detector.
// This is a heuristic layer over EQ/RMS data, not a trained audio classifier.
// It is designed to catch obvious events like knocks, beeps, alarms, and speech.
enum SoundEventType: String, CaseIterable {
    // Small set of obvious events this heuristic can infer from frequency/RMS.
    case knock
    case beep
    case alarm
    case siren
    case speech

    var displayName: String {
        switch self {
        case .knock: return "Knock"
        case .beep: return "Beep"
        case .alarm: return "Alarm"
        case .siren: return "Siren"
        case .speech: return "Speech"
        }
    }
}

struct SoundEvent: Identifiable {
    // UUID lets SwiftUI list events.
    let id = UUID()
    // Event category shown in the UI.
    let type: SoundEventType
    // Heuristic confidence 0...1.
    let confidence: Float
    // Timestamp used for recent-event filtering.
    let timestamp: Date
}

// Applies thresholds and cooldowns so the same sound does not spam the UI.
final class SoundEventService {
    struct Thresholds {
        // Per-event thresholds. Noisy mode multiplies these upward.
        var knock: Float = 0.28
        var beep: Float = 0.35
        var alarm: Float = 0.30
        var speech: Float = 0.25
    }

    // Cooldowns prevent one sound from generating repeated duplicate events.
    private let cooldowns: [SoundEventType: TimeInterval] = [
        .knock: 6,
        .beep: 5,
        .alarm: 10,
        .siren: 10,
        .speech: 4
    ]

    // Last event time by type for cooldown checks.
    private var lastEventTimes: [SoundEventType: Date] = [:]
    // Previous EQ bands let us detect sudden transients.
    private var lastBands: [Float] = Array(repeating: 0, count: 5)
    // Mid-energy history helps detect repeating siren/alarm patterns.
    private var energyHistory: [Float] = []
    private let historySize: Int = 24

    var noisyMode: Bool = false
    var thresholds = Thresholds()

    func process(bands: [Float], rms: Float, timestamp: Date) -> SoundEvent? {
        // Five bands are required: low, low-mid, mid, high-mid, high.
        guard bands.count >= 5 else { return nil }
        // Noisy mode raises thresholds so background noise triggers less often.
        let multiplier: Float = noisyMode ? 1.5 : 1.0

        // Group bands into rough frequency regions.
        let lowEnergy = bands[0] + bands[1]
        let midEnergy = bands[2] + bands[3]
        let highEnergy = bands[4]

        let lastLow = lastBands[0] + lastBands[1]
        let lastHigh = lastBands[4]

        // Transient means "how much did this region jump since last buffer?"
        let lowTransient = lowEnergy - lastLow
        let highTransient = highEnergy - lastHigh

        // Keep a rolling history for alarm/siren pattern checks.
        energyHistory.append(midEnergy)
        if energyHistory.count > historySize {
            energyHistory.removeFirst()
        }

        // Save current bands at the end no matter which branch returns.
        defer { lastBands = bands }

        if lowTransient > thresholds.knock * multiplier, lowEnergy > thresholds.knock * multiplier {
            // Knock is usually a sudden low-frequency transient.
            return emit(type: .knock, confidence: min(1, lowTransient / (thresholds.knock * multiplier)), at: timestamp)
        }

        if highTransient > thresholds.beep * multiplier, highEnergy > thresholds.beep * multiplier {
            // Beep is usually a sudden high-frequency transient.
            return emit(type: .beep, confidence: min(1, highTransient / (thresholds.beep * multiplier)), at: timestamp)
        }

        if let sirenEvent = detectSirenOrAlarm(energyHistory: energyHistory, threshold: thresholds.alarm * multiplier, at: timestamp) {
            // Repeating mid/high energy can indicate alarm or siren.
            return sirenEvent
        }

        if rms > thresholds.speech * multiplier {
            // Loud enough continuous sound is labeled speech as a simple fallback.
            return emit(type: .speech, confidence: min(1, rms / (thresholds.speech * multiplier)), at: timestamp)
        }

        return nil
    }

    private func detectSirenOrAlarm(energyHistory: [Float], threshold: Float, at timestamp: Date) -> SoundEvent? {
        // Need enough history before detecting repeating patterns.
        guard energyHistory.count >= historySize else { return nil }
        let avg = energyHistory.reduce(0, +) / Float(energyHistory.count)
        let maxVal = energyHistory.max() ?? 0
        let minVal = energyHistory.min() ?? 0
        let range = maxVal - minVal
        // Require both enough average energy and enough variation.
        guard avg > threshold, range > 0.08 else { return nil }

        // Multiple peaks suggest siren-like oscillation.
        let peaks = countPeaks(values: energyHistory, above: avg + range * 0.2)
        if peaks >= 2 {
            return emit(type: .siren, confidence: min(1, range * 2.5), at: timestamp)
        }
        return emit(type: .alarm, confidence: min(1, avg / threshold), at: timestamp)
    }

    private func countPeaks(values: [Float], above: Float) -> Int {
        // Count local maxima above a threshold.
        guard values.count > 2 else { return 0 }
        var peaks = 0
        for i in 1..<(values.count - 1) {
            let prev = values[i - 1]
            let current = values[i]
            let next = values[i + 1]
            if current > prev && current > next && current > above {
                peaks += 1
            }
        }
        return peaks
    }

    private func emit(type: SoundEventType, confidence: Float, at timestamp: Date) -> SoundEvent? {
        // Cooldown filter prevents spam for the same event type.
        if let last = lastEventTimes[type], timestamp.timeIntervalSince(last) < (cooldowns[type] ?? 0) {
            return nil
        }
        lastEventTimes[type] = timestamp
        return SoundEvent(type: type, confidence: confidence, timestamp: timestamp)
    }
}
