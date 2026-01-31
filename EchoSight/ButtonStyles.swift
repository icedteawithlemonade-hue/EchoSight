import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.appThemeColor) private var appThemeColor

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
                    .stroke(borderColor(pressed: configuration.isPressed), lineWidth: prominent ? 0 : 1)
            )
            .foregroundStyle(foregroundColor(pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.12), radius: configuration.isPressed ? 4 : 6, x: 0, y: configuration.isPressed ? 2 : 3)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if prominent {
            return appThemeColor.opacity(pressed ? 0.75 : 1.0)
        }
        return pressed ? appThemeColor.opacity(0.38) : Color(.systemBackground)
    }

    private func borderColor(pressed: Bool) -> Color {
        appThemeColor.opacity(pressed ? 0.85 : 0.35)
    }

    private func foregroundColor(pressed: Bool) -> Color {
        if prominent {
            return .white
        }
        return pressed ? appThemeColor : .primary
    }
}

struct PressFeedbackButtonStyle: ButtonStyle {
    @Environment(\.appThemeColor) private var appThemeColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(appThemeColor.opacity(configuration.isPressed ? 0.5 : 0.0), lineWidth: 2)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
