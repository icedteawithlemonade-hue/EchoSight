import Combine
import SwiftUI

final class AppFlow: ObservableObject {
    @Published var phase: Phase = .loading

    enum Phase {
        case loading
        case tutorial
        case main
    }

    init() {
        // Start at loading; we'll advance from LoadingView
    }
}

struct LoadingView: View {
    @EnvironmentObject var flow: AppFlow
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                // App logo if available
                Image("EchoSightLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 160)
                    .accessibilityHidden(true)

                // Progress bar without percentage text
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.blue, .purple, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 12)
                .padding(.horizontal, 32)
            }
            .foregroundStyle(.white)
            .padding()
        }
        .onAppear {
            animateProgress()
        }
    }

    private func animateProgress() {
        // Animate to 100% over ~1.8 seconds, then advance to tutorial
        let duration: Double = 1.8
        withAnimation(.easeInOut(duration: duration)) {
            progress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            // First launch detection
            let hasSeenTutorial = UserDefaults.standard.bool(forKey: "hasSeenTutorial")
            flow.phase = hasSeenTutorial ? .main : .tutorial
        }
    }
}

struct TutorialView: View {
    @EnvironmentObject var flow: AppFlow
    @State private var page: Int = 0
    @State private var selectedNeeds: Set<OnboardingNeed> = [.vision, .hearing, .learning]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                TutorialPageView(title: "Welcome to EchoSight", subtitle: "See and hear your world with clarity.", imageName: "EchoSightLogo")
                    .tag(0)
                AdaptiveNeedsPage(selectedNeeds: $selectedNeeds)
                    .tag(1)
                TutorialPageView(title: "Private by Design", subtitle: "EchoSight prioritizes on-device camera, text, audio, Morse, and learning tools.", systemImage: "lock.shield.fill")
                    .tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            HStack {
                if page > 0 {
                    Button("Back") { page = max(0, page - 1) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if page < 2 {
                    Button("Next") { page = min(2, page + 1) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        applyAdaptiveSetup()
                        flow.phase = .main
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding([.horizontal, .bottom])
        }
    }

    private func applyAdaptiveSetup() {
        let defaults = UserDefaults.standard
        let needs = selectedNeeds.isEmpty ? Set(OnboardingNeed.allCases) : selectedNeeds

        defaults.set(true, forKey: "feature.browser.enabled")
        defaults.set(needs.contains(.vision), forKey: "feature.camera.enabled")
        defaults.set(needs.contains(.hearing), forKey: "feature.mic.enabled")
        defaults.set(needs.contains(.learning), forKey: "feature.asl.enabled")
        defaults.set(needs.contains(.communication), forKey: "feature.morse.enabled")
        defaults.set(needs.contains(.simple), forKey: "accessibility.simplifiedUI")

        let startup: StartupTile
        if needs.contains(.vision) {
            startup = .camera
        } else if needs.contains(.hearing) {
            startup = .mic
        } else if needs.contains(.communication) {
            startup = .morse
        } else if needs.contains(.learning) {
            startup = .asl
        } else {
            startup = .none
        }

        defaults.set(startup != .none, forKey: "startup.open.enabled")
        defaults.set(startup.rawValue, forKey: "startup.open.tile")
        defaults.set(true, forKey: "hasSeenTutorial")

        ActivityHistoryStore.shared.add(.system, title: "Adaptive setup", detail: "Configured EchoSight for \(needs.map(\.title).joined(separator: ", ")).")
    }
}

enum OnboardingNeed: String, CaseIterable, Identifiable {
    case vision
    case hearing
    case learning
    case communication
    case simple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vision: return "Visual assistance"
        case .hearing: return "Audio awareness"
        case .learning: return "ASL learning"
        case .communication: return "Morse tools"
        case .simple: return "Simpler UI"
        }
    }

    var subtitle: String {
        switch self {
        case .vision: return "Camera, OCR, objects"
        case .hearing: return "Mic, captions, sound events"
        case .learning: return "Lessons, signs, phrases"
        case .communication: return "Input, output, haptics"
        case .simple: return "Bigger focused controls"
        }
    }

    var systemImage: String {
        switch self {
        case .vision: return "camera.viewfinder"
        case .hearing: return "ear.and.waveform"
        case .learning: return "hand.raised.fill"
        case .communication: return "antenna.radiowaves.left.and.right"
        case .simple: return "rectangle.grid.1x2"
        }
    }
}

struct AdaptiveNeedsPage: View {
    @Binding var selectedNeeds: Set<OnboardingNeed>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What should EchoSight focus on?")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick what matters. You can change this later in Settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                ForEach(OnboardingNeed.allCases) { need in
                    Button {
                        if selectedNeeds.contains(need) {
                            selectedNeeds.remove(need)
                        } else {
                            selectedNeeds.insert(need)
                        }
                    } label: {
                        NeedSelectionRow(need: need, isSelected: selectedNeeds.contains(need))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

private struct NeedSelectionRow: View {
    let need: OnboardingNeed
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: need.systemImage)
                .font(.title2.weight(.bold))
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(need.title)
                    .font(.headline)
                Text(need.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

struct TutorialPageView: View {
    let title: String
    var subtitle: String? = nil
    var imageName: String? = nil
    var systemImage: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 120))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding()
    }
}

struct RootView: View {
    @StateObject private var flow = AppFlow()
    @AppStorage("theme.color") private var themeColorName: String = ThemeColor.blue.rawValue

    var body: some View {
        let themeColor = ThemeColor(rawValue: themeColorName)?.color ?? .blue
        Group {
            switch flow.phase {
            case .loading:
                LoadingView()
            case .tutorial:
                TutorialView()
            case .main:
                HomeView()
            }
        }
        .tint(themeColor)
        .environment(\.appThemeColor, themeColor)
        .environmentObject(flow)
    }
}

#Preview {
    RootView()
}
