import SwiftUI

struct ContentView: View {
    @State private var showCamera = false
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

                Button(showCamera ? "skibidi camera" : "Camera") {
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
                    print("Button 2 tapped")
                }
                .buttonStyle(.borderedProminent)

                NavigationLink("Go to Second Screen") {
                    SecondView()
                }
                .buttonStyle(.bordered)

                if showCamera {
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
                cameraManager.stop()
            }
        }
    }
}

struct SecondView: View {
    var body: some View {
        Text("Second Screen")
            .font(.title)
    }
}

#Preview {
    ContentView()
}
