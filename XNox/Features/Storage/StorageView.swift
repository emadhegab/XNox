import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @State private var pendingDeleteLocationID: String?
    @State private var browsingSnapshot: StorageLocationSnapshot?
    @State private var isDeleteAllConfirmationPresented = false
    @State private var celebratingLocationID: String?
    @State private var celebrationTrigger = UUID()
    @State private var clearCelebrationTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Storage",
                    subtitle: "Scan known iOS build folders, inspect contents, and reclaim disk space safely."
                )

                summaryCard

                VStack(spacing: 12) {
                    ForEach(viewModel.snapshots) { snapshot in
                        locationCard(for: snapshot)
                    }
                }

                Text(viewModel.statusMessage)
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetSurface()
                    .cardSurface()
            }
            .padding(XNoxTheme.pagePadding)
        }
        .alert(
            "Delete \(pendingSnapshot?.location.title ?? "this folder")?",
            isPresented: showingLocationDeleteAlert,
            presenting: pendingSnapshot
        ) { snapshot in
            Button("Delete", role: .destructive) {
                pendingDeleteLocationID = nil
                Task {
                    await viewModel.delete(locationID: snapshot.id)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteLocationID = nil
            }
        } message: { snapshot in
            Text("This removes all contents in \(snapshot.location.pathLabel).")
        }
        .alert("Delete all managed iOS storage?", isPresented: $isDeleteAllConfirmationPresented) {
            Button("Delete All", role: .destructive) {
                Task {
                    await viewModel.deleteAll()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all listed folders and may remove simulator app data.")
        }
        .sheet(item: $browsingSnapshot) { snapshot in
            StorageLocationBrowserView(
                snapshot: snapshot,
                cachedItems: viewModel.cachedBrowseItems(for: snapshot.id),
                onMutation: { items in
                    await MainActor.run {
                        viewModel.applyBrowsedItems(items, for: snapshot.id)
                    }
                    await viewModel.refresh(locationID: snapshot.id)
                },
                onItemsUpdated: { items in
                    Task { @MainActor in
                        viewModel.updateCachedBrowseItems(items, for: snapshot.id)
                    }
                }
            )
            .frame(minWidth: 860, minHeight: 560)
        }
        .onChange(of: viewModel.lastCleanupCelebrationEvent?.id) { _, _ in
            guard let event = viewModel.lastCleanupCelebrationEvent else { return }
            celebrationTrigger = event.id

            withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                celebratingLocationID = event.locationID
            }

            clearCelebrationTask?.cancel()
            clearCelebrationTask = Task {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.28)) {
                        celebratingLocationID = nil
                    }
                }
            }
        }
        .onDisappear {
            clearCelebrationTask?.cancel()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                metricCard(
                    title: "Reclaimable",
                    value: StorageViewModel.byteString(from: viewModel.liveTotalKnownBytes),
                    systemImage: "externaldrive.fill.badge.minus"
                )
                metricCard(
                    title: "Locations Found",
                    value: "\(viewModel.liveExistingLocationCount)/\(viewModel.snapshots.count)",
                    systemImage: "folder.fill"
                )

                if viewModel.isScanInProgress {
                    scanProgressCard
                }
            }

            HStack(spacing: 10) {
                let canDeleteAll = viewModel.hasContentToDelete && !viewModel.isDeleting && !viewModel.isRefreshing

                Button(viewModel.hasCompletedScan ? "Rescan" : "Start Scan") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .xNoxPrimaryButton()
                .disabled(viewModel.isRefreshing || viewModel.isDeleting)

                Button {
                    isDeleteAllConfirmationPresented = true
                } label: {
                    HStack(spacing: 6) {
                        if canDeleteAll {
                            Image(systemName: "trash.fill")
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text("Delete All")
                    }
                }
                .xNoxDestructiveButton()
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: canDeleteAll)
                .disabled(!canDeleteAll)
            }

            if let deletionProgress = viewModel.deletionProgress {
                ProgressView(value: deletionProgress.fractionCompleted) {
                    Text(deletionProgress.label)
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                } currentValueLabel: {
                    Text("\(deletionProgress.completedUnitCount)/\(deletionProgress.totalUnitCount)")
                        .font(XNoxTypography.mono)
                        .foregroundStyle(XNoxPalette.textSecondary)
                }
                .tint(XNoxPalette.accentStart)
            }
        }
        .cardSurface()
    }

    private var scanProgressCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(XNoxPalette.panelBorder.opacity(0.45), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: max(0.02, viewModel.scanProgressFraction))
                    .stroke(
                        XNoxPalette.accentStart,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.scanProgressFraction)

                Text("\(viewModel.scanProgressPercent)%")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textPrimary)
            }
            .frame(width: 72, height: 72)

            Text("Scanning \(viewModel.scannedLocationCount)/\(viewModel.totalLocationCount)")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
        }
        .frame(width: 160)
        .insetSurface()
    }

    private func metricCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
            Text(value)
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.24), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetSurface()
    }

    @ViewBuilder
    private func locationCard(for snapshot: StorageLocationSnapshot) -> some View {
        let isCelebrating = celebratingLocationID == snapshot.id

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(snapshot.location.title, systemImage: snapshot.location.systemImage)
                    .font(XNoxTypography.cardTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)
                Spacer()
                usageView(for: snapshot)
            }

            Text(snapshot.location.subtitle)
                .font(XNoxTypography.body)
                .foregroundStyle(XNoxPalette.textSecondary)

            Text(snapshot.location.pathLabel)
                .font(XNoxTypography.mono)
                .foregroundStyle(XNoxPalette.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetSurface()

            HStack(alignment: .center, spacing: 10) {
                Text(statusText(for: snapshot))
                    .font(XNoxTypography.caption)
                    .foregroundStyle(statusColor(for: snapshot))

                Spacer()

                Button("Browse") {
                    browsingSnapshot = snapshot
                }
                .xNoxSecondaryButton()
                .disabled(!snapshot.exists || viewModel.isLocationRefreshing(snapshot.id))

                Button("Open in Finder") {
                    viewModel.openInFinder(locationID: snapshot.id)
                }
                .xNoxSecondaryButton()

                Button("Clean") {
                    pendingDeleteLocationID = snapshot.id
                }
                .xNoxSecondaryButton()
                .disabled(!snapshot.exists || snapshot.bytes == 0 || viewModel.isDeleting || viewModel.isLocationRefreshing(snapshot.id))
            }

            Text(snapshot.location.cleanupNote)
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay {
            RoundedRectangle(cornerRadius: XNoxTheme.cardCornerRadius, style: .continuous)
                .fill(Color.green.opacity(isCelebrating ? 0.18 : 0))
        }
        .overlay {
            if isCelebrating {
                StorageConfettiOverlay(trigger: celebrationTrigger)
                    .clipShape(RoundedRectangle(cornerRadius: XNoxTheme.cardCornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isCelebrating)
    }

    private func statusText(for snapshot: StorageLocationSnapshot) -> String {
        if viewModel.isLocationRefreshing(snapshot.id),
           let progress = viewModel.scanProgress(for: snapshot.id) {
            return "Scanning \(progress.filesScanned.formatted()) items • \(StorageViewModel.byteString(from: progress.bytesScanned))"
        }
        if !viewModel.hasScannedLocation(snapshot.id) {
            return "Not scanned yet"
        }
        if let errorMessage = snapshot.errorMessage {
            return "Scanned with warnings: \(errorMessage)"
        }
        if !snapshot.exists {
            return "Not found on this Mac"
        }
        return "\(snapshot.fileCountLabel) • Updated \(snapshot.scannedAt.formatted(date: .omitted, time: .shortened))"
    }

    private func statusColor(for snapshot: StorageLocationSnapshot) -> Color {
        if snapshot.errorMessage != nil {
            return XNoxPalette.warning
        }
        if !snapshot.exists {
            return XNoxPalette.textSecondary
        }
        return XNoxPalette.success
    }

    @ViewBuilder
    private func usageView(for snapshot: StorageLocationSnapshot) -> some View {
        if viewModel.isLocationRefreshing(snapshot.id),
           let progress = viewModel.scanProgress(for: snapshot.id) {
            HStack(spacing: 8) {
                if snapshot.fileCount > 0 {
                    ProgressView(value: locationProgressFraction(snapshot: snapshot, progress: progress))
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Scanning")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.accentStart)

                    Text(StorageViewModel.byteString(from: progress.bytesScanned))
                        .font(XNoxTypography.mono)
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: progress.bytesScanned)
                }
            }
        } else {
            Text(snapshot.usageLabel)
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.accentStart)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.24), value: snapshot.bytes)
        }
    }

    private func locationProgressFraction(snapshot: StorageLocationSnapshot, progress: LocationScanProgress) -> Double {
        guard snapshot.fileCount > 0 else { return 0.05 }
        return min(1, max(0, Double(progress.filesScanned) / Double(max(snapshot.fileCount, 1))))
    }

    private var pendingSnapshot: StorageLocationSnapshot? {
        guard let pendingDeleteLocationID else { return nil }
        return viewModel.snapshots.first { $0.id == pendingDeleteLocationID }
    }

    private var showingLocationDeleteAlert: Binding<Bool> {
        Binding(
            get: { pendingDeleteLocationID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteLocationID = nil
                }
            }
        )
    }
}

private struct StorageConfettiOverlay: View {
    let trigger: UUID
    @State private var startedAt = Date.now
    private let duration: TimeInterval = 1.4
    private let colors: [Color] = [
        Color.green,
        Color.mint,
        Color.yellow,
        Color.blue,
        Color.orange,
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = min(max(elapsed / duration, 0), 1)

            Canvas { context, size in
                let pieceCount = 50

                for index in 0..<pieceCount {
                    let startX = size.width * CGFloat((index * 37) % 100) / 100
                    let delay = Double(index % 8) * 0.05
                    let local = min(max((progress - delay) / (1 - delay), 0), 1)
                    if local <= 0 || local >= 1 { continue }

                    let drift = CGFloat(sin((Double(index) * 0.67) + (local * .pi * 3.2))) * 22
                    let x = startX + drift
                    let y = -8 + (size.height + 16) * CGFloat(local)
                    let pieceSize = CGFloat(6 + (index % 5))
                    let angle = Angle.degrees((Double(index) * 23) + (local * 720))
                    let alpha = 1 - local
                    let color = colors[index % colors.count].opacity(alpha)

                    var transform = CGAffineTransform(translationX: x, y: y)
                    transform = transform.rotated(by: CGFloat(angle.radians))

                    context.concatenate(transform)
                    context.fill(
                        Path(CGRect(x: -pieceSize / 2, y: -pieceSize / 2, width: pieceSize, height: pieceSize * 0.68)),
                        with: .color(color)
                    )
                    context.concatenate(transform.inverted())
                }
            }
        }
        .onAppear {
            startedAt = .now
        }
        .onChange(of: trigger) { _, _ in
            startedAt = .now
        }
    }
}
