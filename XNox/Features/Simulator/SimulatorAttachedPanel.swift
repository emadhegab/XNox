import AppKit
import SwiftUI
import UniformTypeIdentifiers


@MainActor
final class SimulatorActionsPanelManager {
    static let shared = SimulatorActionsPanelManager()

    private var panel: NSPanel?
    private var panelDelegate: PanelCloseDelegate?
    private var trackingTask: Task<Void, Never>?
    private var attachedSimulatorsByUDID: [String: SimulatorDevice] = [:]
    private var attachedWindowToUDID: [CGWindowID: String] = [:]
    private var lastKnownFrameByUDID: [String: CGRect] = [:]
    private var selectedCategoryByUDID: [String: SimulatorActionCategory] = [:]
    private var activeSimulatorUDID: String?
    private weak var sharedViewModel: SimulatorViewModel?

    private init() {}

    func synchronizeAttachedSimulators(
        _ simulators: [SimulatorDevice],
        viewModel: SimulatorViewModel,
        preferredFramesByUDID: [String: CGRect] = [:]
    ) {
        sharedViewModel = viewModel
        attachedSimulatorsByUDID = Dictionary(
            uniqueKeysWithValues: simulators.map { ($0.udid, $0) }
        )
        attachedWindowToUDID = attachedWindowToUDID.filter { attachedSimulatorsByUDID[$0.value] != nil }
        lastKnownFrameByUDID = lastKnownFrameByUDID.filter { attachedSimulatorsByUDID[$0.key] != nil }
        selectedCategoryByUDID = selectedCategoryByUDID.filter { attachedSimulatorsByUDID[$0.key] != nil }
        for (udid, frame) in preferredFramesByUDID where attachedSimulatorsByUDID[udid] != nil {
            lastKnownFrameByUDID[udid] = frame
        }

        guard !attachedSimulatorsByUDID.isEmpty else {
            closeAll()
            return
        }

        updateWindowMappingsFromVisibleWindows()

        if let frontmostWindow = Self.frontmostSimulatorWindow(),
           let resolvedUDID = resolveAttachedUDID(for: frontmostWindow) {
            activeSimulatorUDID = resolvedUDID
            position(panel: ensurePanel(), near: frontmostWindow.frame, animated: false)
        } else if let activeSimulatorUDID,
                  attachedSimulatorsByUDID[activeSimulatorUDID] != nil {
            // Keep current active target.
        } else {
            activeSimulatorUDID = attachedSimulatorsByUDID.keys.first
        }

        let panel = ensurePanel()
        refreshPanelContent()
        startTracking()

        let isSimulatorFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.iphonesimulator"
        let canResolveFrontmostAttached: Bool = {
            guard isSimulatorFrontmost, let frontmostWindow = Self.frontmostSimulatorWindow() else { return false }
            return resolveAttachedUDID(for: frontmostWindow) != nil
        }()
        if canResolveFrontmostAttached {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func show(
        for simulator: SimulatorDevice,
        viewModel: SimulatorViewModel,
        anchorFrame: CGRect?
    ) {
        sharedViewModel = viewModel
        attachedSimulatorsByUDID[simulator.udid] = simulator
        selectedCategoryByUDID[simulator.udid] = selectedCategoryByUDID[simulator.udid] ?? .core
        activeSimulatorUDID = simulator.udid
        if let anchorFrame {
            lastKnownFrameByUDID[simulator.udid] = anchorFrame
        }

        let panel = ensurePanel()
        refreshPanelContent()
        updateWindowMappingsFromVisibleWindows()

        // Prefer attaching to the designated simulator's own window, not merely the current frontmost window.
        var designatedWindow = bestWindow(for: simulator)
        if designatedWindow == nil,
           let frontmostWindow = Self.frontmostSimulatorWindow() {
            let normalizedTitle = frontmostWindow.title.lowercased()
            let normalizedName = simulator.name.lowercased()
            let existingMappedUDID = attachedWindowToUDID[frontmostWindow.id]
            let canReuseFrontmostWindow = existingMappedUDID == nil || existingMappedUDID == simulator.udid
            if (attachedSimulatorsByUDID.count == 1 || normalizedTitle.contains(normalizedName)) && canReuseFrontmostWindow {
                // Recovery fallback after explicit attach request.
                attachedWindowToUDID[frontmostWindow.id] = simulator.udid
                lastKnownFrameByUDID[simulator.udid] = frontmostWindow.frame
                designatedWindow = frontmostWindow
            }
        }

        let simulatorFrame = designatedWindow?.frame ?? frontmostAttachedSimulatorWindow()?.frame ?? anchorFrame
        if designatedWindow != nil {
            activeSimulatorUDID = simulator.udid
            position(panel: panel, near: simulatorFrame, animated: true)
            panel.orderFrontRegardless()
        } else if let simulatorFrame {
            position(panel: panel, near: simulatorFrame, animated: true)
        }
        startTracking()
    }

    func close(for udid: String) {
        attachedSimulatorsByUDID.removeValue(forKey: udid)
        attachedWindowToUDID = attachedWindowToUDID.filter { $0.value != udid }
        lastKnownFrameByUDID.removeValue(forKey: udid)
        selectedCategoryByUDID.removeValue(forKey: udid)
        if activeSimulatorUDID == udid {
            activeSimulatorUDID = nil
        }

        if attachedSimulatorsByUDID.isEmpty {
            closeAll()
            return
        }

        if activeSimulatorUDID == nil {
            activeSimulatorUDID = preferredActiveSimulatorUDID()
        }
        refreshPanelContent()
    }

    func closeAll() {
        trackingTask?.cancel()
        trackingTask = nil
        attachedSimulatorsByUDID.removeAll()
        attachedWindowToUDID.removeAll()
        lastKnownFrameByUDID.removeAll()
        selectedCategoryByUDID.removeAll()
        activeSimulatorUDID = nil

        if let panel {
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
        panelDelegate = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = SimulatorOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("xnox.sim-panel.shared")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 420)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let delegate = PanelCloseDelegate { [weak self] in
            self?.trackingTask?.cancel()
            self?.trackingTask = nil
            self?.panel = nil
            self?.panelDelegate = nil
        }
        panel.delegate = delegate
        self.panel = panel
        panelDelegate = delegate
        return panel
    }

    private func refreshPanelContent() {
        guard let panel,
              let viewModel = sharedViewModel,
              let activeUDID = activeSimulatorUDID,
              let simulator = attachedSimulatorsByUDID[activeUDID] else {
            return
        }
        let selectedCategory = selectedCategoryByUDID[activeUDID] ?? .core

        panel.contentView = NSHostingView(
            rootView: AttachedSimulatorActionsPanelView(
                simulator: simulator,
                viewModel: viewModel,
                initialCategory: selectedCategory,
                onCategoryChange: { [weak self] category in
                    self?.selectedCategoryByUDID[activeUDID] = category
                }
            )
        )
    }

    private func position(panel: NSPanel, near anchorFrame: CGRect?, animated: Bool) {
        let visibleFrame: CGRect
        if let anchorFrame {
            let anchorCenter = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
            visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(anchorCenter) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        } else {
            visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        }
        var targetFrame = panel.frame

        if let anchorFrame {
            let desiredX = anchorFrame.maxX + 12
            let desiredTopY = anchorFrame.maxY
            targetFrame.origin.x = min(max(desiredX, visibleFrame.minX), visibleFrame.maxX - targetFrame.width)
            targetFrame.origin.y = min(max(desiredTopY - targetFrame.height, visibleFrame.minY), visibleFrame.maxY - targetFrame.height)
        } else {
            targetFrame.origin.x = visibleFrame.maxX - targetFrame.width - 20
            targetFrame.origin.y = visibleFrame.maxY - targetFrame.height - 60
        }

        panel.setFrame(targetFrame, display: true, animate: animated)
    }

    private func startTracking() {
        trackingTask?.cancel()
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let panel,
                      !self.attachedSimulatorsByUDID.isEmpty else {
                    break
                }

                let isSimulatorFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.iphonesimulator"
                guard isSimulatorFrontmost else {
                    await MainActor.run {
                        panel.orderOut(nil)
                    }
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    continue
                }

                guard let frontmostWindow = Self.frontmostSimulatorWindow() else {
                    await MainActor.run {
                        panel.orderOut(nil)
                    }
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    continue
                }

                self.updateWindowMappingsFromVisibleWindows()

                let resolvedUDID = self.resolveAttachedUDID(
                    for: (id: frontmostWindow.id, title: frontmostWindow.title, frame: frontmostWindow.frame)
                )

                guard let resolvedUDID,
                      self.attachedSimulatorsByUDID[resolvedUDID] != nil else {
                    await MainActor.run {
                        panel.orderOut(nil)
                    }
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    continue
                }

                await MainActor.run {
                    if resolvedUDID != self.activeSimulatorUDID {
                        self.activeSimulatorUDID = resolvedUDID
                        self.refreshPanelContent()
                    }
                    self.position(panel: panel, near: frontmostWindow.frame, animated: false)
                    if !panel.isVisible {
                        panel.orderFrontRegardless()
                    }
                }

                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func preferredActiveSimulatorUDID() -> String? {
        if let frontmostWindow = frontmostAttachedSimulatorWindow(),
           let resolvedUDID = resolveAttachedUDID(for: frontmostWindow) {
            return resolvedUDID
        }
        return attachedSimulatorsByUDID.keys.first
    }

    private func resolveAttachedUDID(for window: (id: CGWindowID, title: String, frame: CGRect)) -> String? {
        if let mappedUDID = attachedWindowToUDID[window.id],
           attachedSimulatorsByUDID[mappedUDID] != nil {
            lastKnownFrameByUDID[mappedUDID] = window.frame
            return mappedUDID
        }

        if attachedSimulatorsByUDID.count == 1,
           let onlyUDID = attachedSimulatorsByUDID.keys.first,
           !attachedWindowToUDID.values.contains(onlyUDID) {
            if let knownFrame = lastKnownFrameByUDID[onlyUDID] {
                let distance = window.frame.midpointDistance(to: knownFrame)
                if distance < 220 {
                    attachedWindowToUDID[window.id] = onlyUDID
                    lastKnownFrameByUDID[onlyUDID] = window.frame
                    return onlyUDID
                }
            } else if Self.visibleSimulatorWindows().count == 1 {
                attachedWindowToUDID[window.id] = onlyUDID
                lastKnownFrameByUDID[onlyUDID] = window.frame
                return onlyUDID
            }
        }

        if attachedSimulatorsByUDID.count == 1,
           let frameMatchedUDID = bestFrameMatch(for: window.frame) {
            attachedWindowToUDID[window.id] = frameMatchedUDID
            lastKnownFrameByUDID[frameMatchedUDID] = window.frame
            return frameMatchedUDID
        }

        return nil
    }

    private func updateWindowMappingsFromVisibleWindows() {
        let windows = Self.visibleSimulatorWindows()
        guard !windows.isEmpty, !attachedSimulatorsByUDID.isEmpty else { return }

        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let visibleWindowIDs = Set(windows.map(\.id))

        let visibleMappings = attachedWindowToUDID.filter { windowID, udid in
            visibleWindowIDs.contains(windowID) && attachedSimulatorsByUDID[udid] != nil
        }

        // Enforce one-to-one mapping: each attached UDID can map to only one visible window.
        var bestWindowIDByUDID: [String: CGWindowID] = [:]
        for (windowID, udid) in visibleMappings {
            guard let window = windowsByID[windowID] else { continue }
            guard let existingWindowID = bestWindowIDByUDID[udid] else {
                bestWindowIDByUDID[udid] = windowID
                lastKnownFrameByUDID[udid] = window.frame
                continue
            }

            guard let existingWindow = windowsByID[existingWindowID] else {
                bestWindowIDByUDID[udid] = windowID
                lastKnownFrameByUDID[udid] = window.frame
                continue
            }

            let knownFrame = lastKnownFrameByUDID[udid]
            let existingDistance = knownFrame.map { existingWindow.frame.midpointDistance(to: $0) } ?? .greatestFiniteMagnitude
            let newDistance = knownFrame.map { window.frame.midpointDistance(to: $0) } ?? .greatestFiniteMagnitude

            if newDistance < existingDistance {
                bestWindowIDByUDID[udid] = windowID
                lastKnownFrameByUDID[udid] = window.frame
            }
        }

        attachedWindowToUDID = Dictionary(
            uniqueKeysWithValues: bestWindowIDByUDID.map { ($1, $0) }
        )

        var assignedWindowIDs = Set(attachedWindowToUDID.keys)

        for simulator in attachedSimulatorsByUDID.values {
            if let existingWindowID = attachedWindowToUDID.first(where: { $0.value == simulator.udid })?.key,
               let existingWindow = windowsByID[existingWindowID] {
                lastKnownFrameByUDID[simulator.udid] = existingWindow.frame
                continue
            }

            guard let matchedWindow = bestWindowStrict(
                for: simulator,
                in: windows,
                excluding: assignedWindowIDs
            ) else { continue }

            attachedWindowToUDID[matchedWindow.id] = simulator.udid
            lastKnownFrameByUDID[simulator.udid] = matchedWindow.frame
            assignedWindowIDs.insert(matchedWindow.id)
        }
    }

    private func bestWindow(for simulator: SimulatorDevice) -> (id: CGWindowID, title: String, frame: CGRect)? {
        bestWindow(for: simulator, in: Self.visibleSimulatorWindows(), excluding: [])
    }

    private func bestWindow(
        for simulator: SimulatorDevice,
        in windows: [(id: CGWindowID, title: String, frame: CGRect)],
        excluding excludedWindowIDs: Set<CGWindowID>
    ) -> (id: CGWindowID, title: String, frame: CGRect)? {
        let candidateWindows = windows.filter { !excludedWindowIDs.contains($0.id) }
        guard !candidateWindows.isEmpty else { return nil }

        let simulatorName = simulator.name.lowercased()
        let nameMatches = candidateWindows.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(simulatorName)
        }

        if nameMatches.count == 1 {
            return nameMatches[0]
        }

        if let knownFrame = lastKnownFrameByUDID[simulator.udid] {
            let bestByFrame = candidateWindows
                .map { (window: $0, distance: $0.frame.midpointDistance(to: knownFrame)) }
                .min { $0.distance < $1.distance }
            if let bestByFrame, bestByFrame.distance < 280 {
                return bestByFrame.window
            }
        }

        return nil
    }

    private func bestWindowStrict(
        for simulator: SimulatorDevice,
        in windows: [(id: CGWindowID, title: String, frame: CGRect)],
        excluding excludedWindowIDs: Set<CGWindowID>
    ) -> (id: CGWindowID, title: String, frame: CGRect)? {
        let candidateWindows = windows.filter { !excludedWindowIDs.contains($0.id) }
        guard !candidateWindows.isEmpty else { return nil }

        let normalizedName = simulator.name.lowercased()
        let nameMatches = candidateWindows.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(normalizedName)
        }
        if nameMatches.count == 1 {
            return nameMatches[0]
        }

        if let knownFrame = lastKnownFrameByUDID[simulator.udid] {
            let ranked = candidateWindows
                .map { (window: $0, distance: $0.frame.midpointDistance(to: knownFrame)) }
                .sorted { $0.distance < $1.distance }
            if let best = ranked.first, best.distance < 220 {
                let secondDistance = ranked.dropFirst().first?.distance ?? .greatestFiniteMagnitude
                if secondDistance - best.distance > 60 {
                    return best.window
                }
            }
        }

        // Only allow blind mapping when a single simulator is attached.
        if attachedSimulatorsByUDID.count == 1, candidateWindows.count == 1 {
            return candidateWindows[0]
        }

        return nil
    }

    private func bestFrameMatch(for frame: CGRect) -> String? {
        let candidates = lastKnownFrameByUDID
            .filter { attachedSimulatorsByUDID[$0.key] != nil }
            .map { (udid: $0.key, distance: frame.midpointDistance(to: $0.value)) }
            .sorted { $0.distance < $1.distance }

        guard let best = candidates.first else { return nil }
        // Keep match conservative to avoid cross-routing when windows are far apart.
        return best.distance < 280 ? best.udid : nil
    }

    private func frontmostAttachedSimulatorWindow() -> (id: CGWindowID, title: String, frame: CGRect)? {
        let attachedNames = Set(attachedSimulatorsByUDID.values.map { $0.name.lowercased() })
        guard !attachedNames.isEmpty else { return nil }

        return Self.visibleSimulatorWindows().first(where: { window in
            let title = window.title.lowercased()
            return attachedNames.contains(where: { title.contains($0) })
        })
    }

    private static func frontmostSimulatorWindow() -> (id: CGWindowID, title: String, frame: CGRect)? {
        visibleSimulatorWindows().first
    }
    
    private static func visibleSimulatorWindows() -> [(id: CGWindowID, title: String, frame: CGRect)] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowInfoList.compactMap { windowInfo -> (id: CGWindowID, title: String, frame: CGRect)? in
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName == "Simulator" else { return nil }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { return nil }

            guard let windowNumber = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                return nil
            }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = Self.cgFloatValue(boundsDictionary["X"]),
                  let y = Self.cgFloatValue(boundsDictionary["Y"]),
                  let width = Self.cgFloatValue(boundsDictionary["Width"]),
                  let height = Self.cgFloatValue(boundsDictionary["Height"]),
                  width > 0,
                  height > 0 else { return nil }
            let title = (windowInfo[kCGWindowName as String] as? String) ?? ""

            return (
                id: CGWindowID(windowNumber),
                title: title,
                frame: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    private static func cgFloatValue(_ raw: Any?) -> CGFloat? {
        if let value = raw as? CGFloat { return value }
        if let value = raw as? Double { return CGFloat(value) }
        if let value = raw as? Int { return CGFloat(value) }
        if let value = raw as? NSNumber { return CGFloat(value.doubleValue) }
        return nil
    }
}

private extension CGRect {
    func midpointDistance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return sqrt((dx * dx) + (dy * dy))
    }
}

private final class PanelCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class SimulatorOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct AttachedSimulatorActionsPanelView: View {
    let simulator: SimulatorDevice
    @ObservedObject var viewModel: SimulatorViewModel
    let onCategoryChange: (SimulatorActionCategory) -> Void

    @State private var selectedCategory: SimulatorActionCategory
    @State private var isMediaPickerPresented = false
    @State private var showEraseConfirmation = false
    @State private var showDeleteConfirmation = false

    init(
        simulator: SimulatorDevice,
        viewModel: SimulatorViewModel,
        initialCategory: SimulatorActionCategory,
        onCategoryChange: @escaping (SimulatorActionCategory) -> Void
    ) {
        self.simulator = simulator
        self.viewModel = viewModel
        self.onCategoryChange = onCategoryChange
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                categoryStrip
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(XNoxPalette.panelBorder.opacity(0.8))
                    .frame(height: 1)

                Group {
                    switch selectedCategory {
                    case .core:
                        coreActions
                    case .localeAndLinks:
                        localeAndLinksActions
                    case .media:
                        mediaActions
                    case .statusBar:
                        statusBarActions
                    }
                }
                .insetSurface()
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(XNoxPalette.panelBackground.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(XNoxPalette.panelBorder.opacity(0.9), lineWidth: 1)
                )
        )
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
        .confirmationDialog(
            "Erase \(simulator.name)?",
            isPresented: $showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase Data", role: .destructive) {
                Task {
                    await viewModel.eraseSimulator(udid: simulator.udid)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all installed apps and data from this simulator.")
        }
        .confirmationDialog(
            "Delete \(simulator.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Simulator", role: .destructive) {
                Task {
                    await viewModel.deleteSimulator(udid: simulator.udid)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes this simulator.")
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SimulatorActionCategory.allCases) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        selectedCategory = category
                        onCategoryChange(category)
                    } label: {
                        Image(systemName: category.symbolName)
                            .font(XNoxTypography.caption.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .foregroundStyle(isSelected ? XNoxPalette.textPrimary : XNoxPalette.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isSelected
                                    ? XNoxPalette.accentStart.opacity(0.16)
                                    : XNoxPalette.panelInsetBackground.opacity(0.8)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected ? XNoxPalette.accentStart.opacity(0.45) : XNoxPalette.panelBorder,
                                lineWidth: 1
                            )
                    )
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var canRunBootDependentActions: Bool {
        simulator.isAvailable && !viewModel.isBusy
    }

    private var coreActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            HStack(spacing: 8) {
                Button("Erase Data") {
                    showEraseConfirmation = true
                }
                .xNoxDestructiveButton()
                .disabled(viewModel.isBusy)

                Button("Delete") {
                    showDeleteConfirmation = true
                }
                .xNoxDestructiveButton()
                .disabled(viewModel.isBusy)
            }
        }
    }

    private var localeAndLinksActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Locale")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)

            HStack(spacing: 8) {
                TextField("en_US", text: $viewModel.localeIdentifier)
                    .xNoxInputField()

                Button("Apply") {
                    Task {
                        await viewModel.applyLocale(to: simulator.udid)
                    }
                }
                .xNoxSecondaryButton()
                .disabled(!canRunBootDependentActions)
            }

            Text("Open URL / Deep Link")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)

            HStack(spacing: 8) {
                TextField("https://example.com", text: $viewModel.urlToOpen)
                    .xNoxInputField()

                Button("Open") {
                    Task {
                        await viewModel.openURL(in: simulator.udid)
                    }
                }
                .xNoxSecondaryButton()
                .disabled(!canRunBootDependentActions)
            }
        }
    }

    private var mediaActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Choose Files") {
                    isMediaPickerPresented = true
                }
                .xNoxSecondaryButton()
                .disabled(viewModel.isBusy)

                Button("Add to Photos") {
                    Task {
                        await viewModel.addSelectedMediaToLibrary(udid: simulator.udid)
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
                                let filtered = viewModel.selectedMediaURLs.filter { $0 != url }
                                viewModel.setSelectedMediaURLs(filtered)
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

    private var statusBarActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)

            TextField("9:41", text: $viewModel.statusBarTime)
                .xNoxInputField()

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Network")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                    statusBarMenuChip(
                        currentTitle: viewModel.statusBarNetwork.title,
                        symbolName: "antenna.radiowaves.left.and.right"
                    ) {
                        ForEach(SimulatorStatusBarNetwork.allCases) { network in
                            Button {
                                viewModel.statusBarNetwork = network
                            } label: {
                                HStack {
                                    Text(network.title)
                                    if viewModel.statusBarNetwork == network {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Battery State")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                    statusBarMenuChip(
                        currentTitle: viewModel.statusBarBatteryState.title,
                        symbolName: "battery.100"
                    ) {
                        ForEach(SimulatorStatusBarBatteryState.allCases) { batteryState in
                            Button {
                                viewModel.statusBarBatteryState = batteryState
                            } label: {
                                HStack {
                                    Text(batteryState.title)
                                    if viewModel.statusBarBatteryState == batteryState {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wi-Fi Bars")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                    HStack {
                        Text("\(viewModel.statusBarWifiBars)")
                            .font(XNoxTypography.bodyStrong)
                            .foregroundStyle(XNoxPalette.textPrimary)
                        Spacer()
                        Stepper("", value: $viewModel.statusBarWifiBars, in: 0 ... 3)
                            .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cell Bars")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                    HStack {
                        Text("\(viewModel.statusBarCellularBars)")
                            .font(XNoxTypography.bodyStrong)
                            .foregroundStyle(XNoxPalette.textPrimary)
                        Spacer()
                        Stepper("", value: $viewModel.statusBarCellularBars, in: 0 ... 4)
                            .labelsHidden()
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(XNoxPalette.panelInsetBackground.opacity(0.75))
            )

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
            .tint(XNoxPalette.accentStart)

            HStack(spacing: 8) {
                Button("Apply") {
                    Task {
                        await viewModel.overrideStatusBar(for: simulator.udid)
                    }
                }
                .xNoxPrimaryButton()
                .disabled(!canRunBootDependentActions)

                Button("Clear") {
                    Task {
                        await viewModel.clearStatusBarOverride(for: simulator.udid)
                    }
                }
                .xNoxSecondaryButton()
                .disabled(!canRunBootDependentActions)
            }
        }
    }

    private func statusBarMenuChip<Content: View>(
        currentTitle: String,
        symbolName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(XNoxTypography.caption.weight(.semibold))
                    .foregroundStyle(XNoxPalette.textSecondary)
                Text(currentTitle)
                    .font(XNoxTypography.bodyStrong)
                    .foregroundStyle(XNoxPalette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(XNoxPalette.panelInsetBackground.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(XNoxPalette.panelBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

}
