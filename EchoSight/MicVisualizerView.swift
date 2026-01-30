import SwiftUI

struct MicVisualizerView: View {
    @StateObject private var meter = AudioBandsMeter()

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Mic Visualizer")
                    .font(.title2.bold())
                Spacer()
                Circle()
                    .fill(meter.isRunning ? .green : .secondary)
                    .frame(width: 10, height: 10)
            }

            BandsBarView(bands: meter.bands, calibrated: meter.calibrated)

            HStack(spacing: 12) {
                Button(meter.isRunning ? "Stop" : "Start") {
                    if meter.isRunning {
                        meter.stop()
                    } else {
                        meter.requestPermissionAndStart()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Calibrate") {
                    meter.calibrate(seconds: 2.0)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    Text(String(format: "%.2f", meter.sensitivity))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $meter.sensitivity, in: 0.6...1.8, step: 0.05)
            }

            Text(meter.calibrated ? "Calibrated (uses ambient baseline)" : "Not calibrated (baseline = 0)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .onDisappear { meter.stop() }
    }
}

private struct BandsBarView: View {
    let bands: [Float]
    let calibrated: Bool

    private let labels = ["Low", "L-Mid", "Mid", "H-Mid", "High"]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<min(bands.count, 5), id: \.self) { i in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 46, height: 170)

                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.85))
                                .frame(width: 46, height: max(6, 170 * CGFloat(bands[i])))

                            if calibrated {
                                // simple baseline marker line (visual cue only)
                                Rectangle()
                                    .fill(Color.white.opacity(0.55))
                                    .frame(width: 46, height: 2)
                                    .offset(y: -170 * 0.12) // purely visual; baseline value is not exposed here
                            }
                        }
                        Text(labels[i])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio frequency bands visualizer")
    }
}
