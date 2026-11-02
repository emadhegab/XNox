import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: XNoxTheme.space3) {
            Image(systemName: systemImage)
                .font(XNoxTypography.sectionTitle)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(XNoxPalette.accentStart)
                .frame(width: 56, height: 56)
                .background(XNoxPalette.panelInsetBackground)
                .clipShape(RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                        .stroke(XNoxPalette.panelBorder, lineWidth: 1)
                )

            Text(title)
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Text(message)
                .font(XNoxTypography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(XNoxPalette.textSecondary)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(XNoxTheme.space5)
        .cardSurface()
    }
}
