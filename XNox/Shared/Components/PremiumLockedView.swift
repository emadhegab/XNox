import SwiftUI

struct PremiumLockedView: View {
    let sectionTitle: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
            SectionHeaderView(
                title: "\(sectionTitle) is a Pro feature",
                subtitle: "Activate a monthly, yearly, or lifetime license key to unlock this section."
            )

            VStack(alignment: .leading, spacing: 12) {
                Label("All power-user sections unlocked", systemImage: "checkmark.circle")
                Label("Lifetime keys never expire", systemImage: "infinity")
                Label("Works offline with grace mode after activation", systemImage: "wifi.slash")
            }
            .font(XNoxTypography.bodyStrong)
            .foregroundStyle(XNoxPalette.textPrimary)

            Button("Open License Settings") {
                onOpenSettings()
            }
            .xNoxPrimaryButton()
        }
        .cardSurface()
        .padding(XNoxTheme.pagePadding)
    }
}
