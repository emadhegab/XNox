import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection?

    var body: some View {
        List(selection: $selection) {
            ForEach(AppSection.allCases, id: \.self) { section in
                Label {
                    Text(section.title)
                        .font(XNoxTypography.bodyStrong)
                        .foregroundStyle(XNoxPalette.textPrimary)
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
