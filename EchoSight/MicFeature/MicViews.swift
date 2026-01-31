import SwiftUI

struct MicTileView: View {
    @ObservedObject var viewModel: MicViewModel
    @Environment(\.appThemeColor) private var appThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(destination: MicDetailView(viewModel: viewModel)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Mic")
                            .font(.headline)
                        Spacer()
                        Text(viewModel.isListening ? "Listening" : "Off")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.isListening ? .green : .secondary)
                        Circle()
                            .fill(viewModel.isListening ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if viewModel.transcriptLines.isEmpty {
                            Text("Live captions appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
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
                                Text("No recent events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            } else {
                                ForEach(viewModel.recentEvents) { event in
                                    SoundEventChip(event: event)
                                }
                            }
                        }
                    }

                    MicEQBarsView(bands: viewModel.eqBands, barColor: appThemeColor)
                }
            }
            .buttonStyle(PressFeedbackButtonStyle())

            if let error = viewModel.errorBanner {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(viewModel.isListening ? "Stop" : "Start") {
                viewModel.toggleListening()
            }
            .buttonStyle(PressableButtonStyle(prominent: true))
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
    }
}

struct MicDetailView: View {
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
                        viewModel.toggleListening()
                    }
                    .buttonStyle(PressableButtonStyle(prominent: true))
                    .tint(appThemeColor)
                }

                Toggle("Noisy mode", isOn: $viewModel.noisyMode)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Transcript")
                        .font(.headline)
                    Text(viewModel.fullTranscript.isEmpty ? "Start listening to see captions." : viewModel.fullTranscript)
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
                        Text("No recent sound events detected.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
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

private struct SoundEventChip: View {
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

private struct MicEQBarsView: View {
    let bands: [Float]
    let barColor: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<min(bands.count, 5), id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(barColor.opacity(0.85))
                    .frame(width: 16, height: max(6, CGFloat(bands[index]) * 60))
            }
        }
        .animation(.easeOut(duration: 0.12), value: bands)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
