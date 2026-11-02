import SwiftUI

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(XNoxTheme.space4)
            .background(
                RoundedRectangle(cornerRadius: XNoxTheme.cardCornerRadius, style: .continuous)
                    .fill(XNoxPalette.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XNoxTheme.cardCornerRadius, style: .continuous)
                    .stroke(XNoxPalette.panelBorder, lineWidth: 1)
            )
    }
}

struct InsetSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(XNoxTheme.space3)
            .background(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .fill(XNoxPalette.panelInsetBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .stroke(XNoxPalette.panelBorder.opacity(0.85), lineWidth: 1)
            )
    }
}

struct XNoxPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .font(XNoxTypography.button)
            .foregroundStyle(
                isEnabled
                    ? Color.white.opacity(isPressed ? 0.9 : 1)
                    : XNoxPalette.textSecondary.opacity(0.95)
            )
            .padding(.horizontal, XNoxTheme.space3)
            .padding(.vertical, XNoxTheme.space2)
            .background(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .fill(isEnabled ? XNoxPalette.accentStart : XNoxPalette.panelBorder.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .stroke(isEnabled ? XNoxPalette.accentEnd : XNoxPalette.panelBorder.opacity(0.95), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.74)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

struct XNoxSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .font(XNoxTypography.button)
            .foregroundStyle(
                isEnabled
                    ? XNoxPalette.textPrimary.opacity(isPressed ? 0.75 : 1)
                    : XNoxPalette.textSecondary.opacity(0.9)
            )
            .padding(.horizontal, XNoxTheme.space3)
            .padding(.vertical, XNoxTheme.space2)
            .background(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .fill(
                        XNoxPalette.panelInsetBackground.opacity(
                            isEnabled ? (isPressed ? 0.60 : 1) : 0.42
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .stroke(
                        isEnabled ? XNoxPalette.panelBorder : XNoxPalette.panelBorder.opacity(0.6),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.99 : 1)
            .opacity(isEnabled ? 1 : 0.72)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

struct XNoxDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .font(XNoxTypography.button)
            .foregroundStyle(
                isEnabled
                    ? Color.white.opacity(isPressed ? 0.88 : 1)
                    : XNoxPalette.textSecondary.opacity(0.95)
            )
            .padding(.horizontal, XNoxTheme.space3)
            .padding(.vertical, XNoxTheme.space2)
            .background(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .fill(isEnabled ? XNoxPalette.error : XNoxPalette.panelBorder.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                    .stroke(isEnabled ? XNoxPalette.error.opacity(0.7) : XNoxPalette.panelBorder.opacity(0.95), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.74)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }

    func insetSurface() -> some View {
        modifier(InsetSurface())
    }

    func xNoxPrimaryButton() -> some View {
        buttonStyle(XNoxPrimaryButtonStyle())
    }

    func xNoxSecondaryButton() -> some View {
        buttonStyle(XNoxSecondaryButtonStyle())
    }

    func xNoxDestructiveButton() -> some View {
        buttonStyle(XNoxDestructiveButtonStyle())
    }

    func xNoxInputField() -> some View {
        font(XNoxTypography.bodyStrong)
            .textFieldStyle(.roundedBorder)
    }
}
