import AppIntents
import Foundation

private enum IntentLauncher {
    @MainActor
    static func open(_ tile: StartupTile) {
        UserDefaults.standard.set(true, forKey: "startup.open.enabled")
        UserDefaults.standard.set(tile.rawValue, forKey: "startup.open.tile")
        ActivityHistoryStore.shared.add(.system, title: "Shortcut", detail: "Prepared \(tile.title) for launch.")
    }
}

struct StartEchoSightCameraIntent: AppIntent {
    static var title: LocalizedStringResource = "Start EchoSight Camera"
    static var description = IntentDescription("Open EchoSight directly to camera assist tools.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentLauncher.open(.camera)
        return .result()
    }
}

struct StartEchoSightMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Start EchoSight Mic"
    static var description = IntentDescription("Open EchoSight directly to mic assist tools.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentLauncher.open(.mic)
        return .result()
    }
}

struct StartEchoSightMorseIntent: AppIntent {
    static var title: LocalizedStringResource = "Start EchoSight Morse"
    static var description = IntentDescription("Open EchoSight directly to Morse communication.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentLauncher.open(.morse)
        return .result()
    }
}

struct StartEchoSightASLIntent: AppIntent {
    static var title: LocalizedStringResource = "Start EchoSight ASL"
    static var description = IntentDescription("Open EchoSight directly to ASL learning.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentLauncher.open(.asl)
        return .result()
    }
}

struct EchoSightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartEchoSightCameraIntent(),
            phrases: [
                "Start \(.applicationName) camera",
                "Open camera in \(.applicationName)"
            ],
            shortTitle: "Start Camera",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: StartEchoSightMicIntent(),
            phrases: [
                "Start \(.applicationName) mic",
                "Open mic in \(.applicationName)"
            ],
            shortTitle: "Start Mic",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StartEchoSightMorseIntent(),
            phrases: [
                "Start \(.applicationName) Morse",
                "Open Morse in \(.applicationName)"
            ],
            shortTitle: "Start Morse",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: StartEchoSightASLIntent(),
            phrases: [
                "Start \(.applicationName) ASL",
                "Open ASL in \(.applicationName)"
            ],
            shortTitle: "Start ASL",
            systemImageName: "hand.raised.fill"
        )
    }
}
