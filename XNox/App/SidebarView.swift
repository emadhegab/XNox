import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var licenseService: LicenseService
    @Binding var selection: AppSection?

    var body: some View {
        List(selection: $selection) {
            ForEach(AppSection.allCases, id: \.self) { section in
                Label {
                    HStack(spacing: 6) {
                        Text(section.title)
                            .font(XNoxTypography.bodyStrong)
                            .foregroundStyle(XNoxPalette.textPrimary)
                        if section.requiresPro && !licenseService.isProUnlocked {
                            Image(systemName: "lock.fill")
                                .font(XNoxTypography.caption.weight(.semibold))
                                .foregroundStyle(XNoxPalette.warning)
                        }
                    }
                } icon: {
                    Image(systemName: section.systemImage)
                        .font(XNoxTypography.caption.weight(.semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(XNoxPalette.accentStart)
                        .frame(width: 20)
                }
                    .tag(section)
            }
        }
        .navigationTitle("XNox")
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(XNoxPalette.sidebarBackground)
        
    }
}
