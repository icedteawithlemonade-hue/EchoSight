import Combine
import Foundation
import SwiftUI
import UIKit
import WatchConnectivity

enum ActivityKind: String, Codable, CaseIterable {
    case object
    case transcript
    case readText
    case morse
    case asl
    case practice
    case sound
    case system

    var title: String {
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
    var id = UUID()
    var kind: ActivityKind
    var title: String
    var detail: String
    var date = Date()
}

@MainActor
final class ActivityHistoryStore: ObservableObject {
    static let shared = ActivityHistoryStore()

    @Published private(set) var items: [ActivityItem] = []
    private let defaultsKey = "activity.history.items"
    private let maxItems = 80
    private let saveDebounce: TimeInterval = 0.8
    private var pendingSave: DispatchWorkItem?

    private init() {
        load()
    }

    func add(_ kind: ActivityKind, title: String, detail: String) {
        let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDetail.isEmpty else { return }

        if let latest = items.first,
           latest.kind == kind,
           latest.title == title,
           latest.detail == cleanedDetail,
           Date().timeIntervalSince(latest.date) < 10 {
            return
        }

        items.insert(ActivityItem(kind: kind, title: title, detail: cleanedDetail, date: Date()), at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        scheduleSave()
    }

    func recent(limit: Int = 8) -> [ActivityItem] {
        Array(items.prefix(limit))
    }

    func latest(kind: ActivityKind) -> ActivityItem? {
        items.first { $0.kind == kind }
    }

    func clear() {
        pendingSave?.cancel()
        pendingSave = nil
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ActivityItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func scheduleSave() {
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
    case asl
    case morse

    var id: String { rawValue }

    var title: String {
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
    var track: PracticeTrack
    var streak: Int = 0
    var completedLessons: Int = 0
    var achievements: [String] = []
    var lastPracticeDate: Date?
}

@MainActor
final class PracticeStore: ObservableObject {
    static let shared = PracticeStore()

    @Published private(set) var progress: [PracticeTrack: PracticeProgress] = [:]
    private let defaultsKey = "practice.progress"

    private init() {
        load()
    }

    func progress(for track: PracticeTrack) -> PracticeProgress {
        progress[track] ?? PracticeProgress(track: track)
    }

    var totalCompletedLessons: Int {
        progress.values.reduce(0) { $0 + $1.completedLessons }
    }

    var bestStreak: Int {
        progress.values.map(\.streak).max() ?? 0
    }

    func completeDailyLesson(track: PracticeTrack) {
        var item = progress(for: track)
        let calendar = Calendar.current
        let now = Date()

        if let last = item.lastPracticeDate {
            if calendar.isDateInToday(last) {
                ActivityHistoryStore.shared.add(.practice, title: "\(track.title) practiced", detail: "Daily lesson already counted today.")
                return
            } else if calendar.isDateInYesterday(last) {
                item.streak += 1
            } else {
                item.streak = 1
            }
        } else {
            item.streak = 1
        }

        item.completedLessons += 1
        item.lastPracticeDate = now
        item.achievements = achievements(for: item)
        progress[track] = item
        save()

        ActivityHistoryStore.shared.add(.practice, title: "\(track.title) lesson", detail: "Completed lesson \(item.completedLessons). Streak: \(item.streak) day\(item.streak == 1 ? "" : "s").")
        AssistAlertCenter.shared.alert(.practice, message: "\(track.title) practice complete")
    }

    private func achievements(for progress: PracticeProgress) -> [String] {
        var achievements: [String] = []
        if progress.completedLessons >= 1 { achievements.append("First lesson") }
        if progress.completedLessons >= 5 { achievements.append("Five lessons") }
        if progress.streak >= 3 { achievements.append("Three-day streak") }
        if progress.streak >= 7 { achievements.append("Weekly streak") }
        return achievements
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([PracticeTrack: PracticeProgress].self, from: data) else {
            progress = Dictionary(uniqueKeysWithValues: PracticeTrack.allCases.map { ($0, PracticeProgress(track: $0)) })
            return
        }
        progress = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum AssistAlertKind: String {
    case morse
    case obstacle
    case sound
    case practice
}

final class AssistAlertCenter: NSObject, WCSessionDelegate {
    static let shared = AssistAlertCenter()

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func alert(_ kind: AssistAlertKind, message: String) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(kind == .obstacle ? .warning : .success)

        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else {
            return
        }

        WCSession.default.transferUserInfo([
            "kind": kind.rawValue,
            "message": message,
            "date": Date().timeIntervalSince1970
        ])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
