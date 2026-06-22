import Combine
import AVFoundation
import CoreHaptics
import SwiftUI
import UIKit
import WebKit

struct HomeView: View {
    @EnvironmentObject var flow: AppFlow
    @AppStorage("feature.camera.enabled") private var cameraEnabled: Bool = true
    @AppStorage("feature.mic.enabled") private var micEnabled: Bool = true
    @AppStorage("feature.browser.enabled") private var browserEnabled: Bool = true
    @AppStorage("feature.asl.enabled") private var aslEnabled: Bool = true
    @AppStorage("feature.morse.enabled") private var morseEnabled: Bool = true
    @AppStorage("startup.open.enabled") private var openOnStartup: Bool = false
    @AppStorage("startup.open.tile") private var startupTile: String = StartupTile.none.rawValue
    @AppStorage("theme.color") private var themeColorName: String = ThemeColor.blue.rawValue
    @State private var autoOpenTile: Bool = false
    @State private var didAutoOpen: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Assist Tools")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)

                    if cameraEnabled {
                        TileLink(title: "Camera", subtitle: "Recognize with camera", systemImage: "camera.viewfinder", destination: AnyView(CameraPage()))
                    }
                    if micEnabled {
                        TileLink(title: "Mic", subtitle: "Speak & listen", systemImage: "mic.fill", destination: AnyView(MicPage()))
                    }
                    if browserEnabled {
                        TileLink(title: "Browser", subtitle: "Browse content", systemImage: "safari.fill", destination: AnyView(BrowserPage()))
                    }
                    if aslEnabled {
                        TileLink(title: "ASL Learning", subtitle: "Learn American Sign Language", systemImage: "hand.raised.fill", destination: AnyView(ASLAlphabetPage()))
                    }
                    if morseEnabled {
                        TileLink(title: "Morse Communicator", subtitle: "communicate in morse signals", systemImage: "antenna.radiowaves.left.and.right", destination: AnyView(MorseCommunicatorPage()))
                    }
                    TileLink(title: "Practice", subtitle: "Daily ASL and Morse lessons", systemImage: "target", destination: AnyView(PracticeHubPage()))

                    Text("More")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                        .padding(.top, 4)

                    TileLink(title: "Activity History", subtitle: "Recent detections, captions, and practice", systemImage: "clock.arrow.circlepath", destination: AnyView(ActivityHistoryPage()))
                    TileLink(title: "Settings", subtitle: "App preferences", systemImage: "gearshape.fill", iconColor: .red, destination: AnyView(SettingsPage()))
                    TileLink(title: "Accessibility", subtitle: "Accessibility options", systemImage: "figure.stand.line.dotted.figure.stand", iconColor: .red, destination: AnyView(AccessibilityPage()))
                    TileLink(title: "Tutorial", subtitle: "View the tutorial again", systemImage: "book.pages.fill", iconColor: .red, destination: AnyView(TutorialHubPage()))
                    TileLink(title: "About", subtitle: "Learn about EchoSight", systemImage: "info.circle.fill", iconColor: .red, destination: AnyView(AboutPage()))
                }
                .padding()
                .padding(.top, 8)
            }
            .navigationTitle("EchoSight")
            .background(EchoSightBackground())
            .background(
                NavigationLink(destination: startupDestination, isActive: $autoOpenTile) {
                    EmptyView()
                }
                .hidden()
            )
            .tint(themeColor)
            .onAppear {
                guard openOnStartup, !didAutoOpen else { return }
                didAutoOpen = true
                if startupIsAvailable {
                    autoOpenTile = true
                }
            }
        }
    }

    private var startupSelection: StartupTile {
        StartupTile(rawValue: startupTile) ?? .none
    }

    private var startupIsAvailable: Bool {
        switch startupSelection {
        case .none:
            return false
        case .camera:
            return cameraEnabled
        case .mic:
            return micEnabled
        case .browser:
            return browserEnabled
        case .asl:
            return aslEnabled
        case .morse:
            return morseEnabled
        }
    }

    @ViewBuilder
    private var startupDestination: some View {
        switch startupSelection {
        case .camera:
            CameraPage()
        case .mic:
            MicPage()
        case .browser:
            BrowserPage()
        case .asl:
            ASLAlphabetPage()
        case .morse:
            MorseCommunicatorPage()
        case .none:
            EmptyView()
        }
    }

    private var themeColor: Color {
        ThemeColor(rawValue: themeColorName)?.color ?? .blue
    }
}

enum StartupTile: String, CaseIterable, Identifiable {
    case none
    case camera
    case mic
    case browser
    case asl
    case morse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .camera:
            return "Camera"
        case .mic:
            return "Mic"
        case .browser:
            return "Browser"
        case .asl:
            return "ASL Learning"
        case .morse:
            return "Morse Communicator"
        }
    }
}

enum ThemeColor: String, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case teal
    case pink
    case purple
    case indigo
    case red

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .teal: return "Teal"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .indigo: return "Indigo"
        case .red: return "Red"
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .teal: return .teal
        case .pink: return .pink
        case .purple: return .purple
        case .indigo: return .indigo
        case .red: return .red
        }
    }
}

private struct AppThemeColorKey: EnvironmentKey {
    static let defaultValue: Color = .blue
}

extension EnvironmentValues {
    var appThemeColor: Color {
        get { self[AppThemeColorKey.self] }
        set { self[AppThemeColorKey.self] = newValue }
    }
}

private struct EchoSightBackground: View {
    @Environment(\.appThemeColor) private var appThemeColor

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    appThemeColor.opacity(0.10),
                    Color(.systemGroupedBackground).opacity(0.0),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct DashboardStatusCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.12)))
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct OfflinePrivacyCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Offline-first privacy")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text("Camera detection, OCR, Morse, ASL learning, and mic analysis are designed to run on device. No images are uploaded by these tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct AppearOnLoad: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 10)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: visible)
            .onAppear {
                visible = true
            }
    }
}

private struct TileLink: View {
    @AppStorage("accessibility.simplifiedUI") private var simplifiedUI: Bool = false
    @AppStorage("accessibility.simplifiedUI.includeRed") private var simplifyRedTiles: Bool = false
    @Environment(\.appThemeColor) private var appThemeColor

    let title: String
    let subtitle: String
    let systemImage: String
    let destination: AnyView
    let iconColor: Color?

    init(title: String, subtitle: String, systemImage: String, iconColor: Color? = nil, destination: AnyView) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination
        self.iconColor = iconColor
    }

    var body: some View {
        NavigationLink(destination: destination) {
            if simplifiedUI {
                if iconColor == nil {
                    // Simplified UI for blue tiles: taller tile with enlarged icon and no subtitle
                    VStack(spacing: 12) {
                        Image(systemName: systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(.white)
                        Text(title)
                            .font(.system(size: 34, weight: .bold))
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(appThemeColor)
                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if simplifyRedTiles {
                    // Simplified UI for red tiles when allowed: no icon/subtitle, large title with red background
                    HStack {
                        Text(title)
                            .font(.system(size: 34, weight: .bold))
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.red)
                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                    )
                    .foregroundStyle(.white)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    // Simplified is on but red tiles not simplified: show normal layout
                    HStack(spacing: 16) {
                        if let iconColor {
                            Image(systemName: systemImage)
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 40, weight: .semibold))
                                .frame(width: 56, height: 56)
                                .foregroundStyle(iconColor)
                                .background(Circle().fill(iconColor.opacity(0.12)))
                        } else {
                            Image(systemName: systemImage)
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 40, weight: .semibold))
                                .frame(width: 56, height: 56)
                                .foregroundStyle(.tint)
                                .background(Circle().fill(appThemeColor.opacity(0.12)))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                            Text(subtitle)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.secondary.opacity(0.15), lineWidth: 2)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else {
                // Normal layout (icons + subtitle)
                HStack(spacing: 16) {
                    if let iconColor {
                        Image(systemName: systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 40, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .foregroundStyle(iconColor)
                            .background(Circle().fill(iconColor.opacity(0.12)))
                    } else {
                        Image(systemName: systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 40, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .foregroundStyle(.tint)
                            .background(Circle().fill(appThemeColor.opacity(0.12)))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                        Text(subtitle)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.15), lineWidth: 2)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .buttonStyle(CardPressButtonStyle())
        .modifier(AppearOnLoad())
    }
}

private struct ActionTile: View {
    @AppStorage("accessibility.simplifiedUI") private var simplifiedUI: Bool = false
    @AppStorage("accessibility.simplifiedUI.includeRed") private var simplifyRedTiles: Bool = false
    @Environment(\.appThemeColor) private var appThemeColor

    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    let iconColor: Color?

    init(title: String, subtitle: String, systemImage: String, iconColor: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action
        self.iconColor = iconColor
    }

    var body: some View {
        Button(action: action) {
            if simplifiedUI && (iconColor == nil || simplifyRedTiles) {
                HStack {
                    Text(title)
                        .font(.system(size: 34, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(iconColor == nil ? appThemeColor : Color.red)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                )
                .foregroundStyle(.white)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                HStack(spacing: 16) {
                    if let iconColor {
                        Image(systemName: systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 40, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .foregroundStyle(iconColor)
                            .background(Circle().fill(iconColor.opacity(0.12)))
                    } else {
                        Image(systemName: systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 40, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .foregroundStyle(.tint)
                            .background(Circle().fill(appThemeColor.opacity(0.12)))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                        Text(subtitle)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.15), lineWidth: 2)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .buttonStyle(CardPressButtonStyle())
        .modifier(AppearOnLoad())
    }
}

struct ActivityHistoryPage: View {
    @StateObject private var history = ActivityHistoryStore.shared

    var body: some View {
        List {
            Section {
                if history.items.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "clock",
                        description: Text("Detections, captions, read text, Morse, ASL, and practice sessions will appear here.")
                    )
                } else {
                    ForEach(history.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.kind.systemImage)
                                .font(.headline)
                                .foregroundStyle(.tint)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    Spacer()
                                    Text(item.date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Recent Activity")
            }
        }
        .navigationTitle("Activity History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.items.isEmpty {
                Button("Clear") {
                    history.clear()
                }
            }
        }
    }
}

struct PracticeHubPage: View {
    @StateObject private var practice = PracticeStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PracticeSummaryCard(practice: practice)
                ForEach(PracticeTrack.allCases) { track in
                    PracticeTrackCard(track: track, progress: practice.progress(for: track)) {
                        practice.completeDailyLesson(track: track)
                    }
                }
                OfflinePrivacyCard()
            }
            .padding()
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .background(EchoSightBackground())
    }
}

private struct PracticeSummaryCard: View {
    @ObservedObject var practice: PracticeStore

    var body: some View {
        HStack(spacing: 12) {
            DashboardStatusCard(title: "Lessons", detail: "\(practice.totalCompletedLessons) complete", systemImage: "checkmark.seal.fill", tint: .green)
            DashboardStatusCard(title: "Best Streak", detail: "\(practice.bestStreak) days", systemImage: "flame.fill", tint: .orange)
        }
    }
}

private struct PracticeTrackCard: View {
    let track: PracticeTrack
    let progress: PracticeProgress
    let complete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: track.systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(track.title) Daily Lesson")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(nextLesson)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                PracticeMiniMetricCard(value: "\(progress.completedLessons)", label: "lessons", systemImage: "checkmark")
                PracticeMiniMetricCard(value: "\(progress.streak)", label: "streak", systemImage: "flame.fill")
                PracticeMiniMetricCard(value: "\(progress.achievements.count)", label: "badges", systemImage: "rosette")
            }

            Button {
                complete()
            } label: {
                Label("Complete today's lesson", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressableButtonStyle(prominent: true))

            if !progress.achievements.isEmpty {
                Text("Achievements: \(progress.achievements.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var nextLesson: String {
        switch track {
        case .asl:
            return "Practice 5 signs, then review one phrase."
        case .morse:
            return "Practice 5 letters, then play one word."
        }
    }
}

private struct PracticeMiniMetricCard: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CameraPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TileLink(
                    title: "Object Detection",
                    subtitle: "Detect objects and announce direction",
                    systemImage: "viewfinder",
                    destination: AnyView(ObjectDetectionPage())
                )
                TileLink(
                    title: "Text Reader (OCR)",
                    subtitle: "Capture text and read aloud",
                    systemImage: "doc.text.viewfinder",
                    destination: AnyView(TextReaderPage())
                )
                TileLink(
                    title: "Currency Identifier",
                    subtitle: "Identify denominations offline",
                    systemImage: "dollarsign.circle",
                    destination: AnyView(CurrencyIdentifierPage())
                )
                TileLink(
                    title: "Nearby People Detection",
                    subtitle: "Describe relative position only",
                    systemImage: "person.2.circle",
                    destination: AnyView(NearbyPeoplePage())
                )
                TileLink(
                    title: "Crosswalk Signal Detection",
                    subtitle: "Walk / Do Not Walk status",
                    systemImage: "figure.walk",
                    destination: AnyView(CrosswalkSignalPage())
                )
                TileLink(
                    title: "Path Guidance (Experimental)",
                    subtitle: "Simple left/right guidance",
                    systemImage: "arrow.left.and.right.circle",
                    destination: AnyView(PathGuidancePage())
                )
            }
            .padding()
        }
        .navigationTitle("Camera Accessibility")
        .navigationBarTitleDisplayMode(.inline)
        .background(EchoSightBackground())
    }
}

// MARK: - Camera Accessibility Features
private struct CameraPreviewCard: View {
    @ObservedObject var camera: CameraManager
    let title: String

    var body: some View {
        ZStack {
            if let cameraError = camera.cameraError {
                VStack(spacing: 8) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(cameraError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if camera.isAuthorized, camera.hasCameraInput {
                CameraPreview(session: camera.session)
                    .accessibilityLabel(title)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Camera access is required.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CameraStatusCard: View {
    let title: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct DiagnosticsOverlay: View {
    let info: DiagnosticsInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diagnostics")
                .font(.caption.weight(.semibold))
            Text("Model: \(info.modelName)")
                .font(.caption2)
            Text("FPS: \(String(format: "%.1f", info.fps))")
                .font(.caption2)
            Text("Inference: \(String(format: "%.1f", info.inferenceMs)) ms")
                .font(.caption2)
            Text("Compute: \(info.computeUnits)")
                .font(.caption2)
            Text("ANE Allowed: \(info.usesNeuralEngine ? "Yes" : "No")")
                .font(.caption2)
            if !info.topDetections.isEmpty {
                Text("Top: \(info.topDetections.joined(separator: ", "))")
                    .font(.caption2)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PressableButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: prominent ? 0 : 1)
            )
            .foregroundStyle(foregroundColor)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @Environment(\.appThemeColor) private var appThemeColor

    private var borderColor: Color {
        appThemeColor.opacity(0.35)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if prominent {
            return appThemeColor.opacity(pressed ? 0.75 : 1.0)
        }
        return pressed ? appThemeColor.opacity(0.15) : Color(.systemBackground)
    }

    private var foregroundColor: Color {
        prominent ? .white : .primary
    }
}

struct ObjectDetectionPage: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel = ObjectDetectionViewModel()
    @StateObject private var announcer = AnnouncementController()
    @State private var audioFeedback: Bool = true
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    CameraPreviewCard(camera: camera, title: "Object Detection Preview")
                    if showDiagnostics {
                        DiagnosticsOverlay(info: viewModel.diagnostics)
                            .padding(12)
                    }
                }
                CameraStatusCard(title: "Detected Object", status: viewModel.statusText)
                Toggle("Audio feedback", isOn: $audioFeedback)
                    .padding(.horizontal)
                Toggle("Show diagnostics", isOn: $showDiagnostics)
                    .padding(.horizontal)
                Text("On-device only. No images leave your device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Object Detection")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.diagnosticsEnabled = showDiagnostics
            camera.configure()
            camera.onSampleBuffer = { [weak viewModel] sample in
                viewModel?.process(sampleBuffer: sample)
            }
            camera.start()
        }
        .onChange(of: showDiagnostics) { enabled in
            viewModel.diagnosticsEnabled = enabled
        }
        .onChange(of: viewModel.statusText) { newValue in
            guard !newValue.localizedCaseInsensitiveContains("looking"),
                  !newValue.localizedCaseInsensitiveContains("no clear") else {
                return
            }
            ActivityHistoryStore.shared.add(.object, title: "Object Detection", detail: newValue)
            if audioFeedback {
                announcer.announce(newValue)
            }
        }
        .onChange(of: camera.isAuthorized) { authorized in
            if authorized { camera.start() }
        }
        .onDisappear {
            camera.onSampleBuffer = nil
            camera.stop()
            announcer.stop()
        }
    }
}

struct TextReaderPage: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var speech = SpeechAnnouncer()
    @StateObject private var viewModel = TextReaderViewModel()
    @State private var audioFeedback: Bool = true
    @State private var speechRate: Double = 0.5
    @State private var speechPitch: Double = 1.0
    @State private var speechVolume: Double = 1.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CameraPreviewCard(camera: camera, title: "Text Reader Preview")

                Button {
                    viewModel.capture()
                } label: {
                    Label("Capture Text", systemImage: "camera.circle")
                }
                .buttonStyle(PressableButtonStyle(prominent: true))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recognized Text")
                        .font(.headline)
                    Text(viewModel.recognizedText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )

                HStack(spacing: 12) {
                    Button {
                        speech.speak(viewModel.recognizedText, rate: speechRate, pitch: speechPitch, volume: speechVolume)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(PressableButtonStyle(prominent: true))
                    Button {
                        speech.pause()
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    .buttonStyle(PressableButtonStyle(prominent: false))
                    Button {
                        speech.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(PressableButtonStyle(prominent: false))
                }

                Toggle("Auto read after capture", isOn: $audioFeedback)
                    .padding(.horizontal)
                MorseSettingSlider(title: "Speech rate", value: $speechRate, range: 0.3...0.7, suffix: "")
                MorseSettingSlider(title: "Speech pitch", value: $speechPitch, range: 0.7...1.3, suffix: "")
                MorseSettingSlider(title: "Speech volume", value: $speechVolume, range: 0.2...1.0, suffix: "")
                Text("On-device only. OCR runs locally using Vision.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                // TODO: Fine-tune Vision text recognition and post-processing.
            }
            .padding()
        }
        .navigationTitle("Text Reader")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onAppear {
            camera.configure()
            camera.onSampleBuffer = { [weak viewModel] sample in
                viewModel?.update(sampleBuffer: sample)
            }
            camera.start()
        }
        .onChange(of: viewModel.recognizedText) { newValue in
            ActivityHistoryStore.shared.add(.readText, title: "Text Reader", detail: newValue)
            if audioFeedback {
                speech.speak(newValue, rate: speechRate, pitch: speechPitch, volume: speechVolume, debounce: true)
            }
        }
        .onChange(of: speechRate) { _ in
            speech.restartIfSpeaking(rate: speechRate, pitch: speechPitch, volume: speechVolume)
        }
        .onChange(of: speechPitch) { _ in
            speech.restartIfSpeaking(rate: speechRate, pitch: speechPitch, volume: speechVolume)
        }
        .onChange(of: speechVolume) { _ in
            speech.restartIfSpeaking(rate: speechRate, pitch: speechPitch, volume: speechVolume)
        }
        .onChange(of: camera.isAuthorized) { authorized in
            if authorized { camera.start() }
        }
        .onDisappear {
            camera.onSampleBuffer = nil
            camera.stop()
            speech.stop()
        }
    }
}

struct CurrencyIdentifierPage: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel = CurrencyIdentifierViewModel()
    @StateObject private var announcer = AnnouncementController()
    @State private var audioFeedback: Bool = true
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    CameraPreviewCard(camera: camera, title: "Currency Identifier Preview")
                    if showDiagnostics {
                        DiagnosticsOverlay(info: viewModel.diagnostics)
                            .padding(12)
                    }
                }
                CameraStatusCard(title: "Denomination", status: viewModel.statusText)
                Toggle("Audio feedback", isOn: $audioFeedback)
                    .padding(.horizontal)
                Toggle("Show diagnostics", isOn: $showDiagnostics)
                    .padding(.horizontal)
                Text("On-device only. No images leave your device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Text("Uses the bundled classifier when available; otherwise OCR confirms denomination text and numbers across frames.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Currency Identifier")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.diagnosticsEnabled = showDiagnostics
            camera.configure()
            camera.onSampleBuffer = { [weak viewModel] sample in
                viewModel?.update(sampleBuffer: sample)
            }
            camera.start()
        }
        .onChange(of: showDiagnostics) { enabled in
            viewModel.diagnosticsEnabled = enabled
        }
        .onChange(of: viewModel.statusText) { newValue in
            guard newValue.hasPrefix("Detected: $") else { return }
            ActivityHistoryStore.shared.add(.object, title: "Currency Identifier", detail: newValue)
            if audioFeedback {
                announcer.announce(newValue)
            }
        }
        .onChange(of: camera.isAuthorized) { authorized in
            if authorized { camera.start() }
        }
        .onDisappear {
            camera.onSampleBuffer = nil
            camera.stop()
            announcer.stop()
        }
    }
}

struct NearbyPeoplePage: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel = PeopleDetectionViewModel()
    @StateObject private var announcer = AnnouncementController()
    @State private var audioFeedback: Bool = true
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    CameraPreviewCard(camera: camera, title: "Nearby People Preview")
                    if showDiagnostics {
                        DiagnosticsOverlay(info: viewModel.diagnostics)
                            .padding(12)
                    }
                }
                CameraStatusCard(title: "Relative Position", status: viewModel.statusText)
                Toggle("Audio feedback", isOn: $audioFeedback)
                    .padding(.horizontal)
                Toggle("Show diagnostics", isOn: $showDiagnostics)
                    .padding(.horizontal)
                Text("No face recognition or tracking. Only relative positions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                // TODO: Integrate Vision person detection and relative position only.
            }
            .padding()
        }
        .navigationTitle("Nearby People")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.diagnosticsEnabled = showDiagnostics
            camera.configure()
            camera.onSampleBuffer = { [weak viewModel] sample in
                viewModel?.process(sampleBuffer: sample)
            }
            camera.start()
        }
        .onChange(of: showDiagnostics) { enabled in
            viewModel.diagnosticsEnabled = enabled
        }
        .onChange(of: viewModel.statusText) { newValue in
            ActivityHistoryStore.shared.add(.object, title: "Nearby People", detail: newValue)
            if audioFeedback {
                announcer.announce(newValue)
            }
        }
        .onChange(of: camera.isAuthorized) { authorized in
            if authorized { camera.start() }
        }
        .onDisappear {
            camera.onSampleBuffer = nil
            camera.stop()
            announcer.stop()
        }
    }
}

struct CrosswalkSignalPage: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel = CrosswalkSignalViewModel()
    @StateObject private var announcer = AnnouncementController()
    @State private var audioFeedback: Bool = true
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    CameraPreviewCard(camera: camera, title: "Crosswalk Signal Preview")
                    if showDiagnostics {
                        DiagnosticsOverlay(info: viewModel.diagnostics)
                            .padding(12)
                    }
                }
                CameraStatusCard(title: "Crosswalk Signal", status: viewModel.statusText)
                Toggle("Audio feedback", isOn: $audioFeedback)
                    .padding(.horizontal)
                Toggle("Show diagnostics", isOn: $showDiagnostics)
                    .padding(.horizontal)
                Text("On-device only. No video is stored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                // TODO: Integrate Vision/Core ML model for crosswalk signal detection.
            }
            .padding()
        }
        .navigationTitle("Crosswalk Signal")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.diagnosticsEnabled = showDiagnostics
            camera.configure()
            camera.onSampleBuffer = { [weak viewModel] sample in
                viewModel?.process(sampleBuffer: sample)
            }
            camera.start()
        }
        .onChange(of: showDiagnostics) { enabled in
            viewModel.diagnosticsEnabled = enabled
        }
        .onChange(of: viewModel.statusText) { newValue in
            ActivityHistoryStore.shared.add(.object, title: "Crosswalk Signal", detail: newValue)
            if audioFeedback {
                announcer.announce(newValue)
            }
        }
        .onChange(of: camera.isAuthorized) { authorized in
            if authorized { camera.start() }
        }
        .onDisappear {
            camera.onSampleBuffer = nil
            camera.stop()
            announcer.stop()
        }
    }
}

struct PathGuidancePage: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel = PathGuidanceViewModel()
    @StateObject private var announcer = AnnouncementController()
    @State private var audioFeedback: Bool = true
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    CameraPreviewCard(camera: camera, title: "Path Guidance Preview")
                    if showDiagnostics {
                        DiagnosticsOverlay(info: viewModel.diagnostics)
                            .padding(12)
                    }
                }
                CameraStatusCard(title: "Guidance (Experimental)", status: viewModel.statusText)
                Toggle("Audio feedback", isOn: $audioFeedback)
                    .padding(.horizontal)
                Toggle("Show diagnostics", isOn: $showDiagnostics)
                    .padding(.horizontal)
                Text("Experimental feature. Guidance is approximate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                // TODO: Integrate path guidance model and safety checks.
            }
            .padding()
        }
        .navigationTitle("Path Guidance")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.diagnosticsEnabled = showDiagnostics
            camera.configure()
            camera.onSampleBuffer = { [weak viewModel] sample in
                viewModel?.process(sampleBuffer: sample)
            }
            camera.start()
        }
        .onChange(of: showDiagnostics) { enabled in
            viewModel.diagnosticsEnabled = enabled
        }
        .onChange(of: viewModel.statusText) { newValue in
            ActivityHistoryStore.shared.add(.object, title: "Path Guidance", detail: newValue)
            if newValue.localizedCaseInsensitiveContains("left") || newValue.localizedCaseInsensitiveContains("right") {
                AssistAlertCenter.shared.alert(.obstacle, message: newValue)
            }
            if audioFeedback {
                announcer.announce(newValue)
            }
        }
        .onChange(of: camera.isAuthorized) { authorized in
            if authorized { camera.start() }
        }
        .onDisappear {
            camera.onSampleBuffer = nil
            camera.stop()
            announcer.stop()
        }
    }
}


struct MicPage: View {
    @StateObject private var viewModel = MicViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MicTileView(viewModel: viewModel)
            }
            .padding()
        }
        .navigationTitle("Mic")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MorseCommunicatorPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TileLink(
                    title: "How to Use Morse",
                    subtitle: "Learn dots, dashes, and spacing",
                    systemImage: "questionmark.circle.fill",
                    destination: AnyView(MorseTutorialPage())
                )
                TileLink(
                    title: "Morse Input",
                    subtitle: "Tap to translate into text",
                    systemImage: "hand.tap.fill",
                    destination: AnyView(MorseInputPage())
                )
                TileLink(
                    title: "Morse Output",
                    subtitle: "Type text to play vibrations",
                    systemImage: "waveform.path.ecg",
                    destination: AnyView(MorseOutputPage())
                )
                TileLink(
                    title: "Morse Practice",
                    subtitle: "Daily streaks and lessons",
                    systemImage: "target",
                    destination: AnyView(PracticeHubPage())
                )
                TileLink(
                    title: "Morse Letters",
                    subtitle: "Browse A–Z symbols",
                    systemImage: "textformat.abc",
                    destination: AnyView(MorseLettersPage())
                )
                TileLink(
                    title: "Morse Numbers",
                    subtitle: "Browse 0–9 symbols",
                    systemImage: "number",
                    destination: AnyView(MorseNumbersPage())
                )
            }
            .padding()
        }
        .navigationTitle("Morse Communicator")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

struct MorseInputPage: View {
    @State private var currentSymbols: String = ""
    @State private var outputText: String = ""
    @State private var rawStream: String = ""
    @State private var isPressing: Bool = false
    @State private var pressStart: Date?
    @State private var letterCommitWork: DispatchWorkItem?
    @State private var wordCommitWork: DispatchWorkItem?

    @State private var dotThreshold: Double = 0.18
    @State private var dashThreshold: Double = 0.35
    @State private var letterGap: Double = 0.6
    @State private var wordGap: Double = 1.2
    @AppStorage("morse.input.haptic.dot") private var hapticDotEnabled: Bool = true
    @AppStorage("morse.input.haptic.dash") private var hapticDashEnabled: Bool = true
    @Environment(\.appThemeColor) private var appThemeColor

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap to enter Morse")
                        .font(.headline)
                    Text("Short tap = dot, long press = dash. Pauses separate letters and words.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isPressing ? appThemeColor.opacity(0.2) : Color.secondary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(appThemeColor.opacity(0.2), lineWidth: 1)
                        )
                        .frame(height: 240)

                    VStack(spacing: 8) {
                        Text(isPressing ? "Release to finish tap" : "Tap and hold here")
                            .font(.title3.weight(.semibold))
                        Text(currentSymbols.isEmpty ? "Current input: —" : "Current input: \(currentSymbols)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPressing {
                                beginPress()
                            }
                        }
                        .onEnded { _ in
                            endPress()
                        }
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Output")
                            .font(.headline)
                        Spacer()
                        Button("Reset") {
                            resetOutput()
                        }
                        .buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Raw stream")
                            .font(.subheadline.weight(.semibold))
                        Text(rawStreamDisplay())
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Decoded text")
                            .font(.subheadline.weight(.semibold))
                        Text(outputText.isEmpty ? "Output will appear here as you tap." : outputText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.secondary.opacity(0.2), lineWidth: 1)
                            )
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Input Settings")
                        .font(.headline)

                    MorseSettingSlider(
                        title: "Dot max duration",
                        value: $dotThreshold,
                        range: 0.05...0.4,
                        suffix: "s"
                    )
                    MorseSettingSlider(
                        title: "Dash min duration",
                        value: $dashThreshold,
                        range: 0.2...0.9,
                        suffix: "s"
                    )
                    MorseSettingSlider(
                        title: "Letter gap",
                        value: $letterGap,
                        range: 0.2...1.5,
                        suffix: "s"
                    )
                    MorseSettingSlider(
                        title: "Word gap",
                        value: $wordGap,
                        range: 0.6...2.5,
                        suffix: "s"
                    )
                    Toggle("Haptic tick for dots", isOn: $hapticDotEnabled)
                    Toggle("Haptic tick for dashes", isOn: $hapticDashEnabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .padding()
        }
        .navigationTitle("Morse Input")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onChange(of: dotThreshold) { newValue in
            if newValue >= dashThreshold - 0.05 {
                dotThreshold = max(0.05, dashThreshold - 0.05)
            }
        }
        .onChange(of: dashThreshold) { newValue in
            if newValue <= dotThreshold + 0.05 {
                dashThreshold = min(0.9, dotThreshold + 0.05)
            }
        }
    }

    private func beginPress() {
        isPressing = true
        pressStart = Date()
        letterCommitWork?.cancel()
        wordCommitWork?.cancel()
    }

    private func endPress() {
        guard let start = pressStart else {
            isPressing = false
            return
        }
        let duration = Date().timeIntervalSince(start)
        let symbol = classifySymbol(duration: duration)
        currentSymbols.append(symbol)
        triggerInputHaptic(for: symbol)
        isPressing = false
        scheduleCommitTimers()
    }

    private func classifySymbol(duration: TimeInterval) -> String {
        if duration <= dotThreshold {
            return "."
        }
        if duration >= dashThreshold {
            return "-"
        }
        let midpoint = (dotThreshold + dashThreshold) / 2
        return duration < midpoint ? "." : "-"
    }

    private func scheduleCommitTimers() {
        letterCommitWork?.cancel()
        wordCommitWork?.cancel()

        let letterWork = DispatchWorkItem {
            commitCurrentSymbols()
        }
        let wordWork = DispatchWorkItem {
            commitCurrentSymbols()
            if !outputText.hasSuffix(" "), !outputText.isEmpty {
                outputText.append(" ")
            }
            if !rawStream.hasSuffix(" / "), !rawStream.isEmpty {
                rawStream.append(" / ")
            }
        }

        letterCommitWork = letterWork
        wordCommitWork = wordWork
        DispatchQueue.main.asyncAfter(deadline: .now() + letterGap, execute: letterWork)
        DispatchQueue.main.asyncAfter(deadline: .now() + wordGap, execute: wordWork)
    }

    private func commitCurrentSymbols() {
        guard !currentSymbols.isEmpty else { return }
        if !rawStream.isEmpty, !rawStream.hasSuffix(" / ") {
            rawStream.append(" ")
        }
        rawStream.append(currentSymbols)
        if let character = MorseCodeMap.shared.character(for: currentSymbols) {
            outputText.append(character)
            ActivityHistoryStore.shared.add(.morse, title: "Morse Input", detail: "Decoded \(currentSymbols) as \(character)")
        } else {
            outputText.append("?")
            ActivityHistoryStore.shared.add(.morse, title: "Morse Input", detail: "Unknown symbol \(currentSymbols)")
        }
        currentSymbols = ""
    }

    private func resetOutput() {
        currentSymbols = ""
        outputText = ""
        rawStream = ""
        letterCommitWork?.cancel()
        wordCommitWork?.cancel()
    }

    private func rawStreamDisplay() -> String {
        let combined = rawStream + currentSymbols
        return combined.isEmpty ? "—" : combined
    }

    private func triggerInputHaptic(for symbol: String) {
        switch symbol {
        case ".":
            guard hapticDotEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case "-":
            guard hapticDashEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        default:
            break
        }
    }
}

struct MorseOutputPage: View {
    @State private var textToPlay: String = ""
    @State private var selectedWordIndex: Int = 0
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackStatus: PlaybackStatus = .stopped
    @State private var playbackPosition = PlaybackPosition()
    @State private var playbackToken: Int = 0
    @State private var settings = MorsePlaybackSettings()
    @FocusState private var editorFocused: Bool
    @StateObject private var haptics = MorseHaptics()
    @Environment(\.appThemeColor) private var appThemeColor

    var body: some View {
        let words = parsedWords()
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Type text to play as Morse")
                        .font(.headline)
                    TextEditor(text: $textToPlay)
                        .frame(minHeight: 140)
                        .focused($editorFocused)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                                )
                        )
                    Text("Your text will be converted into dots and dashes and played using haptics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Playback")
                        .font(.headline)
                    HStack {
                        Spacer()
                        HStack(spacing: 16) {
                            Button {
                                moveToPreviousWord(in: words)
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                togglePlayback(words: words)
                            } label: {
                                Image(systemName: playbackStatus == .playing ? "pause.fill" : "play.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                moveToNextWord(in: words)
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Now playing")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(currentPlaybackLabel(words: words))
                            .font(.headline)
                        ProgressView(
                            value: words.isEmpty ? 0 : Double(min(selectedWordIndex + 1, words.count)),
                            total: max(Double(words.count), 1)
                        )
                        .opacity(words.isEmpty ? 0.3 : 1.0)
                        Text("Word \(words.isEmpty ? 0 : min(selectedWordIndex + 1, words.count)) of \(words.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Word Navigator")
                        .font(.headline)
                    Text("Tap a word to jump back and replay its Morse output.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if words.isEmpty {
                                Text("Type text above to generate word tiles.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(words.indices, id: \.self) { idx in
                                    let word = words[idx]
                                    Button {
                                        setPlaybackStart(index: idx, words: words)
                                    } label: {
                                        Text(word)
                                            .font(.subheadline)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(
                                                Capsule()
                                                    .fill(selectedWordIndex == idx ? appThemeColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                MorsePlaybackSettingsCard(settings: $settings)
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editorFocused = false
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    editorFocused = false
                }
            }
        }
        .navigationTitle("Morse Output")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onDisappear {
            stopPlayback()
        }
    }

    private func parsedWords() -> [String] {
        textToPlay
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }
    }

    private func togglePlayback(words: [String]) {
        switch playbackStatus {
        case .playing:
            pausePlayback()
        case .paused:
            resumePlayback(words: words)
        case .stopped:
            startPlayback(from: PlaybackPosition(wordIndex: selectedWordIndex), words: words)
        }
    }

    private func pausePlayback() {
        playbackToken += 1
        playbackTask?.cancel()
        playbackTask = nil
        playbackStatus = .paused
        haptics.stop()
    }

    private func stopPlayback() {
        playbackToken += 1
        playbackTask?.cancel()
        playbackTask = nil
        playbackStatus = .stopped
        playbackPosition = PlaybackPosition(wordIndex: selectedWordIndex)
        haptics.stop()
    }

    private func resumePlayback(words: [String]) {
        startPlayback(from: playbackPosition, words: words)
    }

    private func startPlayback(from position: PlaybackPosition, words: [String]) {
        stopPlayback()
        guard !words.isEmpty else { return }
        let clampedWord = min(max(position.wordIndex, 0), words.count - 1)
        playbackPosition = PlaybackPosition(wordIndex: clampedWord, letterIndex: position.letterIndex, symbolIndex: position.symbolIndex)
        selectedWordIndex = clampedWord
        playbackStatus = .playing
        playbackToken += 1
        let token = playbackToken
        ActivityHistoryStore.shared.add(.morse, title: "Morse Output", detail: "Playing \(words.joined(separator: " "))")
        AssistAlertCenter.shared.alert(.morse, message: "Morse playback started")

        playbackTask = Task {
            await haptics.startEngineIfNeeded()
            for wordIndex in clampedWord..<words.count {
                if Task.isCancelled || token != playbackToken { break }
                let word = words[wordIndex]
                await MainActor.run {
                    selectedWordIndex = wordIndex
                    if playbackPosition.wordIndex != wordIndex {
                        playbackPosition = PlaybackPosition(wordIndex: wordIndex)
                    }
                }

                let startLetterIndex = (wordIndex == clampedWord) ? playbackPosition.letterIndex : 0
                let startSymbolIndex = (wordIndex == clampedWord) ? playbackPosition.symbolIndex : 0
                await playWord(word, startLetterIndex: startLetterIndex, startSymbolIndex: startSymbolIndex, token: token)

                if Task.isCancelled || token != playbackToken { break }
                if wordIndex < words.count - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(settings.wordGap * 1_000_000_000))
                }
            }
            await MainActor.run {
                playbackStatus = .stopped
            }
        }
    }

    private func moveToPreviousWord(in words: [String]) {
        guard !words.isEmpty else { return }
        let newIndex = max(selectedWordIndex - 1, 0)
        setPlaybackStart(index: newIndex, words: words)
    }

    private func moveToNextWord(in words: [String]) {
        guard !words.isEmpty else { return }
        let newIndex = min(selectedWordIndex + 1, words.count - 1)
        setPlaybackStart(index: newIndex, words: words)
    }

    private func setPlaybackStart(index: Int, words: [String]) {
        guard !words.isEmpty else { return }
        let clamped = min(max(index, 0), words.count - 1)
        selectedWordIndex = clamped
        playbackPosition = PlaybackPosition(wordIndex: clamped)
        if playbackStatus == .playing {
            startPlayback(from: playbackPosition, words: words)
        }
    }

    private func currentPlaybackLabel(words: [String]) -> String {
        guard !words.isEmpty, selectedWordIndex < words.count else { return "—" }
        switch playbackStatus {
        case .paused:
            return "Paused on \(words[selectedWordIndex])"
        case .playing, .stopped:
            return words[selectedWordIndex]
        }
    }

    private func playWord(_ word: String, startLetterIndex: Int, startSymbolIndex: Int, token: Int) async {
        let letters = word.uppercased().filter { $0.isLetter || $0.isNumber }
        let letterArray = Array(letters)
        guard !letterArray.isEmpty else { return }

        let safeStartLetter = min(max(startLetterIndex, 0), letterArray.count - 1)
        for letterIndex in safeStartLetter..<letterArray.count {
            if Task.isCancelled || token != playbackToken { return }
            let char = letterArray[letterIndex]
            if let code = MorseCodeMap.shared.code(for: char) {
                let symbols = Array(code)
                let safeStartSymbol = min(max(startSymbolIndex, 0), max(symbols.count - 1, 0))
                let symbolStart = (letterIndex == safeStartLetter) ? safeStartSymbol : 0
                for symbolIndex in symbolStart..<symbols.count {
                    if Task.isCancelled || token != playbackToken { return }
                    await MainActor.run {
                        playbackPosition = PlaybackPosition(wordIndex: selectedWordIndex, letterIndex: letterIndex, symbolIndex: symbolIndex)
                    }
                    let symbol = symbols[symbolIndex]
                    if symbol == "." {
                        await haptics.play(duration: settings.dotDuration, intensity: settings.intensity, sharpness: settings.sharpness)
                    } else if symbol == "-" {
                        await haptics.play(duration: settings.dashDuration, intensity: settings.intensity, sharpness: settings.sharpness)
                    }
                    if symbolIndex < symbols.count - 1 {
                        try? await Task.sleep(nanoseconds: UInt64(settings.elementGap * 1_000_000_000))
                    }
                }
            }
            if letterIndex < letterArray.count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(settings.letterGap * 1_000_000_000))
            }
        }
    }
}

private enum PlaybackStatus {
    case stopped
    case playing
    case paused
}

private struct PlaybackPosition: Equatable {
    var wordIndex: Int = 0
    var letterIndex: Int = 0
    var symbolIndex: Int = 0
}

private final class MorseCodeMap {
    static let shared = MorseCodeMap()

    private let map: [Character: String] = [
        "A": ".-",    "B": "-...",  "C": "-.-.",  "D": "-..",   "E": ".",
        "F": "..-.",  "G": "--.",   "H": "....",  "I": "..",    "J": ".---",
        "K": "-.-",   "L": ".-..",  "M": "--",    "N": "-.",    "O": "---",
        "P": ".--.",  "Q": "--.-",  "R": ".-.",   "S": "...",   "T": "-",
        "U": "..-",   "V": "...-",  "W": ".--",   "X": "-..-",  "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----."
    ]
    private lazy var reverseMap: [String: Character] = {
        var reverse: [String: Character] = [:]
        for (key, value) in map {
            reverse[value] = key
        }
        return reverse
    }()

    func code(for character: Character) -> String? {
        map[character]
    }

    func character(for code: String) -> Character? {
        reverseMap[code]
    }
}

private final class MorseHaptics: ObservableObject {
    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    init() {
        guard supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.stoppedHandler = { _ in
            // Engine stops when the app goes to the background; restart on next play.
        }
    }

    func startEngineIfNeeded() async {
        guard supportsHaptics else { return }
        if engine == nil {
            engine = try? CHHapticEngine()
        }
        if let engine {
            try? await engine.start()
        }
    }

    func stop() {
        guard supportsHaptics else { return }
        try? engine?.stop()
    }

    func play(duration: TimeInterval, intensity: Double, sharpness: Double) async {
        guard supportsHaptics, let engine else { return }
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity))
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensityParam, sharpnessParam],
            relativeTime: 0,
            duration: duration
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []) else { return }
        let player = try? engine.makePlayer(with: pattern)
        try? player?.start(atTime: 0)
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}

private struct MorsePlaybackSettings {
    var dotDuration: Double = 0.12
    var dashDuration: Double = 0.36
    var elementGap: Double = 0.12
    var letterGap: Double = 0.36
    var wordGap: Double = 0.84
    var intensity: Double = 1.0
    var sharpness: Double = 0.6
}

private struct MorsePlaybackSettingsCard: View {
    @Binding var settings: MorsePlaybackSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback Settings")
                .font(.headline)

            MorseSettingSlider(
                title: "Dot duration",
                value: $settings.dotDuration,
                range: 0.05...0.4,
                suffix: "s"
            )
            MorseSettingSlider(
                title: "Dash duration",
                value: $settings.dashDuration,
                range: 0.1...0.8,
                suffix: "s"
            )
            MorseSettingSlider(
                title: "Element gap",
                value: $settings.elementGap,
                range: 0.05...0.4,
                suffix: "s"
            )
            MorseSettingSlider(
                title: "Letter gap",
                value: $settings.letterGap,
                range: 0.1...0.8,
                suffix: "s"
            )
            MorseSettingSlider(
                title: "Word gap",
                value: $settings.wordGap,
                range: 0.3...1.6,
                suffix: "s"
            )
            MorseSettingSlider(
                title: "Haptic intensity",
                value: $settings.intensity,
                range: 0.2...1.0,
                suffix: ""
            )
            MorseSettingSlider(
                title: "Haptic sharpness",
                value: $settings.sharpness,
                range: 0.1...1.0,
                suffix: ""
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct MorseSettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(formattedValue())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }

    private func formattedValue() -> String {
        if suffix.isEmpty {
            return String(format: "%.2f", value)
        }
        return String(format: "%.2f%@", value, suffix)
    }
}

extension View {
    fileprivate func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Morse Letters (A–Z with slider + scroll)
struct MorseLettersPage: View {
    @State private var selectedIndex: Int = 0
    @State private var isDraggingSlider: Bool = false
    @State private var pendingScroll: DispatchWorkItem?
    private let letters: [String] = (0..<26).compactMap { i in
        guard let scalar = UnicodeScalar(65 + i) else { return nil }
        return String(Character(scalar))
    }
    private let scrollDebounce: TimeInterval = 0.04

    private func scheduleScroll(to index: Int, proxy: ScrollViewProxy, animated: Bool) {
        pendingScroll?.cancel()
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(index, anchor: .top)
                }
            } else {
                proxy.scrollTo(index, anchor: .top)
            }
        }
        pendingScroll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDebounce, execute: work)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                HStack {
                    Text("Letter: \(letters[selectedIndex])")
                        .font(.headline)
                    Spacer()
                }

                Slider(
                    value: Binding(
                        get: { Double(selectedIndex) },
                        set: { newVal in
                            let idx = Int(newVal.rounded())
                            if idx != selectedIndex {
                                selectedIndex = idx
                                scheduleScroll(to: idx, proxy: proxy, animated: !isDraggingSlider)
                            }
                        }
                    ),
                    in: 0...25,
                    step: 1,
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            scheduleScroll(to: selectedIndex, proxy: proxy, animated: true)
                        }
                    }
                )
                .accessibilityLabel("Select letter")

                Divider().padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(0..<letters.count, id: \.self) { i in
                            MorseLetterCard(letter: letters[i], index: i)
                                .id(i)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: MorseLetterOffsetKey.self,
                                            value: [i: geo.frame(in: .named("morseLettersScroll")).minY]
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        if isDraggingSlider {
                            isDraggingSlider = false
                        }
                        pendingScroll?.cancel()
                    }
                )
                .coordinateSpace(name: "morseLettersScroll")
                .onPreferenceChange(MorseLetterOffsetKey.self) { offsets in
                    guard !offsets.isEmpty else { return }
                    if isDraggingSlider { return }
                    let targetTop: CGFloat = 20
                    let closest = offsets.min(by: { abs($0.value - targetTop) < abs($1.value - targetTop) })
                    if let idx = closest?.key, idx != selectedIndex {
                        selectedIndex = idx
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Morse Letters")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

private struct MorseLetterOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct MorseLetterCard: View {
    let letter: String
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(letter)
                .font(.headline)
            ZStack {
                Image("Morse_\(letter)")
                    .resizable()
                    .aspectRatio(CGSize(width: 283, height: 25), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel("Morse for letter \(letter)")
                    .overlay(
                        Group {
                            if UIImage(named: "Morse_\(letter)") == nil {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.08))
                                    VStack(spacing: 6) {
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                            .font(.system(size: 28))
                                            .foregroundStyle(.secondary)
                                        Text("Add image named \"Morse_\(letter)\"")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

// MARK: - Morse Numbers (0–9 with slider + scroll)
struct MorseNumbersPage: View {
    @State private var selectedIndex: Int = 0
    @State private var isDraggingSlider: Bool = false
    @State private var pendingScroll: DispatchWorkItem?
    private let numbers: [Int] = Array(0...9)
    private let scrollDebounce: TimeInterval = 0.04

    private func scheduleScroll(to index: Int, proxy: ScrollViewProxy, animated: Bool) {
        pendingScroll?.cancel()
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(index, anchor: .top)
                }
            } else {
                proxy.scrollTo(index, anchor: .top)
            }
        }
        pendingScroll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDebounce, execute: work)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                HStack {
                    Text("Number: \(numbers[selectedIndex])")
                        .font(.headline)
                    Spacer()
                }

                Slider(
                    value: Binding(
                        get: { Double(selectedIndex) },
                        set: { newVal in
                            let idx = Int(newVal.rounded())
                            if idx != selectedIndex {
                                selectedIndex = idx
                                scheduleScroll(to: idx, proxy: proxy, animated: !isDraggingSlider)
                            }
                        }
                    ),
                    in: 0...Double(numbers.count - 1),
                    step: 1,
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            scheduleScroll(to: selectedIndex, proxy: proxy, animated: true)
                        }
                    }
                )
                .accessibilityLabel("Select number")

                Divider().padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(0..<numbers.count, id: \.self) { i in
                            MorseNumberCard(number: numbers[i], index: i)
                                .id(i)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: MorseNumberOffsetKey.self,
                                            value: [i: geo.frame(in: .named("morseNumbersScroll")).minY]
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        if isDraggingSlider {
                            isDraggingSlider = false
                        }
                        pendingScroll?.cancel()
                    }
                )
                .coordinateSpace(name: "morseNumbersScroll")
                .onPreferenceChange(MorseNumberOffsetKey.self) { offsets in
                    guard !offsets.isEmpty else { return }
                    if isDraggingSlider { return }
                    let targetTop: CGFloat = 20
                    let closest = offsets.min(by: { abs($0.value - targetTop) < abs($1.value - targetTop) })
                    if let idx = closest?.key, idx != selectedIndex {
                        selectedIndex = idx
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Morse Numbers")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

private struct MorseNumberOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct MorseNumberCard: View {
    let number: Int
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number)")
                .font(.headline)
            ZStack {
                Image("Morse_\(number)")
                    .resizable()
                    .aspectRatio(CGSize(width: 283, height: 25), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel("Morse for number \(number)")
                    .overlay(
                        Group {
                            if UIImage(named: "Morse_\(number)") == nil {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.08))
                                    VStack(spacing: 6) {
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                            .font(.system(size: 28))
                                            .foregroundStyle(.secondary)
                                        Text("Add image named \"Morse_\(number)\"")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}


final class AudioMeter: ObservableObject {
    private let engine = AVAudioEngine()
    @Published var level: CGFloat = 0 // 0...1

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
        } catch {
            // Unable to start engine
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?.pointee else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameLength {
            let x = channelData[i]
            sum += x * x
        }
        let rms = sqrt(sum / Float(frameLength))
        var db: Float = -80
        if rms > 0 { db = 20 * log10(rms) }
        let minDb: Float = -80
        let clamped = max(minDb, db)
        let normalized = (clamped - minDb) / -minDb // 0..1

        DispatchQueue.main.async {
            self.level = CGFloat(normalized)
        }
    }
}

struct BrowserPage: View {
    @State private var urlText: String = ""
    @FocusState private var urlFieldFocused: Bool
    @State private var textSize: Double = 16
    @State private var lineSpacing: Double = 1.4
    @State private var highContrast: Bool = false
    @State private var highlightLinks: Bool = true
    @State private var simplifyPage: Bool = true
    @State private var simplifyIntensity: Double = 0.6
    @State private var focusMode: Bool = false
    @State private var autoScroll: Bool = false
    @State private var autoScrollSpeed: Double = 1.2
    @State private var readerEnabled: Bool = true
    @State private var speechRate: Double = 0.48
    @State private var webViewHeight: Double = 520
    @State private var savedSites: [String] = [
        "https://nfb.org/",
        "https://www.acb.org/home",
        "https://www.nad.org/",
        "https://webaim.org/"
    ]
    @StateObject private var readerModel = WebReaderModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("URL")
                        .font(.headline)
                    HStack(spacing: 8) {
                        TextField("Enter a website URL", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($urlFieldFocused)
                            .onSubmit {
                                loadFromURLText()
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        Button("Paste") {
                            if let clipboard = UIPasteboard.general.string {
                                urlText = clipboard
                                loadFromURLText()
                            }
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))
                    }
                    HStack(spacing: 10) {
                        Button {
                            loadFromURLText()
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Go")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: true))

                        Button {
                            readerModel.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))
                        .disabled(!readerModel.canGoBack)

                        Button {
                            readerModel.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))
                        .disabled(!readerModel.canGoForward)

                        Button {
                            readerModel.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))

                        Button {
                            readerModel.stop()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))
                        .disabled(!readerModel.isLoading)

                        Spacer()

                        Button {
                            saveCurrentURL()
                        } label: {
                            Image(systemName: "bookmark")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: true))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )

                WebReaderView(
                    model: readerModel,
                    urlText: $urlText,
                    readerEnabled: $readerEnabled,
                    textSize: $textSize,
                    lineSpacing: $lineSpacing,
                    highContrast: $highContrast,
                    highlightLinks: $highlightLinks,
                    simplifyPage: $simplifyPage,
                    simplifyIntensity: $simplifyIntensity,
                    focusMode: $focusMode,
                    autoScroll: $autoScroll,
                    autoScrollSpeed: $autoScrollSpeed
                )
                .frame(height: webViewHeight)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved Sites")
                        .font(.headline)
                    if savedSites.isEmpty {
                        Text("No saved sites yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(savedSites, id: \.self) { site in
                            HStack(spacing: 10) {
                                Button {
                                    urlText = site
                                    loadFromURLText()
                                } label: {
                                    HStack {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(.tint)
                                        Text(site)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    removeSavedSite(site)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(PressableButtonStyle(prominent: false))
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(.secondary.opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable reader controls", isOn: $readerEnabled)
                        .font(.headline)
                    if readerEnabled {
                        MorseSettingSlider(title: "Text size", value: $textSize, range: 12...28, suffix: "pt")
                        MorseSettingSlider(title: "Line spacing", value: $lineSpacing, range: 1.0...2.2, suffix: "")
                        Toggle("High contrast", isOn: $highContrast)
                        Toggle("Highlight links", isOn: $highlightLinks)
                        Toggle("Simplify page", isOn: $simplifyPage)
                        if simplifyPage {
                            MorseSettingSlider(title: "Simplify intensity", value: $simplifyIntensity, range: 0...1, suffix: "")
                        }
                        Toggle("Auto-scroll", isOn: $autoScroll)
                        if autoScroll {
                            MorseSettingSlider(title: "Auto-scroll speed", value: $autoScrollSpeed, range: 0.5...3.0, suffix: "x")
                        }
                        MorseSettingSlider(title: "Web view height", value: $webViewHeight, range: 360...900, suffix: "pt")
                    } else {
                        Text("Reader controls are off. Pages render normally.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Read Aloud (TTS)")
                        .font(.headline)
                    Text(readerModel.currentSpokenLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button {
                            readerModel.skipWord(-1, rate: Float(speechRate))
                        } label: {
                            Image(systemName: "backward.fill")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))

                        Button {
                            readerModel.startSpeaking(rate: Float(speechRate))
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: true))

                        Button {
                            readerModel.pauseSpeaking()
                        } label: {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))

                        Button {
                            readerModel.resumeSpeaking()
                        } label: {
                            Image(systemName: "gobackward")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))

                        Button {
                            readerModel.stopSpeaking()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))

                        Button {
                            readerModel.skipWord(1, rate: Float(speechRate))
                        } label: {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(PressableButtonStyle(prominent: false))
                    }
                    MorseSettingSlider(title: "Speech rate", value: $speechRate, range: 0.3...0.7, suffix: "")
                    Text("Bonus: Read selection (long-press text)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Accessibility Features")
                        .font(.headline)
                    Toggle("Focus mode (one paragraph at a time)", isOn: $focusMode)
                    Toggle("Tap to define / tap to spell", isOn: .constant(false))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .padding()
        }
        .navigationTitle("Web Reader")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture {
            urlFieldFocused = false
        }
        .onChange(of: speechRate) { newValue in
            if readerModel.isSpeaking {
                readerModel.restartSpeaking(rate: Float(newValue))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    urlFieldFocused = false
                }
            }
        }
    }

    private func saveCurrentURL() {
        guard let normalized = normalizedURL(from: urlText) else { return }
        if !savedSites.contains(normalized) {
            savedSites.append(normalized)
        }
        urlText = normalized
        readerModel.load(urlString: normalized)
    }

    private func removeSavedSite(_ site: String) {
        savedSites.removeAll { $0 == site }
    }

    private func loadFromURLText() {
        guard let normalized = normalizedURL(from: urlText) else { return }
        urlText = normalized
        readerModel.load(urlString: normalized)
    }

    private func normalizedURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
    }
}

private final class WebReaderModel: NSObject, ObservableObject, WKNavigationDelegate, AVSpeechSynthesizerDelegate {
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var currentSpokenLabel: String = "Not reading"
    @Published var isSpeaking: Bool = false

    private(set) var webView: WKWebView?
    private let synthesizer = AVSpeechSynthesizer()
    private var autoScrollTimer: Timer?
    private var lastSettings = WebReaderSettings()
    private var cachedText: String = ""
    private var cachedWords: [String] = []
    private var currentWordIndex: Int = 0
    private var utteranceStartIndex: Int = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
    }

    func load(urlString: String) {
        guard let url = URL(string: urlString.hasPrefix("http") ? urlString : "https://\(urlString)") else { return }
        webView?.load(URLRequest(url: url))
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func stop() {
        webView?.stopLoading()
    }

    func applyReaderSettings(
        enabled: Bool,
        textSize: Double,
        lineSpacing: Double,
        highContrast: Bool,
        highlightLinks: Bool,
        simplifyPage: Bool,
        simplifyIntensity: Double,
        focusMode: Bool
    ) {
        lastSettings = WebReaderSettings(
            enabled: enabled,
            textSize: textSize,
            lineSpacing: lineSpacing,
            highContrast: highContrast,
            highlightLinks: highlightLinks,
            simplifyPage: simplifyPage,
            simplifyIntensity: simplifyIntensity,
            focusMode: focusMode
        )
        let js = """
        (function() {
            const id = 'echosight-reader-style';
            let style = document.getElementById(id);
            if (!\(enabled)) {
                if (style) style.remove();
                document.body.classList.remove('echosight-reader');
                document.documentElement.classList.remove('echosight-invert');
                return;
            }
            if (!style) {
                style = document.createElement('style');
                style.id = id;
                document.head.appendChild(style);
            }
            const linkSize = \(highlightLinks) ? 1.08 : 1.0;
            const linkUnderline = \(highlightLinks) ? 'underline' : 'none';
            const contrast = '#111';
            const bg = '#f9f9f9';
            style.textContent = `
                html, body {
                    background: ${bg} !important;
                }
                body.echosight-reader {
                    font-size: \(textSize)px !important;
                    line-height: \(lineSpacing) !important;
                    color: ${contrast} !important;
                }
                body.echosight-reader a {
                    text-decoration: ${linkUnderline} !important;
                    font-size: ${linkSize}em !important;
                    padding: 2px 2px !important;
                }
                html.echosight-invert {
                    filter: invert(1) hue-rotate(180deg) !important;
                    background: #000 !important;
                }
            `;
            document.body.classList.add('echosight-reader');
            if (\(highContrast)) {
                document.documentElement.classList.add('echosight-invert');
            } else {
                document.documentElement.classList.remove('echosight-invert');
            }
            if (\(simplifyPage)) {
                const intensity = \(simplifyIntensity);
                const hideSelectors = [
                    'nav','header','footer','aside','[role="navigation"]','[role="banner"]',
                    '[role="contentinfo"]','.sidebar','.nav','.menu','.ads','.ad','.promo'
                ];
                if (intensity > 0.5) {
                    hideSelectors.push('.share','.social','.related','.newsletter','.subscribe','.comments');
                }
                if (intensity > 0.8) {
                    hideSelectors.push('img','video','iframe','picture');
                }
                hideSelectors.forEach(sel => {
                    document.querySelectorAll(sel).forEach(el => el.style.display = 'none');
                });
                if (intensity >= 0.95) {
                    const existing = document.getElementById('echosight-text-only');
                    const main = document.querySelector('main, article, [role="main"]') || document.body;
                    const text = main.innerText || '';
                    if (!existing) {
                        document.body.innerHTML = '';
                        const wrap = document.createElement('div');
                        wrap.id = 'echosight-text-only';
                        wrap.style.maxWidth = '48rem';
                        wrap.style.margin = '0 auto';
                        wrap.style.padding = '24px';
                        const disclaimer = document.createElement('div');
                        disclaimer.textContent = 'Disclaimer: only text (max simplification).';
                        disclaimer.style.fontWeight = '600';
                        disclaimer.style.marginBottom = '12px';
                        const content = document.createElement('div');
                        content.style.whiteSpace = 'pre-wrap';
                        content.textContent = text;
                        wrap.appendChild(disclaimer);
                        wrap.appendChild(content);
                        document.body.appendChild(wrap);
                    } else {
                        existing.querySelector('div:nth-child(2)').textContent = text;
                    }
                }
            }
            if (\(focusMode)) {
                const main = document.querySelector('main, article, [role="main"]') || document.body;
                main.style.maxWidth = '48rem';
                main.style.margin = '0 auto';
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func setAutoScroll(enabled: Bool, speed: Double) {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        guard enabled else { return }
        let clamped = max(0.2, min(speed, 6.0))
        let interval = 0.08
        let step = clamped * 2
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.webView?.evaluateJavaScript("window.scrollBy(0, \(step));", completionHandler: nil)
        }
    }

    func startSpeaking(rate: Float) {
        extractReadableText { [weak self] text in
            guard let self, let text, !text.isEmpty else { return }
            self.cacheText(text)
            self.speakFrom(index: self.currentWordIndex, rate: rate)
            DispatchQueue.main.async {
                self.isSpeaking = true
            }
        }
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
        isSpeaking = false
    }

    func resumeSpeaking() {
        synthesizer.continueSpeaking()
        isSpeaking = true
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        currentSpokenLabel = "Stopped"
        isSpeaking = false
    }

    func restartSpeaking(rate: Float) {
        guard isSpeaking else { return }
        speakFrom(index: currentWordIndex, rate: rate)
    }

    func skipWord(_ delta: Int, rate: Float) {
        ensureCachedText { [weak self] in
            guard let self else { return }
            guard !self.cachedWords.isEmpty else { return }
            let newIndex = min(max(self.currentWordIndex + delta, 0), self.cachedWords.count - 1)
            self.currentWordIndex = newIndex
            self.speakFrom(index: newIndex, rate: rate)
        }
    }

    private func extractReadableText(completion: @escaping (String?) -> Void) {
        let js = """
        (function() {
            const main = document.querySelector('main, article, [role="main"]');
            return (main ? main.innerText : document.body.innerText);
        })();
        """
        webView?.evaluateJavaScript(js) { result, _ in
            completion(result as? String)
        }
    }

    private func ensureCachedText(_ completion: @escaping () -> Void) {
        if !cachedText.isEmpty {
            completion()
            return
        }
        extractReadableText { [weak self] text in
            guard let self, let text, !text.isEmpty else { return }
            self.cacheText(text)
            completion()
        }
    }

    private func cacheText(_ text: String) {
        cachedText = text
        cachedWords = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0) }
        if cachedWords.isEmpty {
            currentWordIndex = 0
        } else {
            currentWordIndex = min(currentWordIndex, cachedWords.count - 1)
        }
        updateCurrentSpokenLabel()
    }

    private func speakFrom(index: Int, rate: Float) {
        guard !cachedWords.isEmpty else { return }
        let clamped = min(max(index, 0), cachedWords.count - 1)
        currentWordIndex = clamped
        utteranceStartIndex = clamped
        let remainder = cachedWords[clamped...].joined(separator: " ")
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: remainder)
        utterance.rate = rate
        synthesizer.speak(utterance)
        updateCurrentSpokenLabel()
    }

    private func updateCurrentSpokenLabel() {
        guard !cachedWords.isEmpty, currentWordIndex < cachedWords.count else {
            currentSpokenLabel = "Not reading"
            return
        }
        currentSpokenLabel = "Reading: \(cachedWords[currentWordIndex]) (\(currentWordIndex + 1)/\(cachedWords.count))"
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let text = utterance.speechString as NSString
        let prefix = text.substring(to: characterRange.location)
        let wordsBefore = prefix.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let current = utteranceStartIndex + wordsBefore
        if current >= 0, current < cachedWords.count {
            currentWordIndex = current
            updateCurrentSpokenLabel()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        cachedText = ""
        cachedWords = []
        currentWordIndex = 0
        currentSpokenLabel = "Not reading"
        applyReaderSettings(
            enabled: lastSettings.enabled,
            textSize: lastSettings.textSize,
            lineSpacing: lastSettings.lineSpacing,
            highContrast: lastSettings.highContrast,
            highlightLinks: lastSettings.highlightLinks,
            simplifyPage: lastSettings.simplifyPage,
            simplifyIntensity: lastSettings.simplifyIntensity,
            focusMode: lastSettings.focusMode
        )
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }
}

private struct WebReaderSettings {
    var enabled: Bool = true
    var textSize: Double = 16
    var lineSpacing: Double = 1.4
    var highContrast: Bool = false
    var highlightLinks: Bool = true
    var simplifyPage: Bool = true
    var simplifyIntensity: Double = 0.6
    var focusMode: Bool = false
}

private struct WebReaderView: UIViewRepresentable {
    @ObservedObject var model: WebReaderModel
    @Binding var urlText: String
    @Binding var readerEnabled: Bool
    @Binding var textSize: Double
    @Binding var lineSpacing: Double
    @Binding var highContrast: Bool
    @Binding var highlightLinks: Bool
    @Binding var simplifyPage: Bool
    @Binding var simplifyIntensity: Double
    @Binding var focusMode: Bool
    @Binding var autoScroll: Bool
    @Binding var autoScrollSpeed: Double

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground
        model.attach(webView: webView)
        if !urlText.isEmpty {
            model.load(urlString: urlText)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        model.applyReaderSettings(
            enabled: readerEnabled,
            textSize: textSize,
            lineSpacing: lineSpacing,
            highContrast: highContrast,
            highlightLinks: highlightLinks,
            simplifyPage: simplifyPage,
            simplifyIntensity: simplifyIntensity,
            focusMode: focusMode
        )
        model.setAutoScroll(enabled: autoScroll, speed: autoScrollSpeed)
    }
}

struct SettingsAccessibilityPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.stand.line.dotted.figure.stand")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Settings & Accessibility coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

struct AccessibilityPage: View {
    @AppStorage("accessibility.simplifiedUI") private var simplifiedUI: Bool = false
    @AppStorage("accessibility.simplifiedUI.includeRed") private var simplifyRedTiles: Bool = false

    var body: some View {
        Form {
            Section("Simplified UI") {
                Toggle("Simplified UI", isOn: $simplifiedUI)
                Toggle("Apply to red tiles", isOn: $simplifyRedTiles)
                    .disabled(!simplifiedUI)
                Text("Simplified UI removes icons and subtitles on Home tiles and enlarges titles. Red tiles will use red backgrounds; others use blue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Devices") {
                NavigationLink("Connect EchoSense Device") {
                    EchoSenseDevicePage()
                }
                Text("Bluetooth pairing and configuration are coming soon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EchoSenseDevicePage: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("EchoSense Device")
                .font(.title2.bold())
            Text("Bluetooth pairing and device configuration are coming soon.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("EchoSense")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

struct SettingsPage: View {
    @AppStorage("feature.camera.enabled") private var cameraEnabled: Bool = true
    @AppStorage("feature.morse.enabled") private var morseEnabled: Bool = true
    @AppStorage("feature.browser.enabled") private var browserEnabled: Bool = true
    @AppStorage("feature.asl.enabled") private var aslEnabled: Bool = true
    @AppStorage("feature.mic.enabled") private var micEnabled: Bool = true
    @AppStorage("startup.open.enabled") private var openOnStartup: Bool = false
    @AppStorage("startup.open.tile") private var startupTile: String = StartupTile.none.rawValue
    @AppStorage("theme.color") private var themeColorName: String = ThemeColor.blue.rawValue
    @AppStorage(SpeechSettings.voiceIdentifierKey) private var speechVoiceIdentifier: String = SpeechSettings.autoVoiceIdentifier
    @AppStorage(SpeechSettings.rateKey) private var speechRate: Double = 0.5

    var body: some View {
        Form {
            Section("Visual Features") {
                Toggle("Camera", isOn: $cameraEnabled)
                Toggle("Morse Communicator", isOn: $morseEnabled)
                Toggle("Browser", isOn: $browserEnabled)
            }
            Section("Auditory Features") {
                Toggle("ASL Alphabet", isOn: $aslEnabled)
                Toggle("Mic", isOn: $micEnabled)
            }
            Section("Appearance") {
                Picker("Theme color", selection: $themeColorName) {
                    ForEach(ThemeColor.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            }
            Section("Speech") {
                Picker("Voice", selection: $speechVoiceIdentifier) {
                    Text("Auto (best match)").tag(SpeechSettings.autoVoiceIdentifier)
                    ForEach(availableVoices(), id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.identifier)
                    }
                }
                MorseSettingSlider(title: "Speech rate", value: $speechRate, range: 0.3...0.7, suffix: "")
                Button("Test Voice") {
                    SpeechAnnouncer.shared.testVoice()
                }
                Text("Tip: Download enhanced voices in Settings → Accessibility → Spoken Content → Voices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy & Device Alerts") {
                Label("Offline-first camera, OCR, mic analysis, ASL, and Morse tools", systemImage: "lock.shield.fill")
                Label("iPhone haptics are active for Morse, practice, obstacle, and sound alerts", systemImage: "iphone.radiowaves.left.and.right")
                Label("Apple Watch relay is ready when a companion watch app is installed", systemImage: "applewatch")
                Text("EchoSight does not upload camera frames for its critical assist tools.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open tile on start-up", isOn: $openOnStartup)
                if openOnStartup {
                    Picker("Tile", selection: $startupTile) {
                        ForEach(StartupTile.allCases) { tile in
                            Text(tile.title).tag(tile.rawValue)
                        }
                    }
                }
                Text("Select a feature tile to open automatically when EchoSight starts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func availableVoices() -> [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let locale = Locale.current.identifier
        let language = Locale.current.languageCode ?? "en"
        let preferred = voices.filter { $0.language == locale }
        let fallback = voices.filter { $0.language.hasPrefix(language) }
        let list = preferred.isEmpty ? fallback : preferred
        return list.sorted { $0.name < $1.name }
    }
}

struct AboutPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("EchoSight\nCreated by the EchoSight team.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("version 5.0.22")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

struct TutorialHubPage: View {
    @EnvironmentObject var flow: AppFlow

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Overview tile (launches the original onboarding tutorial)
                ActionTile(title: "Overview", subtitle: "Quick start tutorial", systemImage: "book.closed.fill") {
                    UserDefaults.standard.set(false, forKey: "hasSeenTutorial")
                    flow.phase = .tutorial
                }

                // Extra spacing to isolate the overview tile
                Spacer(minLength: 8)

                // Feature-specific tutorials
                TileLink(title: "Camera", subtitle: "Using camera recognition", systemImage: "camera.viewfinder", destination: AnyView(CameraTutorialPage()))
                TileLink(title: "Mic", subtitle: "Voice and listening tips", systemImage: "mic.fill", destination: AnyView(MicTutorialPage()))
                TileLink(title: "Browser", subtitle: "Browsing with EchoSight", systemImage: "safari.fill", destination: AnyView(BrowserTutorialPage()))
                TileLink(title: "ASL Alphabet", subtitle: "Learn and practice", systemImage: "hand.raised.fill", destination: AnyView(ASLTutorialPage()))
                TileLink(title: "Morse Communicator", subtitle: "Send and receive signals", systemImage: "antenna.radiowaves.left.and.right", destination: AnyView(MorseTutorialPage()))
            }
            .padding()
        }
        .navigationTitle("Tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Replace the entire ASLTutorialPage with the new implementation
struct ASLTutorialPage: View {
    private let tips: [(title: String, text: String)] = [
        (
            title: "Topic-Comment Structure",
            text: "In ASL, sentences often follow topic first, then comment. For example, \"Your name what?\" instead of \"What is your name?\" This helps sentences feel natural in sign language."
        ),
        (
            title: "Deaf Etiquette Basics",
            text: "Simple etiquette like getting attention (touch shoulder or wave gently), and always face the signer directly."
        ),
        (
            title: "Facial Expressions Matter",
            text: "Facial movements (eyebrows, mouth) are part of the grammar, not extra gesture. Raised eyebrows often signal a question."
        ),
        (
            title: "Finger Spelling Tips",
            text: "For repeated letters, add a little bounce or slide so it’s easier to read."
        ),
        (
            title: "Handshape & Location",
            text: "ASL signs depend on handshape, palm orientation, and location in signing space — not just motion."
        ),
        (
            title: "Numbers Help",
            text: "Knowing how to sign 1–10 often comes up in everyday ASL."
        ),
        (
            title: "Eye Contact Is Important",
            text: "Maintaining eye contact shows attention and respect and helps communication flow naturally in ASL."
        ),
        (
            title: "Sign in a Neutral Space",
            text: "Most signs happen between the chest and face area; signing too high or too low can reduce clarity."
        ),
        (
            title: "One Concept at a Time",
            text: "ASL often uses fewer signs than English, focusing on key ideas rather than every word."
        ),
        (
            title: "Clarification Is Normal",
            text: "It’s okay to ask someone to repeat or slow down; this is common and expected in ASL conversations."
        ),
        (
            title: "Names Are Fingerspelled",
            text: "People’s names are usually spelled using the ASL alphabet unless they have a name sign."
        ),
        (
            title: "Use Pointing Appropriately",
            text: "Pointing is commonly used in ASL to refer to people or objects and is not considered rude."
        ),
        (
            title: "Speed Comes with Practice",
            text: "Clear, steady signing is better than fast signing when learning ASL."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<tips.count, id: \.self) { i in
                    InfoTile(title: tips[i].title, text: tips[i].text)
                }
            }
            .padding()
        }
        .navigationTitle("ASL Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CameraTutorialPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Camera Overview").font(.title.bold())
                Text("• Point the camera at an object or text.\n• Ensure good lighting for best results.\n• Keep your hands steady; use a stand if needed.\n• Try different distances to improve recognition accuracy.")
                Text("Tips").font(.headline)
                Text("• Avoid glare or reflections.\n• Tap to focus if the subject appears blurry.\n• Use the rear camera for better quality.")
            }
            .padding()
        }
        .navigationTitle("Camera Tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MicTutorialPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mic Overview").font(.title.bold())
                Text("• Speak clearly and at a moderate pace.\n• Reduce background noise when possible.\n• Use headphones with a mic for clearer input.")
                Text("Tips").font(.headline)
                Text("• Pause briefly between sentences.\n• If the app isn't responding, check microphone permissions in Settings.")
            }
            .padding()
        }
        .navigationTitle("Mic Tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BrowserTutorialPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Browser Overview").font(.title.bold())
                Text("• Use the integrated browser to access content within EchoSight.\n• Navigate with the standard back/forward buttons.\n• Use reader mode if available for simplified pages.")
                Text("Tips").font(.headline)
                Text("• Favor accessible websites with semantic markup.\n• Increase text size using system accessibility settings for better readability.")
            }
            .padding()
        }
        .navigationTitle("Browser Tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MorseTutorialPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MorseHeroCard()

                MorseSectionCard(title: "Spacing Is Important", systemImage: "pause.circle.fill") {
                    Text("Morse code does not use a spacebar. Instead, pauses separate signals.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MorseBulletList(items: [
                        "A short pause separates dots and dashes within the same letter",
                        "A medium pause separates letters",
                        "A long pause separates words"
                    ])
                    Text("The app automatically handles these pauses for you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MorseSectionCard(title: "Example", systemImage: "text.quote") {
                    Text("The word “ADD” in Morse code looks like this:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MorseExampleBlock(lines: [
                        "A = · –",
                        "D = – · ·",
                        "",
                        "So “ADD” is sent as:",
                        "· – | – · · | – · ·"
                    ])
                    Text("The longer pauses show where one letter ends and the next begins.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MorseSectionCard(title: "Using Morse in This App", systemImage: "hand.tap.fill") {
                    MorseBulletList(items: [
                        "Short tap on the screen = dot",
                        "Long press on the screen = dash",
                        "Pause briefly to finish a letter",
                        "Pause longer to finish a word",
                        "Your taps will automatically be translated into text"
                    ])
                }

                MorseSectionCard(title: "Morse Output", systemImage: "waveform.path.ecg") {
                    Text("You can also type text and have it played back as Morse code using vibrations:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MorseBulletList(items: [
                        "Short vibration = dot",
                        "Long vibration = dash"
                    ])
                    Text("This allows communication without sound or speech.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MorseSectionCard(title: "Who Morse Code Helps", systemImage: "person.2.fill") {
                    MorseBulletList(items: [
                        "Are deafblind",
                        "Have limited speech or motor control",
                        "Need a silent or tactile way to communicate"
                    ])
                }

                MorseSectionCard(title: "Reference Chart", systemImage: "doc.richtext") {
                    Text("Below is a chart showing the Morse code for letters A–Z and numbers 0–9.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MorseChartCard(title: "Morse Letters and Numbers", assetName: "Morse_Chart")
                }
            }
            .padding()
        }
        .navigationTitle("Morse Tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MorseHeroCard: View {
    @Environment(\.appThemeColor) private var appThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(appThemeColor))
                VStack(alignment: .leading, spacing: 4) {
                    Text("How Morse Code Works")
                        .font(.title2.bold())
                    Text("Communicate using short and long signals called dots and dashes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                MorseSignalCard(symbol: "·", label: "Dot", detail: "Short tap or vibration")
                MorseSignalCard(symbol: "–", label: "Dash", detail: "Longer tap or vibration")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [appThemeColor.opacity(0.12), appThemeColor.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(appThemeColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

private struct MorseSignalCard: View {
    let symbol: String
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(symbol)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
            Text(label)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct MorseSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct MorseBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.body.weight(.semibold))
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MorseExampleBlock: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                if line.isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    Text(line)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

private struct MorseChartCard: View {
    let title: String
    let assetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ZStack {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel("\(title) Morse chart")
                    .overlay(
                        Group {
                            if UIImage(named: assetName) == nil {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.08))
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.richtext")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.secondary)
                                        Text("Add image named \"\(assetName)\"")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Updated ASLAlphabetPage with added "ASL Numbers" tile
struct ASLAlphabetPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TileLink(title: "ASL Tips", subtitle: "Get helpful guidance", systemImage: "lightbulb.fill", destination: AnyView(ASLTutorialPage()))
                TileLink(title: "ASL Alphabet", subtitle: "Browse letters A–Z", systemImage: "hand.raised.fill", destination: AnyView(ASLAlphabetLearnView()))
                TileLink(title: "ASL Numbers", subtitle: "Numbers 1–20", systemImage: "123.rectangle", destination: AnyView(ASLNumbersLearnView()))
                TileLink(title: "ASL Phrases", subtitle: "Practice common phrases", systemImage: "text.bubble", destination: AnyView(ASLPhrasesPage()))
                TileLink(title: "Daily Practice", subtitle: "Streaks, quizzes, and progress", systemImage: "target", destination: AnyView(PracticeHubPage()))
            }
            .padding()
        }
        .navigationTitle("ASL")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ASL Alphabet Learn (A–Z with slider + scroll)
struct ASLAlphabetLearnView: View {
    @State private var selectedIndex: Int = 0
    @State private var isDraggingSlider: Bool = false
    @State private var pendingScroll: DispatchWorkItem?
    private let letters: [String] = (0..<26).compactMap { i in
        guard let scalar = UnicodeScalar(65 + i) else { return nil }
        return String(Character(scalar))
    }
    private let scrollDebounce: TimeInterval = 0.04

    private func scheduleScroll(to index: Int, proxy: ScrollViewProxy, animated: Bool) {
        pendingScroll?.cancel()
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(index, anchor: .top)
                }
            } else {
                proxy.scrollTo(index, anchor: .top)
            }
        }
        pendingScroll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDebounce, execute: work)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                HStack {
                    Text("Letter: \(letters[selectedIndex])")
                        .font(.headline)
                    Spacer()
                }

                // Slider to quickly jump between letters A..Z
                Slider(
                    value: Binding(
                        get: { Double(selectedIndex) },
                        set: { newVal in
                            let idx = Int(newVal.rounded())
                            if idx != selectedIndex {
                                selectedIndex = idx
                                scheduleScroll(to: idx, proxy: proxy, animated: !isDraggingSlider)
                            }
                        }
                    ),
                    in: 0...25,
                    step: 1,
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            scheduleScroll(to: selectedIndex, proxy: proxy, animated: true)
                        }
                    }
                )
                .accessibilityLabel("Select letter")

                Divider().padding(.bottom, 4)

                // Scrollable list of letters with images
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(0..<letters.count, id: \.self) { i in
                            ASLLetterCard(letter: letters[i], index: i)
                                .id(i)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: LetterOffsetKey.self,
                                            value: [i: geo.frame(in: .named("scroll")).minY]
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        if isDraggingSlider {
                            isDraggingSlider = false
                        }
                        pendingScroll?.cancel()
                    }
                )
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(LetterOffsetKey.self) { offsets in
                    guard !offsets.isEmpty else { return }
                    if isDraggingSlider { return }
                    // Pick the item whose top is closest to a small inset from the top (e.g., 20 pts)
                    let targetTop: CGFloat = 20
                    let closest = offsets.min(by: { abs($0.value - targetTop) < abs($1.value - targetTop) })
                    if let idx = closest?.key, idx != selectedIndex {
                        selectedIndex = idx
                    }
                }
            }
        }
        .navigationTitle("ASL Alphabet")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

// Tracks each letter card's vertical position in the ScrollView
private struct LetterOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Single letter card showing the letter and its image (placeholder if missing)
private struct ASLLetterCard: View {
    let letter: String
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // Primary image (expects assets named ASL_A, ASL_B, ..., ASL_Z)
                Image("ASL_\(letter)")
                    .resizable()
                    .aspectRatio(CGSize(width: 255, height: 285), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel("ASL sign for letter \(letter)")
                    .overlay(
                        Group {
                            // If the asset doesn't exist yet, show a helpful placeholder
                            if UIImage(named: "ASL_\(letter)") == nil {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.08))
                                    VStack(spacing: 8) {
                                        Image(systemName: "hand.raised.fill")
                                            .font(.system(size: 48))
                                            .foregroundStyle(.secondary)
                                        Text("Add image named \"ASL_\(letter)\"")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - ASL Phrases (placeholder)
struct ASLPhrasesPage: View {
    private let sections: [(title: String, items: [String])] = [
        (
            title: "Greetings",
            items: [
                "Hello",
                "Nice to meet you",
                "Good morning",
                "Goodbye"
            ]
        ),
        (
            title: "Basic Questions",
            items: [
                "What is your name?",
                "How are you?",
                "Where is the bathroom?",
                "Can you help me?"
            ]
        ),
        (
            title: "Common Responses",
            items: [
                "Yes",
                "No",
                "Please",
                "Thank you"
            ]
        ),
        (
            title: "Conversation Help",
            items: [
                "I don't understand",
                "Can you repeat that?",
                "Slow down please",
                "One moment"
            ]
        ),
        (
            title: "Introductions",
            items: [
                "My name is ___",
                "I am learning ASL",
                "I'm sorry",
                "Thank you for your patience"
            ]
        ),
        (
            title: "Polite / Everyday Use",
            items: [
                "Excuse me",
                "That's okay",
                "No problem",
                "I appreciate it"
            ]
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<sections.count, id: \.self) { i in
                    PhraseSection(title: sections[i].title, items: sections[i].items)
                }
            }
            .padding()
        }
        .navigationTitle("ASL Phrases")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

private struct PhraseSection: View {
    @AppStorage("accessibility.simplifiedUI") private var simplifiedUI: Bool = false
    @Environment(\.appThemeColor) private var appThemeColor

    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(simplifiedUI ? .system(size: 28, weight: .bold) : .headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(simplifiedUI ? 18 : 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(simplifiedUI ? appThemeColor : appThemeColor.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(appThemeColor.opacity(0.2), lineWidth: 1)
                        )
                )
                .foregroundStyle(simplifiedUI ? .white : .primary)

            ForEach(items, id: \.self) { item in
                NavigationLink {
                    PhraseDetailPage(phrase: item)
                } label: {
                    HStack(spacing: 12) {
                        Text(item)
                            .font(simplifiedUI ? .system(size: 22, weight: .semibold) : .subheadline)
                            .foregroundStyle(simplifiedUI ? .white : .primary)
                        Spacer()
                        Text("->")
                            .font((simplifiedUI ? .system(size: 22, weight: .bold) : .subheadline.weight(.semibold)))
                            .foregroundStyle(simplifiedUI ? .white.opacity(0.9) : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(simplifiedUI ? 18 : 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(simplifiedUI ? appThemeColor.opacity(0.9) : Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.secondary.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PhraseDetailPage: View {
    @AppStorage("accessibility.simplifiedUI") private var simplifiedUI: Bool = false

    let phrase: String
    private var words: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
        return phrase
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: CharacterSet.letters.inverted) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    PhraseWordTile(word: word)
                }
            }
            .padding()
        }
        .navigationTitle(phrase)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

private struct PhraseWordTile: View {
    @AppStorage("accessibility.simplifiedUI") private var simplifiedUI: Bool = false
    @Environment(\.appThemeColor) private var appThemeColor

    let word: String

    private var letters: [Character] {
        word.compactMap { char in
            char.isLetter ? char : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(word)
                .font(simplifiedUI ? .system(size: 26, weight: .bold) : .headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if letters.isEmpty {
                        Text("No letters to display.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                            ASLPhraseLetterCard(letter: letter)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(simplifiedUI ? 18 : 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(simplifiedUI ? appThemeColor.opacity(0.12) : Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct ASLPhraseLetterCard: View {
    let letter: Character

    private var assetName: String {
        "ASL_\(String(letter).uppercased())"
    }

    var body: some View {
        ZStack {
            Image(assetName)
                .resizable()
                .aspectRatio(CGSize(width: 255, height: 285), contentMode: .fit)
                .frame(width: 140, height: 190)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                )
                .accessibilityLabel("ASL letter \(letter)")
                .overlay(
                    Group {
                        if UIImage(named: assetName) == nil {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.08))
                                VStack(spacing: 6) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.secondary)
                                    Text("Add \(assetName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ASL Numbers (1–20 with slider + scroll)
struct ASLNumbersLearnView: View {
    @State private var selectedIndex: Int = 0
    @State private var isDraggingSlider: Bool = false
    @State private var pendingScroll: DispatchWorkItem?
    private let numbers: [Int] = Array(1...20)
    private let scrollDebounce: TimeInterval = 0.04

    private func scheduleScroll(to index: Int, proxy: ScrollViewProxy, animated: Bool) {
        pendingScroll?.cancel()
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(index, anchor: .top)
                }
            } else {
                proxy.scrollTo(index, anchor: .top)
            }
        }
        pendingScroll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDebounce, execute: work)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                HStack {
                    Text("Number: \(numbers[selectedIndex])")
                        .font(.headline)
                    Spacer()
                }

                // Slider to quickly jump between numbers 1..20
                Slider(
                    value: Binding(
                        get: { Double(selectedIndex) },
                        set: { newVal in
                            let idx = Int(newVal.rounded())
                            if idx != selectedIndex {
                                selectedIndex = idx
                                scheduleScroll(to: idx, proxy: proxy, animated: !isDraggingSlider)
                            }
                        }
                    ),
                    in: 0...Double(numbers.count - 1),
                    step: 1,
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            scheduleScroll(to: selectedIndex, proxy: proxy, animated: true)
                        }
                    }
                )
                .accessibilityLabel("Select number")

                Divider().padding(.bottom, 4)

                // Scrollable list of numbers with images
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(0..<numbers.count, id: \.self) { i in
                            ASLNumberCard(number: numbers[i], index: i)
                                .id(i)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: NumberOffsetKey.self,
                                            value: [i: geo.frame(in: .named("numbersScroll")).minY]
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        if isDraggingSlider {
                            isDraggingSlider = false
                        }
                        pendingScroll?.cancel()
                    }
                )
                .coordinateSpace(name: "numbersScroll")
                .onPreferenceChange(NumberOffsetKey.self) { offsets in
                    guard !offsets.isEmpty else { return }
                    if isDraggingSlider { return }
                    // Pick the item whose top is closest to a small inset from the top (e.g., 20 pts)
                    let targetTop: CGFloat = 20
                    let closest = offsets.min(by: { abs($0.value - targetTop) < abs($1.value - targetTop) })
                    if let idx = closest?.key, idx != selectedIndex {
                        selectedIndex = idx
                    }
                }
            }
        }
        .navigationTitle("ASL Numbers")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

// Tracks each number card's vertical position in the ScrollView
private struct NumberOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Single number card showing the number's image (placeholder if missing)
private struct ASLNumberCard: View {
    let number: Int
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // Primary image (expects assets named ASL_1, ASL_2, ..., ASL_20)
                Image("ASL_\(number)")
                    .resizable()
                    .aspectRatio(CGSize(width: 237, height: 406), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel("ASL sign for number \(number)")
                    .overlay(
                        Group {
                            // If the asset doesn't exist yet, show a helpful placeholder
                            if UIImage(named: "ASL_\(number)") == nil {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.08))
                                    VStack(spacing: 8) {
                                        Image(systemName: "hand.raised.fill")
                                            .font(.system(size: 48))
                                            .foregroundStyle(.secondary)
                                        Text("Add image named \"ASL_\(number)\"")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// New helper view InfoTile added after ASLPhrasesPage
private struct InfoTile: View {
    @AppStorage("accessibility.simplifiedUI") private var simplifiedUI: Bool = false
    @Environment(\.appThemeColor) private var appThemeColor

    let title: String
    let text: String

    var body: some View {
        Group {
            if simplifiedUI {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text)
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(appThemeColor)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.15), lineWidth: 1)
                        )
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(text)")
    }
}

#Preview {
    HomeView()
}
