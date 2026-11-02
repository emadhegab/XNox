import SwiftUI
import UniformTypeIdentifiers

enum SimulatorActionCategory: String, CaseIterable, Identifiable {
    case core
    case localeAndLinks
    case media
    case statusBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core:
            return "Core"
        case .localeAndLinks:
            return "Locale / Links"
        case .media:
            return "Media"
        case .statusBar:
            return "Status Bar"
        }
    }

    var symbolName: String {
        switch self {
        case .core:
            return "switch.2"
        case .localeAndLinks:
            return "link"
        case .media:
            return "photo.on.rectangle.angled"
        case .statusBar:
            return "wifi"
        }
    }
}

struct SimulatorView: View {
    @ObservedObject private var viewModel = SimulatorViewModel.shared
    @State private var isMediaPickerPresented = false
    @State private var showEraseConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var expandedCategories: Set<SimulatorDeviceCategory> = []
    @State private var renameTargetSimulator: SimulatorDevice?
    @State private var renameDraft = ""
    @State private var attachedSimulatorUDIDs: Set<String> = []
    @State private var actionCategoryBySimulator: [String: SimulatorActionCategory] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Simulator",
                    subtitle: "Manage simulator inventory, attach active devices, and run focused actions by category."
                )

                inventoryCard
                createCard
                statusCard
            }
            .padding(XNoxTheme.pagePadding)
        }
        .task {
            await viewModel.refresh()
            await reapplyPersistedValuesOnLaunch()
            syncAttachedStateFromPersistence()
        }
        .onChange(of: viewModel.simulators) {_, _ in
            syncAttachedStateFromPersistence()
        }
        .fileImporter(
            isPresented: $isMediaPickerPresented,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                viewModel.setSelectedMediaURLs(urls)
            case let .failure(error):
                viewModel.statusMessage = error.localizedDescription
            }
        }
        .alert(
            "Erase \(viewModel.selectedSimulator?.name ?? "selected simulator")?",
            isPresented: $showEraseConfirmation
        ) {
            Button("Erase Data", role: .destructive) {
                Task {
                    await viewModel.eraseSelectedSimulator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all installed apps and data from the selected simulator.")
        }
        .alert(
            "Delete \(viewModel.selectedSimulator?.name ?? "selected simulator")?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete Simulator", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedSimulator()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the simulator from your device list.")
        }
        .sheet(item: $renameTargetSimulator) { simulator in
            renameSimulatorSheet(for: simulator)
        }
    }

    private var inventoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Simulator Inventory")
                    .font(XNoxTypography.cardTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)

                Spacer()

                Button("Refresh") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .xNoxSecondaryButton()
                .disabled(viewModel.isBusy)
            }

            if categoriesWithDevices.isEmpty {
                Text("No simulator devices detected. Create one from the form below.")
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetSurface()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(categoriesWithDevices) { category in
                        categorySection(category)
                    }
                }
            }
        }
        .cardSurface()
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Simulator")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            TextField("Simulator Name", text: $viewModel.newSimulatorName)
                .xNoxInputField()

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Device Type")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)

                    Picker("Device Type", selection: $viewModel.selectedDeviceTypeIdentifier) {
                        ForEach(viewModel.deviceTypes) { deviceType in
                            Text(deviceType.name).tag(deviceType.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Runtime")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)

                    Picker("Runtime", selection: $viewModel.selectedRuntimeIdentifier) {
                        ForEach(viewModel.runtimes) { runtime in
                            Text(runtime.name).tag(runtime.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Button("Create Simulator") {
                Task {
                    await viewModel.createSimulator()
                }
            }
            .xNoxPrimaryButton()
            .disabled(
                viewModel.isBusy ||
                viewModel.selectedRuntimeIdentifier.isEmpty ||
                viewModel.selectedDeviceTypeIdentifier.isEmpty
            )
        }
        .cardSurface()
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.statusMessage)
                .font(XNoxTypography.body)
                .foregroundStyle(XNoxPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .insetSurface()
        .cardSurface()
    }

    private func categorySection(_ category: SimulatorDeviceCategory) -> some View {
        let devices = simulators(in: category)
        let isExpanded = expandedCategories.contains(category)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    toggleCategory(category)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(XNoxTypography.caption.weight(.semibold))
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .frame(width: 12)

                    Label(category.title, systemImage: category.systemImage)
                        .font(XNoxTypography.bodyStrong)
                        .foregroundStyle(XNoxPalette.textPrimary)

                    Spacer()

                    Text("\(devices.count)")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(XNoxPalette.panelInsetBackground)
                        .clipShape(Capsule(style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(devices) { simulator in
                        simulatorRow(simulator)
                    }
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                .fill(XNoxPalette.panelInsetBackground.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                .stroke(XNoxPalette.panelBorder.opacity(0.8), lineWidth: 1)
        )
        .clipped()
    }

    private func simulatorRow(_ simulator: SimulatorDevice) -> some View {
        let isSelected = simulator.udid == viewModel.selectedSimulatorUDID
        let isAttached = attachedSimulatorUDIDs.contains(simulator.udid)
        let isActive = isSelected || isAttached

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    viewModel.selectedSimulatorUDID = isSelected ? nil : simulator.udid
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(simulator.name)
                            .font(XNoxTypography.bodyStrong)
                            .foregroundStyle(XNoxPalette.textPrimary)

                        Text(simulator.runtimeName)
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)

                        Text(lastUsedLabel(for: simulator))
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)

                        if let availabilityIssue = simulator.availabilityIssue {
                            Text("Unavailable: \(availabilityIssue)")
                                .font(XNoxTypography.caption)
                                .foregroundStyle(XNoxPalette.error)
                                .lineLimit(2)
                        }

                        Text(simulator.udid)
                            .font(XNoxTypography.mono)
                            .foregroundStyle(XNoxPalette.textSecondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        statusPill(
                            title: simulator.state,
                            color: simulator.isBooted ? XNoxPalette.success : XNoxPalette.textSecondary
                        )

                        if !simulator.isAvailable {
                            statusPill(
                                title: "Unavailable",
                                color: XNoxPalette.error
                            )
                        }

                        if simulator.isBooted {
                            attachToggleButton(for: simulator, isAttached: isAttached)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .buttonStyle(.plain)

            if isSelected {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(XNoxPalette.panelBorder.opacity(0.75))
                    .frame(height: 1)
                    .padding(.horizontal, 10)

                inlineActions(for: simulator)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                .fill(isActive ? XNoxPalette.panelInsetBackground.opacity(1) : XNoxPalette.panelInsetBackground.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XNoxTheme.controlCornerRadius, style: .continuous)
                .stroke(
                    isActive ? XNoxPalette.accentStart : XNoxPalette.panelBorder,
                    lineWidth: isActive ? 1.4 : 1
                )
        )
        .clipped()
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: viewModel.selectedSimulatorUDID)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: attachedSimulatorUDIDs)
    }

    private func inlineActions(for simulator: SimulatorDevice) -> some View {
        let canRunBootDependentActions = simulator.isAvailable && !viewModel.isBusy
        let selectedCategory = selectedActionCategory(for: simulator)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Actions for \(simulator.name)")
                    .font(XNoxTypography.bodyStrong)
                    .foregroundStyle(XNoxPalette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Edit Name") {
                    renameDraft = simulator.name
                    renameTargetSimulator = simulator
                }
                .xNoxSecondaryButton()
                .disabled(viewModel.isBusy)

            }

            actionCategoryStrip(for: simulator)

            if !simulator.isAvailable {
                Text("This simulator is unavailable on this machine and boot-dependent actions are disabled.")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.error)
            }

            Group {
                switch selectedCategory {
                case .core:
                    coreActionsSection(for: simulator, canRunBootDependentActions: canRunBootDependentActions)
                case .localeAndLinks:
                    localeAndLinksSection(for: simulator, canRunBootDependentActions: canRunBootDependentActions)
                case .media:
                    mediaSection(for: simulator, canRunBootDependentActions: canRunBootDependentActions)
                case .statusBar:
                    statusBarSection(for: simulator, canRunBootDependentActions: canRunBootDependentActions)
                }
            }
            .insetSurface()
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    @ViewBuilder
    private func attachToggleButton(for simulator: SimulatorDevice, isAttached: Bool) -> some View {
        if isAttached {
            Button {
                toggleAttach(for: simulator)
            } label: {
                Label("Detach from Sim", systemImage: "bolt.slash")
            }
            .xNoxSecondaryButton()
            .disabled(viewModel.isBusy)
            .help("Detach this simulator from the actions panel.")
        } else {
            Button {
                toggleAttach(for: simulator)
            } label: {
                Label("Attach to Sim", systemImage: "bolt.fill")
            }
            .xNoxPrimaryButton()
            .disabled(viewModel.isBusy)
            .help("Attach this simulator to open quick actions panel.")
        }
    }

    private func actionCategoryStrip(for simulator: SimulatorDevice) -> some View {
        let selectedCategory = selectedActionCategory(for: simulator)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SimulatorActionCategory.allCases) { category in
                    let isSelected = category == selectedCategory
                    Button {
                        actionCategoryBySimulator[simulator.udid] = category
                    } label: {
                        Label(category.title, systemImage: category.symbolName)
                            .font(XNoxTypography.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .foregroundStyle(isSelected ? XNoxPalette.textPrimary : XNoxPalette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                isSelected
                                    ? XNoxPalette.accentStart.opacity(0.16)
                                    : XNoxPalette.panelInsetBackground.opacity(0.8)
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isSelected ? XNoxPalette.accentStart.opacity(0.45) : XNoxPalette.panelBorder, lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func coreActionsSection(for simulator: SimulatorDevice, canRunBootDependentActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Boot") {
                    runForSimulator(simulator) {
                        await viewModel.bootSelectedSimulator()
                    }
                }
                .xNoxPrimaryButton()
                .disabled(!canRunBootDependentActions)

                Button("Erase Data") {
                    viewModel.selectedSimulatorUDID = simulator.udid
                    showEraseConfirmation = true
                }
                .xNoxDestructiveButton()
                .disabled(viewModel.isBusy)

                Button("Delete") {
                    viewModel.selectedSimulatorUDID = simulator.udid
                    showDeleteConfirmation = true
                }
                .xNoxDestructiveButton()
                .disabled(viewModel.isBusy)
            }
        }
    }

    private func localeAndLinksSection(for simulator: SimulatorDevice, canRunBootDependentActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Locale")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)

            HStack(spacing: 8) {
                TextField("en_US", text: $viewModel.localeIdentifier)
                    .xNoxInputField()

                Button("Apply") {
                    runForSimulator(simulator) {
                        await viewModel.applyLocaleToSelectedSimulator()
                    }
                }
                .xNoxSecondaryButton()
                .disabled(!canRunBootDependentActions)
            }

            Text("Open URL / Deep Link")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)

            HStack(spacing: 8) {
                TextField("https://example.com or myapp://home", text: $viewModel.urlToOpen)
                    .xNoxInputField()

                Button("Open") {
                    runForSimulator(simulator) {
                        await viewModel.openURLInSelectedSimulator()
                    }
                }
                .xNoxSecondaryButton()
                .disabled(!canRunBootDependentActions)
            }
        }
    }

    private func mediaSection(for simulator: SimulatorDevice, canRunBootDependentActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Choose Files") {
                    isMediaPickerPresented = true
                }
                .xNoxSecondaryButton()
                .disabled(viewModel.isBusy)

                Button("Add to Photos") {
                    runForSimulator(simulator) {
                        await viewModel.addSelectedMediaToLibrary()
                    }
                }
                .xNoxPrimaryButton()
                .disabled(!canRunBootDependentActions || viewModel.selectedMediaURLs.isEmpty)
            }

            if !viewModel.selectedMediaURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.selectedMediaURLs, id: \.path) { url in
                        HStack(spacing: 8) {
                            Text(url.lastPathComponent)
                                .font(XNoxTypography.caption)
                                .foregroundStyle(XNoxPalette.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                removeMediaSelection(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(XNoxPalette.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func statusBarSection(for simulator: SimulatorDevice, canRunBootDependentActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("9:41", text: $viewModel.statusBarTime)
                    .xNoxInputField()

                Picker("Network", selection: $viewModel.statusBarNetwork) {
                    ForEach(SimulatorStatusBarNetwork.allCases) { network in
                        Text(network.title).tag(network)
                    }
                }
                .pickerStyle(.menu)

                Picker("Battery", selection: $viewModel.statusBarBatteryState) {
                    ForEach(SimulatorStatusBarBatteryState.allCases) { batteryState in
                        Text(batteryState.title).tag(batteryState)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                Stepper("Wi-Fi: \(viewModel.statusBarWifiBars)", value: $viewModel.statusBarWifiBars, in: 0 ... 3)
                Stepper("Cell: \(viewModel.statusBarCellularBars)", value: $viewModel.statusBarCellularBars, in: 0 ... 4)
            }
            .font(XNoxTypography.caption)
            .foregroundStyle(XNoxPalette.textSecondary)

            HStack {
                Text("Battery")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
                Spacer()
                Text("\(viewModel.statusBarBatteryLevel)%")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textPrimary)
            }

            Slider(
                value: Binding(
                    get: { Double(viewModel.statusBarBatteryLevel) },
                    set: { viewModel.statusBarBatteryLevel = Int($0.rounded()) }
                ),
                in: 0 ... 100,
                step: 1
            )

            HStack(spacing: 8) {
                Button("Apply") {
                    runForSimulator(simulator) {
                        await viewModel.overrideStatusBarForSelectedSimulator()
                    }
                }
                .xNoxPrimaryButton()
                .disabled(!canRunBootDependentActions)

                Button("Clear") {
                    runForSimulator(simulator) {
                        await viewModel.clearStatusBarOverrideForSelectedSimulator()
                    }
                }
                .xNoxSecondaryButton()
                .disabled(!canRunBootDependentActions)
            }
        }
    }

    private func selectedActionCategory(for simulator: SimulatorDevice) -> SimulatorActionCategory {
        actionCategoryBySimulator[simulator.udid] ?? .core
    }

    private func attach(to simulator: SimulatorDevice) {
        viewModel.selectedSimulatorUDID = simulator.udid
        actionCategoryBySimulator[simulator.udid] = actionCategoryBySimulator[simulator.udid] ?? .core
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            attachedSimulatorUDIDs.insert(simulator.udid)
        }
        viewModel.setSimulatorAttached(udid: simulator.udid, isAttached: true)

        Task {
            await viewModel.attachSelectedSimulator()
            let refreshedSimulator = viewModel.simulators.first(where: { $0.udid == simulator.udid }) ?? simulator
            SimulatorActionsPanelManager.shared.show(
                for: refreshedSimulator,
                viewModel: viewModel,
                anchorFrame: viewModel.attachedSimulatorWindowFrame
            )
            syncAttachedStateFromPersistence()
        }
    }

    private func toggleAttach(for simulator: SimulatorDevice) {
        if attachedSimulatorUDIDs.contains(simulator.udid) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                attachedSimulatorUDIDs.remove(simulator.udid)
            }
            SimulatorActionsPanelManager.shared.close(for: simulator.udid)
            viewModel.setSimulatorAttached(udid: simulator.udid, isAttached: false)
            syncAttachedStateFromPersistence()
        } else {
            attach(to: simulator)
        }
    }

    private func syncAttachedStateFromPersistence() {
        let bootedAttachedSimulators = viewModel.simulators.filter { simulator in
            simulator.isBooted && viewModel.persistedAttachedSimulatorUDIDs.contains(simulator.udid)
        }
        let bootedAttachedUDIDs = Set(bootedAttachedSimulators.map(\.udid))
        attachedSimulatorUDIDs = bootedAttachedUDIDs
        SimulatorActionsPanelManager.shared.synchronizeAttachedSimulators(
            bootedAttachedSimulators,
            viewModel: viewModel,
            preferredFramesByUDID: viewModel.attachedSimulatorFrames(for: bootedAttachedUDIDs)
        )
    }

    private func reapplyPersistedValuesOnLaunch() async {
        let bootedAttachedSimulators = viewModel.simulators.filter { simulator in
            simulator.isBooted && viewModel.persistedAttachedSimulatorUDIDs.contains(simulator.udid)
        }

        for simulator in bootedAttachedSimulators {
            await viewModel.reapplyPersistedOverrides(to: simulator.udid)
        }
    }

    private func runForSimulator(_ simulator: SimulatorDevice, action: @escaping @MainActor () async -> Void) {
        viewModel.selectedSimulatorUDID = simulator.udid
        Task {
            await action()
        }
    }

    private var categoriesWithDevices: [SimulatorDeviceCategory] {
        SimulatorDeviceCategory.allCases.filter { !simulators(in: $0).isEmpty }
    }

    private func simulators(in category: SimulatorDeviceCategory) -> [SimulatorDevice] {
        viewModel.simulators
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastUsedAt ?? .distantPast
                let rhsDate = rhs.lastUsedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func toggleCategory(_ category: SimulatorDeviceCategory) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    private func lastUsedLabel(for simulator: SimulatorDevice) -> String {
        guard let lastUsedAt = simulator.lastUsedAt else {
            return "Last used: unavailable"
        }

        return "Last used: \(lastUsedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func removeMediaSelection(_ url: URL) {
        let filtered = viewModel.selectedMediaURLs.filter { $0 != url }
        viewModel.setSelectedMediaURLs(filtered)
    }

    private func renameSimulatorSheet(for simulator: SimulatorDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Simulator Name")
                .font(XNoxTypography.sectionTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Text(simulator.udid)
                .font(XNoxTypography.mono)
                .foregroundStyle(XNoxPalette.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            TextField("Simulator Name", text: $renameDraft)
                .xNoxInputField()

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    renameTargetSimulator = nil
                }
                .xNoxSecondaryButton()

                Button("Save") {
                    let udid = simulator.udid
                    let newName = renameDraft
                    Task {
                        await viewModel.renameSimulator(udid: udid, newName: newName)
                        renameTargetSimulator = nil
                    }
                }
                .xNoxPrimaryButton()
                .disabled(
                    viewModel.isBusy ||
                    renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    renameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == simulator.name
                )
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(XNoxTypography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .clipShape(Capsule(style: .continuous))
    }
}

private extension SimulatorDeviceCategory {
    var systemImage: String {
        switch self {
        case .iPhone:
            return "iphone"
        case .iPad:
            return "ipad"
        case .appleWatch:
            return "applewatch"
        case .appleTV:
            return "appletv"
        case .appleVision:
            return "visionpro"
        case .iPod:
            return "ipod"
        case .mac:
            return "laptopcomputer"
        case .other:
            return "questionmark.circle"
        }
    }
}
