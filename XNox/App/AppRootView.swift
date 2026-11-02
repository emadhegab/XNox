import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var activityCenter: GlobalActivityCenter
    @State private var sidebarSelection: AppSection?

    var body: some View {
        NavigationSplitView(columnVisibility: $appState.splitViewVisibility) {
            SidebarView(selection: $sidebarSelection)
                .background(XNoxPalette.sidebarBackground)
        } detail: {
            detailView(for: appState.selectedSection ?? .dashboard)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AppGradientBackground())
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        .tint(XNoxPalette.accentStart)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if activityCenter.hasActiveActivities {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(activityCenter.summaryLabel)
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textPrimary)
                    }
                    .padding(.horizontal, XNoxTheme.space3)
                    .padding(.vertical, XNoxTheme.space2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(XNoxPalette.panelInsetBackground)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(XNoxPalette.panelBorder, lineWidth: 1)
                    )
                    .help(activityCenter.tooltipText)
                }
            }
        }
        .sheet(isPresented: $appState.isSettingsModalPresented) {
            SettingsModalView()
        }
        .task {
            if sidebarSelection != appState.selectedSection {
                sidebarSelection = appState.selectedSection
            }
        }
        .onChange(of: sidebarSelection) { _, newValue in
            guard appState.selectedSection != newValue else { return }
            appState.selectedSection = newValue

            if let rawValue = newValue?.rawValue {
                appState.settings.persistLastSelectedSection(rawValue)
            }
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            guard sidebarSelection != newValue else { return }
            sidebarSelection = newValue
        }
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .xcodes:
            XcodeManagerView()
        case .simulator:
            SimulatorView()
        case .storage:
            StorageView()
        case .signing:
            SigningView()
        case .devices:
            DeviceRegistrationView {
                appState.selectedSection = .signing
            }
        case .history:
            OperationsHistoryView()
        case .settings:
            SettingsView(presentation: .embedded)
        }
    }
}
