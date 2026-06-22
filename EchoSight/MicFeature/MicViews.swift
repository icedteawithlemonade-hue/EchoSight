import SwiftUI

// SwiftUI screens for the Mic feature.
// The UI stays simple while MicViewModel handles audio capture, captions,
// sound events, history logging, and haptic alerts.
struct MicTileView: View {
    // Parent page owns MicViewModel; this tile observes and controls it.
    @ObservedObject var viewModel: MicViewModel
    @Environment(\.appThemeColor) private var appThemeColor
    // Drives the small pulsing dot while listening.
    @State private var listeningPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(destination: MicDetailView(viewModel: viewModel)) {
                // The whole card opens the detailed mic screen.
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Mic")
                            .font(.headline)
                        Spacer()
                        Text(viewModel.isListening ? "Listening" : "Off")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.isListening ? .green : .secondary)
                        Circle()
                            // Green dot gives quick live/off status.
                            .fill(viewModel.isListening ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                            .scaleEffect(viewModel.isListening && listeningPulse ? 1.8 : 1.0)
                            .opacity(viewModel.isListening && listeningPulse ? 0.45 : 1.0)
                            .animation(
                                viewModel.isListening
                                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                    : .easeOut(duration: 0.2),
                                value: listeningPulse
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if viewModel.transcriptLines.isEmpty {
                            // Placeholder before speech recognition has text.
                            Text("Live captions appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            // Compact tile shows only the formatted latest lines.
                            ForEach(viewModel.transcriptLines, id: \.self) { line in
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if viewModel.recentEvents.isEmpty {
                                // Empty state keeps horizontal event strip stable.
                                Text("No recent events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            } else {
                                // Recent detected sound events from SoundEventService.
                                ForEach(viewModel.recentEvents) { event in
                                    SoundEventChip(event: event)
                                }
                            }
                        }
                    }

                    MicEQBarsView(bands: viewModel.eqBands, barColor: appThemeColor)
                }
            }
            .buttonStyle(.plain)

            if let error = viewModel.errorBanner {
                // Permission/audio/speech errors appear inline.
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(viewModel.isListening ? "Stop" : "Start") {
                // Delegates all start/stop complexity to MicViewModel.
                viewModel.toggleListening()
            }
            .buttonStyle(.borderedProminent)
            .tint(appThemeColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.secondary.opacity(0.12), lineWidth: 1)
                )
        )
        .onChange(of: viewModel.isListening) { isListening in
            // Start/stop the pulse animation when listening changes.
            listeningPulse = isListening
        }
        .onAppear {
            listeningPulse = viewModel.isListening
        }
    }
}

// Full mic screen with live transcript, detected sound events, and EQ bars.
struct MicDetailView: View {
    // Uses the same view model as the tile, so state stays synchronized.
    @ObservedObject var viewModel: MicViewModel
    @Environment(\.appThemeColor) private var appThemeColor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(viewModel.isListening ? "Listening" : "Off")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.isListening ? .green : .secondary)
                    Spacer()
                    Button(viewModel.isListening ? "Stop" : "Start") {
                        // Same toggle as the tile.
                        viewModel.toggleListening()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appThemeColor)
                }

                Toggle("Noisy mode", isOn: $viewModel.noisyMode)
                    // Noisy mode raises event thresholds in SoundEventService.
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Transcript")
                        .font(.headline)
                    Text(viewModel.fullTranscript.isEmpty ? "Start listening to see captions." : viewModel.fullTranscript)
                        // Full transcript keeps all recognized speech visible.
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Events")
                        .font(.headline)
                    if viewModel.recentEvents.isEmpty {
                        // Empty state before the heuristic detects sounds.
                        Text("No recent sound events detected.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        // Detailed list includes timestamp and confidence.
                        ForEach(viewModel.recentEvents) { event in
                            HStack {
                                Text(event.type.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(event.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(event.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("EQ")
                        .font(.headline)
                    MicEQBarsView(bands: viewModel.eqBands, barColor: appThemeColor)
                }

                if let error = viewModel.errorBanner {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Mic")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Compact label for one detected sound event.
private struct SoundEventChip: View {
    // Small pill shown on the compact mic tile.
    let event: SoundEvent

    var body: some View {
        Text("\(event.type.displayName) \(Int(event.confidence * 100))%")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule().fill(Color.secondary.opacity(0.15))
            )
    }
}

// Draws the five-band EQ meter used by the mic tile and detail screen.
private struct MicEQBarsView: View {
    // Five normalized bands from EQAnalyzer.
    let bands: [Float]
    let barColor: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<min(bands.count, 5), id: \.self) { index in
                // Height maps directly from normalized band value.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(barColor.opacity(0.85))
                    .frame(width: 16, height: max(6, CGFloat(bands[index]) * 60))
                    .shadow(color: barColor.opacity(0.18), radius: 5, x: 0, y: 3)
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: bands)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
