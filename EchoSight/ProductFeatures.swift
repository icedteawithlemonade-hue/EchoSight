import Combine
import Foundation
import SwiftUI
import UIKit
import WatchConnectivity

// ProductFeatures.swift holds shared product-level state:
// activity history, practice progress, and haptic/watch alerts.
// Keeping these here lets any screen log events without knowing the current UI.
enum ActivityKind: String, Codable, CaseIterable {
    // Categories used by ActivityHistoryPage.
    case object
    case transcript
    case readText
    case morse
    case asl
    case practice
    case sound
    case system

    var title: String {
        // Human-readable section/title label.
        switch self {
        case .object: return "Object"
        case .transcript: return "Transcript"
        case .readText: return "Read Text"
        case .morse: return "Morse"
        case .asl: return "ASL"
        case .practice: return "Practice"
        case .sound: return "Sound"
        case .system: return "System"
        }
    }

    var systemImage: String {
        // SF Symbols icon shown beside each activity item.
        switch self {
        case .object: return "viewfinder"
        case .transcript: return "captions.bubble.fill"
        case .readText: return "doc.text.viewfinder"
        case .morse: return "antenna.radiowaves.left.and.right"
        case .asl: return "hand.raised.fill"
        case .practice: return "target"
        case .sound: return "waveform"
        case .system: return "checkmark.seal.fill"
        }
    }
}

struct ActivityItem: Identifiable, Codable, Equatable {
    // Codable lets the local history save to UserDefaults as JSON.
    var id = UUID()
    var kind: ActivityKind
    var title: String
    var detail: String
    var date = Date()
}

@MainActor
// Persistent event log for detections, captions, read text, Morse, ASL,
// practice, and system actions. Saves are debounced to keep the UI smooth.
final class ActivityHistoryStore: ObservableObject {
    // Singleton is convenient because every feature can log activity.
    static let shared = ActivityHistoryStore()

    // private(set) means views can read items, but only the store mutates them.
    @Published private(set) var items: [ActivityItem] = []
    // UserDefaults key for JSON encoded activity history.
    private let defaultsKey = "activity.history.items"
    // Limit keeps local storage and list rendering small.
    private let maxItems = 80
    // Debounce avoids writing UserDefaults on every rapid detection frame.
    private let saveDebounce: TimeInterval = 0.8
    private var pendingSave: DispatchWorkItem?

    private init() {
        load()
    }

    func add(_ kind: ActivityKind, title: String, detail: String) {
        // Empty entries are ignored so history stays meaningful.
        let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDetail.isEmpty else { return }

        // Drop duplicates that happen within 10 seconds.
        if let latest = items.first,
           latest.kind == kind,
           latest.title == title,
           latest.detail == cleanedDetail,
           Date().timeIntervalSince(latest.date) < 10 {
            return
        }

        // Insert newest first for easier display.
        items.insert(ActivityItem(kind: kind, title: title, detail: cleanedDetail, date: Date()), at: 0)
        if items.count > maxItems {
            // Trim old items after maxItems.
            items = Array(items.prefix(maxItems))
        }
        scheduleSave()
    }

    func recent(limit: Int = 8) -> [ActivityItem] {
        // Helper for dashboard-style summaries.
        Array(items.prefix(limit))
    }

    func latest(kind: ActivityKind) -> ActivityItem? {
        // Find the most recent item of one category.
        items.first { $0.kind == kind }
    }

    func clear() {
        // Cancel pending delayed save, clear memory, then save empty array.
        pendingSave?.cancel()
        pendingSave = nil
        items = []
        save()
    }

    private func load() {
        // Load JSON from UserDefaults if it exists.
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ActivityItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        // Save as JSON data in UserDefaults. No network or database is involved.
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func scheduleSave() {
        // Keep only one pending save work item.
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.save()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounce, execute: work)
    }
}

enum PracticeTrack: String, Codable, CaseIterable, Identifiable {
    // Practice currently tracks ASL and Morse separately.
    case asl
    case morse

    var id: String { rawValue }

    var title: String {
        // Display title for cards and history entries.
        switch self {
        case .asl: return "ASL"
        case .morse: return "Morse"
        }
    }

    var systemImage: String {
        switch self {
        case .asl: return "hand.raised.fill"
        case .morse: return "dot.radiowaves.left.and.right"
        }
    }
}

struct PracticeProgress: Codable, Equatable {
    // Stored progress for one practice track.
    var track: PracticeTrack
    var streak: Int = 0
    var completedLessons: Int = 0
    var achievements: [String] = []
    var lastPracticeDate: Date?
}

@MainActor
// Tracks daily progress for ASL and Morse practice.
final class PracticeStore: ObservableObject {
    // Shared store so PracticeHub and feature screens see the same progress.
    static let shared = PracticeStore()

    // Dictionary keyed by track for fast lookup.
    @Published private(set) var progress: [PracticeTrack: PracticeProgress] = [:]
    private let defaultsKey = "practice.progress"

    private init() {
        load()
    }

    func progress(for track: PracticeTrack) -> PracticeProgress {
        // If the track has no saved data yet, return a fresh zero-progress item.
        progress[track] ?? PracticeProgress(track: track)
    }

    var totalCompletedLessons: Int {
        // Sum across all tracks for dashboard metric.
        progress.values.reduce(0) { $0 + $1.completedLessons }
    }

    var bestStreak: Int {
        // Highest streak across all tracks.
        progress.values.map(\.streak).max() ?? 0
    }

    func completeDailyLesson(track: PracticeTrack) {
        // Count at most one lesson per track per day for streak integrity.
        var item = progress(for: track)
        let calendar = Calendar.current
        let now = Date()

        if let last = item.lastPracticeDate {
            if calendar.isDateInToday(last) {
                // Already counted today, so only log a reminder.
                ActivityHistoryStore.shared.add(.practice, title: "\(track.title) practiced", detail: "Daily lesson already counted today.")
                return
            } else if calendar.isDateInYesterday(last) {
                // Consecutive day continues streak.
                item.streak += 1
            } else {
                // Gap resets streak.
                item.streak = 1
            }
        } else {
            // First ever practice starts a streak.
            item.streak = 1
        }

        // Update persisted progress.
        item.completedLessons += 1
        item.lastPracticeDate = now
        item.achievements = achievements(for: item)
        progress[track] = item
        save()

        // Log locally and trigger haptic/watch alert.
        ActivityHistoryStore.shared.add(.practice, title: "\(track.title) lesson", detail: "Completed lesson \(item.completedLessons). Streak: \(item.streak) day\(item.streak == 1 ? "" : "s").")
        AssistAlertCenter.shared.alert(.practice, message: "\(track.title) practice complete")
    }

    private func achievements(for progress: PracticeProgress) -> [String] {
        // Badge list is derived from progress instead of stored manually.
        var achievements: [String] = []
        if progress.completedLessons >= 1 { achievements.append("First lesson") }
        if progress.completedLessons >= 5 { achievements.append("Five lessons") }
        if progress.streak >= 3 { achievements.append("Three-day streak") }
        if progress.streak >= 7 { achievements.append("Weekly streak") }
        return achievements
    }

    private func load() {
        // Load saved progress or initialize both tracks.
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([PracticeTrack: PracticeProgress].self, from: data) else {
            progress = Dictionary(uniqueKeysWithValues: PracticeTrack.allCases.map { ($0, PracticeProgress(track: $0)) })
            return
        }
        progress = decoded
    }

    private func save() {
        // Persist progress locally as JSON.
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum AssistAlertKind: String {
    // Types are sent to Apple Watch so it can choose haptic style.
    case morse
    case obstacle
    case sound
    case practice
}

// Sends local haptics on iPhone and relays alert messages to Apple Watch
// when a companion watch app is available.
final class AssistAlertCenter: NSObject, WCSessionDelegate {
    // Shared alert center used by camera, mic, Morse, and practice features.
    static let shared = AssistAlertCenter()

    private override init() {
        super.init()
        if WCSession.isSupported() {
            // Activate WatchConnectivity only when supported.
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func alert(_ kind: AssistAlertKind, message: String) {
        // Always provide immediate phone haptic feedback.
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(kind == .obstacle ? .warning : .success)

        // Watch relay is optional and only runs when a companion watch app exists.
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else {
            return
        }

        // transferUserInfo queues delivery even if the watch is not immediately reachable.
        WCSession.default.transferUserInfo([
            "kind": kind.rawValue,
            "message": message,
            "date": Date().timeIntervalSince1970
        ])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Required by WatchConnectivity after deactivation.
        session.activate()
    }
}
