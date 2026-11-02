import AppKit
import SwiftUI

struct StorageLocationBrowserView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: StorageLocationBrowserViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var hasLoadedContents = false
    @State private var hasMutatedContents = false

    private let onMutation: @Sendable ([StorageLocationBrowserItem]) async -> Void
    private let onItemsUpdated: @Sendable ([StorageLocationBrowserItem]) -> Void

    init(
        snapshot: StorageLocationSnapshot,
        cachedItems: [StorageLocationBrowserItem],
        onMutation: @escaping @Sendable ([StorageLocationBrowserItem]) async -> Void,
        onItemsUpdated: @escaping @Sendable ([StorageLocationBrowserItem]) -> Void
        ) {
        _viewModel = StateObject(
            wrappedValue: StorageLocationBrowserViewModel(
                locationTitle: snapshot.location.title,
                locationID: snapshot.id,
                basePath: snapshot.absolutePath,
                initialItems: cachedItems
            )
        )
        self.onMutation = onMutation
        self.onItemsUpdated = onItemsUpdated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            listSurface
            footer
        }
        .padding(20)
        .background(AppGradientBackground())
        .task {
            guard viewModel.items.isEmpty else { return }
            await refreshAndCache()
        }
        .onAppear {
            hasLoadedContents = !viewModel.items.isEmpty
        }
        .onDisappear {
            guard hasLoadedContents else { return }
            let items = viewModel.items
            onItemsUpdated(items)
            guard hasMutatedContents else { return }
            Task {
                await onMutation(items)
            }
        }
        .alert("Delete selected files and folders?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.deleteSelected() != nil {
                        hasLoadedContents = true
                        hasMutatedContents = true
                        onItemsUpdated(viewModel.items)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(viewModel.selectedCount) selected item(s) from disk.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Browse \(viewModel.locationTitle)")
                    .font(XNoxTypography.sectionTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .xNoxSecondaryButton()
            }

            Text(viewModel.basePath)
                .font(XNoxTypography.mono)
                .foregroundStyle(XNoxPalette.textSecondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Refresh") {
                Task {
                    await refreshAndCache()
                }
            }
            .xNoxPrimaryButton()
            .disabled(viewModel.isLoading || viewModel.isDeleting)

            Button("Select All") {
                viewModel.selectAll()
            }
            .xNoxSecondaryButton()
            .disabled(viewModel.items.isEmpty || viewModel.isLoading || viewModel.isDeleting)

            Button("Clear Selection") {
                viewModel.clearSelection()
            }
            .xNoxSecondaryButton()
            .disabled(viewModel.selectedCount == 0 || viewModel.isDeleting)

            Spacer()

            Button {
                isDeleteConfirmationPresented = true
            } label: {
                HStack(spacing: 6) {
                    if viewModel.canDeleteSelected {
                        Image(systemName: "trash.fill")
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text("Delete Selected")
                }
            }
            .xNoxDestructiveButton()
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewModel.canDeleteSelected)
            .disabled(!viewModel.canDeleteSelected)
        }
    }

    private var listSurface: some View {
        Group {
            if viewModel.items.isEmpty, !viewModel.isLoading {
                EmptyStateView(
                    title: "Folder Is Empty",
                    message: "No files or subfolders were found at this location.",
                    systemImage: "tray"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardSurface()
    }

    private func itemRow(_ item: StorageLocationBrowserItem) -> some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { viewModel.isSelected(item.id) },
                    set: { isSelected in
                        viewModel.setSelected(
                            isSelected,
                            for: item.id,
                            extendingRange: NSEvent.modifierFlags.contains(.shift)
                        )
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: item.systemImage)
                .font(XNoxTypography.caption.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(XNoxPalette.accentStart)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(XNoxTypography.bodyStrong)
                    .foregroundStyle(XNoxPalette.textPrimary)
                    .lineLimit(1)

                Text("Created: \(item.createdAtLabel)")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .lineLimit(1)

                Text("Last used: \(item.lastUsedAtLabel)")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            sizePill(for: item)

            Button {
                viewModel.openInFinder(itemID: item.id)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(XNoxTypography.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(XNoxPalette.accentStart)
            .help("Reveal in Finder")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface()
        .overlay(
            RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                .stroke(recencyBorderColor(for: item), lineWidth: 1.35)
        )
    }

    private func sectionView(_ section: StorageLocationBrowserSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(recencyColor(for: section.band))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(XNoxTypography.bodyStrong)
                        .foregroundStyle(XNoxPalette.textPrimary)

                    Text(section.detail)
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(section.items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let deletionProgress = viewModel.deletionProgress {
                ProgressView(value: deletionProgress.fractionCompleted) {
                    Text("Deleting selected items")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                } currentValueLabel: {
                    Text("\(deletionProgress.completedUnitCount)/\(deletionProgress.totalUnitCount)")
                        .font(XNoxTypography.mono)
                        .foregroundStyle(XNoxPalette.textSecondary)
                }
                .tint(XNoxPalette.accentStart)
            }

            HStack {
                Text(viewModel.statusMessage)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .lineLimit(2)

                Spacer()

                Text(viewModel.selectedSummaryLabel)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshAndCache() async {
        await viewModel.refresh()
        hasLoadedContents = true
        onItemsUpdated(viewModel.items)
    }

    private struct SizePillStyle {
        let text: Color
        let background: Color
        let border: Color
    }

    private func sizePill(for item: StorageLocationBrowserItem) -> some View {
        let style = sizePillStyle(for: item.sizeBytes)
        return Text(item.sizeLabel)
            .font(XNoxTypography.mono)
            .foregroundStyle(style.text)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.border, lineWidth: 1)
            )
    }

    private func sizePillStyle(for sizeBytes: Int64) -> SizePillStyle {
        let oneGB: Int64 = 1_024 * 1_024 * 1_024
        let severityColor: Color

        if sizeBytes >= 8 * oneGB {
            severityColor = XNoxPalette.error
        } else if sizeBytes >= 2 * oneGB {
            severityColor = Color(nsColor: .systemOrange)
        } else if sizeBytes >= 500 * 1_024 * 1_024 {
            severityColor = Color(nsColor: .systemYellow)
        } else if sizeBytes > 0 {
            severityColor = XNoxPalette.success
        } else {
            return SizePillStyle(
                text: XNoxPalette.textSecondary,
                background: XNoxPalette.panelInsetBackground,
                border: XNoxPalette.panelBorder
            )
        }

        return SizePillStyle(
            text: severityColor,
            background: severityColor.opacity(0.16),
            border: severityColor.opacity(0.88)
        )
    }

    private func recencyBorderColor(for item: StorageLocationBrowserItem) -> Color {
        recencyColor(for: item.recencyBand)
    }

    private func recencyColor(for band: StorageItemRecencyBand) -> Color {
        switch band {
        case .recent:
            return XNoxPalette.success
        case .month:
            return Color(nsColor: .systemYellow)
        case .sixMonths:
            return Color(nsColor: .systemOrange)
        case .year:
            return XNoxPalette.error
        case .unknown:
            return XNoxPalette.panelBorder
        }
    }
}
