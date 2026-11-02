import SwiftUI

struct OperationsHistoryView: View {
    @StateObject private var viewModel = OperationsHistoryViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Operation History",
                    subtitle: "Chronological record of executed commands, statuses, and summaries across features."
                )

                if viewModel.logs.isEmpty {
                    EmptyStateView(
                        title: "History Is Empty",
                        message: "Run any tool action to record command output and completion status here.",
                        systemImage: "clock"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.logs) { log in
                            logCard(for: log)
                        }
                    }
                }
            }
            .padding(XNoxTheme.pagePadding)
        }
    }

    @ViewBuilder
    private func statusBadge(for status: String) -> some View {
        switch status {
        case XNoxOperationStatus.success.rawValue:
            StatusBadge(kind: .good)
        case XNoxOperationStatus.failed.rawValue:
            StatusBadge(kind: .error)
        case XNoxOperationStatus.pending.rawValue:
            StatusBadge(kind: .neutral)
        default:
            StatusBadge(kind: .warning)
        }
    }

    private func logCard(for log: OperationLog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(log.feature)
                    .font(XNoxTypography.cardTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)
                Spacer()
                statusBadge(for: log.status)
            }

            Text(log.command)
                .font(XNoxTypography.mono)
                .foregroundStyle(XNoxPalette.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetSurface()

            if !log.summary.isEmpty {
                Text(log.summary)
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textPrimary)
            }

            Text(log.startedAt.formatted(date: .abbreviated, time: .standard))
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
