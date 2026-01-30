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

    var body: some View {
        VStack {
            TabView(selection: $page) {
                TutorialPageView(title: "Welcome to EchoSight", subtitle: "See and hear your world with clarity.", imageName: "EchoSightLogo")
                    .tag(0)
                TutorialPageView(title: "Use the Camera", subtitle: "Point your camera to recognize objects.", systemImage: "camera.viewfinder")
                    .tag(1)
                TutorialPageView(title: "Hear It Aloud", subtitle: "Let EchoSight read text and descriptions.", systemImage: "speaker.wave.2.fill")
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
                        UserDefaults.standard.set(true, forKey: "hasSeenTutorial")
                        flow.phase = .main
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding([.horizontal, .bottom])
        }
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

    var body: some View {
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
        .environmentObject(flow)
    }
}

#Preview {
    RootView()
}
