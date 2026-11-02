import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var didAppear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Control Center",
                    subtitle: "Check your local toolchain before simulator workflows."
                )

                healthOverviewCard

                if let installErrorMessage = viewModel.installErrorMessage {
                    Text(installErrorMessage)
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                }

                if viewModel.toolStatuses.isEmpty {
                    EmptyStateView(
                        title: "Scan Required",
                        message: "Run a toolchain scan to evaluate local readiness.",
                        systemImage: "wrench.and.screwdriver"
                    )
                } else {
                    LazyVGrid(columns: gridColumns, spacing: XNoxTheme.cardSpacing) {
                        ForEach(viewModel.toolStatuses) { status in
                            toolStatusCard(for: status)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }

                
            }
            .padding(XNoxTheme.pagePadding)
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 6)
            .animation(.easeOut(duration: 0.35), value: didAppear)
        }
        .task {
            await viewModel.refresh()
        }
        .onAppear {
            didAppear = true
        }
    }

    private var healthOverviewCard: some View {
        HStack(alignment: .top, spacing: XNoxTheme.space4) {
            VStack(alignment: .leading, spacing: XNoxTheme.space3) {
                HStack(spacing: XNoxTheme.space2) {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 10, height: 10)
                    Text(healthTitle)
                        .font(XNoxTypography.cardTitle)
                        .foregroundStyle(XNoxPalette.textPrimary)
                }

                Text(healthSubtitle)
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textSecondary)

                HStack(spacing: XNoxTheme.space3) {
                    summaryPill(
                        value: "\(readyCount)",
                        label: "Ready",
                        color: XNoxPalette.success
                    )
                    summaryPill(
                        value: "\(attentionCount)",
                        label: "Attention",
                        color: XNoxPalette.warning
                    )
                    summaryPill(
                        value: "\(viewModel.toolStatuses.count)",
                        label: "Tracked",
                        color: XNoxPalette.textSecondary
                    )
                }
            }

            Spacer(minLength: XNoxTheme.space3)

            VStack(alignment: .trailing, spacing: XNoxTheme.space2) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Run Scan") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .xNoxPrimaryButton()
                .disabled(viewModel.isLoading)

                Text("Last updated from local scan")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }
        }
        .cardSurface()
    }

    private var flowConnector: some View {
        Rectangle()
            .fill(XNoxPalette.panelBorder)
            .frame(width: 24, height: 1)
    }

    private func flowStep(number: String, title: String) -> some View {
        HStack(spacing: XNoxTheme.space2) {
            Text(number)
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textPrimary)
                .padding(.horizontal, XNoxTheme.space2)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(XNoxPalette.panelInsetBackground)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(XNoxPalette.panelBorder, lineWidth: 1)
                )

            Text(title)
                .font(XNoxTypography.bodyStrong)
                .foregroundStyle(XNoxPalette.textPrimary)
        }
    }

    private func summaryPill(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(color)
            Text(label)
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
        }
        .padding(.horizontal, XNoxTheme.space3)
        .padding(.vertical, XNoxTheme.space2)
        .background(
            RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                .fill(XNoxPalette.panelInsetBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                .stroke(XNoxPalette.panelBorder, lineWidth: 1)
        )
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320), spacing: XNoxTheme.cardSpacing),
            GridItem(.flexible(minimum: 320), spacing: XNoxTheme.cardSpacing),
        ]
    }

    private var readyCount: Int {
        viewModel.toolStatuses.filter { status in
            status.path != nil && !status.isUpdateAvailable && status.meetsMinimumVersion
        }.count
    }

    private var attentionCount: Int {
        viewModel.toolStatuses.count - readyCount
    }

    private var healthTitle: String {
        if viewModel.toolStatuses.isEmpty {
            return "No Scan Results"
        }
        if attentionCount == 0 {
            return "Environment Healthy"
        }
        return "Action Required"
    }

    private var healthSubtitle: String {
        if viewModel.toolStatuses.isEmpty {
            return "Run the initial scan to inspect versions and command paths."
        }
        if attentionCount == 0 {
            return "All tracked tools meet baseline expectations."
        }
        return "\(attentionCount) tool\(attentionCount == 1 ? "" : "s") need attention before critical workflows."
    }

    private var healthColor: Color {
        if viewModel.toolStatuses.isEmpty {
            return XNoxPalette.textSecondary
        }
        return attentionCount == 0 ? XNoxPalette.success : XNoxPalette.warning
    }

    private func statusDetailRows(for status: ToolStatus) -> some View {
        VStack(alignment: .leading, spacing: XNoxTheme.space2) {
            if let version = status.version {
                LabeledContent("Installed") {
                    Text(version)
                        .font(XNoxTypography.bodyStrong)
                        .foregroundStyle(XNoxPalette.textPrimary)
                }
            }

            if let latestVersion = status.latestAvailableVersion, status.isUpdateAvailable {
                LabeledContent("Latest") {
                    Text(latestVersion)
                        .font(XNoxTypography.bodyStrong)
                        .foregroundStyle(XNoxPalette.warning)
                }
            }
        }
    }

    private func toolStatusCard(for status: ToolStatus) -> some View {
        VStack(alignment: .leading, spacing: XNoxTheme.space3) {
            HStack {
                Text(status.tool.displayName)
                    .font(XNoxTypography.cardTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)
                Spacer()
                StatusBadge(kind: badgeKind(for: status))
            }

            statusDetailRows(for: status)

            if let path = status.path {
                Text(path)
                    .font(XNoxTypography.mono)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .textSelection(.enabled)
                    .insetSurface()
            }

            if let note = status.note {
                Text(note)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.warning)
            }

            if status.path == nil {
                HStack(spacing: XNoxTheme.space2) {
                    Button("Install \(status.tool.displayName)") {
                        viewModel.installMissingDependency(for: status.tool)
                    }
                    .xNoxPrimaryButton()

                    Text(status.tool.installCommand)
                        .font(XNoxTypography.mono)
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .textSelection(.enabled)
                }
            } else if status.isUpdateAvailable {
                HStack(spacing: XNoxTheme.space2) {
                    Button("Update \(status.tool.displayName)") {
                        viewModel.updateDependency(for: status)
                    }
                    .xNoxPrimaryButton()

                    if let updateCommand = status.updateCommand {
                        Text(updateCommand)
                            .font(XNoxTypography.mono)
                            .foregroundStyle(XNoxPalette.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func badgeKind(for status: ToolStatus) -> StatusBadgeKind {
        if status.path == nil {
            return .warning
        }
        if status.isUpdateAvailable {
            return .warning
        }
        return status.meetsMinimumVersion ? .good : .warning
    }
}
