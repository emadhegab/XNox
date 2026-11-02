import SwiftUI

struct SectionHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: XNoxTheme.space2) {
            Text(title)
                .font(XNoxTypography.display)
                .foregroundStyle(XNoxPalette.textPrimary)
            Text(subtitle)
                .font(XNoxTypography.body)
                .foregroundStyle(XNoxPalette.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, XNoxTheme.grid)
    }
}
