import SwiftUI

// Legacy prototype screen kept for quick camera experiments.
// The shipped app currently starts from RootView, not ContentView, but this file
// is useful when testing CameraManager by itself during development.
struct ContentView: View {
    // Local toggle for showing/hiding the prototype camera preview.
    @State private var showCamera = false
    // Prototype owns its own CameraManager separate from the shipped pages.
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image("EchoSightLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .accessibilityLabel("EchoSight logo")
                    .padding(.top, 8)
                
                Text("Visual Recognition")
                    .font(.largeTitle)
                    .bold()

                Button(showCamera ? "Hide Camera" : "Camera") {
                    // Toggle camera preview for quick CameraManager testing.
                    if showCamera {
                        cameraManager.stop()
                        showCamera = false
                    } else {
                        cameraManager.configure()
                        cameraManager.start()
                        showCamera = true
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Read aloud") {
                    // Placeholder prototype button from early development.
                    print("Button 2 tapped")
                }
                .buttonStyle(.borderedProminent)

                NavigationLink("Go to Second Screen") {
                    SecondView()
                }
                .buttonStyle(.bordered)

                if showCamera {
                    // Raw preview layer shown without detection overlay.
                    CameraPreview(session: cameraManager.session)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding()
            .navigationTitle("Visual Assist")
            .onDisappear {
                // Always stop camera when leaving this prototype screen.
                cameraManager.stop()
            }
        }
    }
}

struct SecondView: View {
    // Placeholder navigation target used while testing NavigationStack.
    var body: some View {
        Text("Second Screen")
            .font(.title)
    }
}

#Preview {
    ContentView()
}
