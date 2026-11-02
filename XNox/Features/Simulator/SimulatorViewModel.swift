import Combine
import Foundation

@MainActor
final class SimulatorViewModel: ObservableObject {
    static let shared = SimulatorViewModel()
    nonisolated private static let localeIdentifierKey = "simulator.localeIdentifier"
    nonisolated private static let urlToOpenKey = "simulator.urlToOpen"
    nonisolated private static let statusBarTimeKey = "simulator.statusBar.time"
    nonisolated private static let statusBarNetworkKey = "simulator.statusBar.network"
    nonisolated private static let statusBarWifiBarsKey = "simulator.statusBar.wifiBars"
    nonisolated private static let statusBarCellularBarsKey = "simulator.statusBar.cellularBars"
    nonisolated private static let statusBarBatteryStateKey = "simulator.statusBar.batteryState"
    nonisolated private static let statusBarBatteryLevelKey = "simulator.statusBar.batteryLevel"

    @Published var simulators: [SimulatorDevice] = []
    @Published var runtimes: [SimulatorRuntime] = []
    @Published var deviceTypes: [SimulatorDeviceType] = []
    @Published var selectedSimulatorUDID: String?

    @Published var newSimulatorName = "XNox iPhone"
    @Published var selectedRuntimeIdentifier = ""
    @Published var selectedDeviceTypeIdentifier = ""

    @Published var localeIdentifier = "en_US"
    @Published var urlToOpen = ""
    @Published var selectedMediaURLs: [URL] = []

    @Published var statusBarTime = "9:41"
    @Published var statusBarNetwork: SimulatorStatusBarNetwork = .wifi
    @Published var statusBarWifiBars = 3
    @Published var statusBarCellularBars = 4
    @Published var statusBarBatteryState: SimulatorStatusBarBatteryState = .charged
    @Published var statusBarBatteryLevel = 72

    @Published var statusMessage = "Ready to manage simulators."
    @Published var isRefreshing = false
    /// Set when `simctl` failed and no devices could be listed; nil after a successful load.
    @Published private(set) var loadError: String?
    @Published var isPerformingAction = false

    var isBusy: Bool {
        isRefreshing || isPerformingAction
    }

    var selectedSimulator: SimulatorDevice? {
        guard let selectedSimulatorUDID else { return nil }
        return simulators.first { $0.udid == selectedSimulatorUDID }
    }

    private let service: SimulatorControlService
    private let historyRecorder: any OperationHistoryRecording
    private var cancellables: Set<AnyCancellable> = []

    init(
        service: SimulatorControlService = SimulatorControlService(),
        historyRecorder: (any OperationHistoryRecording)? = nil
    ) {
        self.service = service
        self.historyRecorder = historyRecorder ?? OperationHistoryRecorder.shared
        loadPersistedPreferences()
        configurePreferencePersistence()
    }

    /// Returns the catalog warnings as an error only when they left us with no devices at all.
    nonisolated static func loadError(warnings: [String], simulatorCount: Int) -> String? {
        guard simulatorCount == 0, !warnings.isEmpty else { return nil }
        return warnings.joined(separator: " | ")
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        defer {
            isRefreshing = false
        }

        do {
            let warnings = try await reloadCatalog(preferredSelection: selectedSimulatorUDID)
            loadError = Self.loadError(warnings: warnings, simulatorCount: simulators.count)
            if warnings.isEmpty {
                if runtimes.isEmpty || deviceTypes.isEmpty {
                    statusMessage = "Loaded \(simulators.count) simulator(s), but runtimes/types are empty. Verify Xcode and simulator runtimes are installed."
                } else {
                    statusMessage = "Loaded \(simulators.count) simulator(s), \(runtimes.count) runtime(s), \(deviceTypes.count) device type(s)."
                }
            } else {
                statusMessage = "Loaded \(simulators.count) simulator(s), \(runtimes.count) runtime(s), \(deviceTypes.count) device type(s). \(warnings.joined(separator: " | "))"
            }
        } catch {
            loadError = simulators.isEmpty ? error.localizedDescription : nil
            statusMessage = error.localizedDescription
        }
    }

    func createSimulator() async {
        guard !isPerformingAction else { return }

        let trimmedName = newSimulatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Enter a simulator name first."
            return
        }

        guard !selectedDeviceTypeIdentifier.isEmpty else {
            statusMessage = "Choose a device type."
            return
        }

        guard !selectedRuntimeIdentifier.isEmpty else {
            statusMessage = "Choose a runtime."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }
        let historyID = historyRecorder.start(
            feature: "Simulator",
            command: "xcrun simctl create '\(trimmedName)' \(selectedDeviceTypeIdentifier) \(selectedRuntimeIdentifier)",
            summary: "Creating simulator \(trimmedName)."
        )

        do {
            let udid = try await service.createSimulator(
                name: trimmedName,
                deviceTypeIdentifier: selectedDeviceTypeIdentifier,
                runtimeIdentifier: selectedRuntimeIdentifier
            )
            _ = try await reloadCatalog(preferredSelection: udid)
            statusMessage = "Created \(trimmedName)."
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            statusMessage = error.localizedDescription
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    func bootSelectedSimulator() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await bootSimulator(udid: udid)
    }

    func bootSimulator(udid: String) async {
        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl boot <udid>",
            successMessage: "Booted selected simulator."
        ) { udid in
            try await self.service.bootSimulator(udid: udid)
        }
    }

    func eraseSelectedSimulator() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await eraseSimulator(udid: udid)
    }

    func eraseSimulator(udid: String) async {
        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl erase <udid>",
            successMessage: "Erased selected simulator."
        ) { udid in
            try await self.service.eraseSimulator(udid: udid)
        }
    }

    func deleteSelectedSimulator() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await deleteSimulator(udid: udid)
    }

    func deleteSimulator(udid: String) async {
        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl delete <udid>",
            successMessage: "Deleted selected simulator."
        ) { udid in
            try await self.service.deleteSimulator(udid: udid)
        }
    }

    func renameSimulator(udid: String, newName: String) async {
        guard !isPerformingAction else { return }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Enter a simulator name first."
            return
        }

        guard simulators.contains(where: { $0.udid == udid }) else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }
        let historyID = historyRecorder.start(
            feature: "Simulator",
            command: "xcrun simctl rename \(udid) '\(trimmedName)'",
            summary: "Renaming simulator to \(trimmedName)."
        )

        do {
            try await service.renameSimulator(udid: udid, name: trimmedName)
            _ = try await reloadCatalog(preferredSelection: udid)
            statusMessage = "Renamed simulator to \(trimmedName)."
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            statusMessage = error.localizedDescription
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    func applyLocaleToSelectedSimulator() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await applyLocale(to: udid)
    }

    func applyLocale(to udid: String) async {
        let locale = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !locale.isEmpty else {
            statusMessage = "Enter a locale like en_US."
            return
        }

        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl spawn <udid> defaults write -g AppleLocale \(locale)",
            successMessage: "Set locale to \(locale). If UI locale does not refresh immediately, relaunch the app in simulator."
        ) { udid in
            try await self.service.bootSimulator(udid: udid)
            try await self.service.setLocale(udid: udid, localeIdentifier: locale)
        }
    }

    func openURLInSelectedSimulator() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await openURL(in: udid)
    }

    func openURL(in udid: String) async {
        let trimmedURL = urlToOpen.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedURL = URL(string: trimmedURL), parsedURL.scheme != nil else {
            statusMessage = "Enter a valid URL with a scheme, for example https://example.com or myapp://home."
            return
        }

        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl openurl <udid> \(trimmedURL)",
            successMessage: "Opened URL in selected simulator."
        ) { udid in
            try await self.service.bootSimulator(udid: udid)
            try await self.service.openURL(udid: udid, rawURL: trimmedURL)
        }
    }

    func addSelectedMediaToLibrary() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await addSelectedMediaToLibrary(udid: udid)
    }

    func addSelectedMediaToLibrary(udid: String) async {
        guard !selectedMediaURLs.isEmpty else {
            statusMessage = "Choose one or more files first."
            return
        }

        var importedCount = 0
        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl addmedia <udid> <files>",
            successMessage: "Added media to Photo Library."
        ) { udid in
            try await self.service.bootSimulator(udid: udid)

            let scopedURLs = self.selectedMediaURLs.map { url in
                (url: url, didStart: url.startAccessingSecurityScopedResource())
            }
            defer {
                for scoped in scopedURLs where scoped.didStart {
                    scoped.url.stopAccessingSecurityScopedResource()
                }
            }

            let paths = scopedURLs.map { $0.url.path }
            importedCount = try await self.service.addMedia(udid: udid, filePaths: paths)
        }
        if importedCount > 0 {
            statusMessage = "Added \(importedCount) file(s) to Photo Library."
        }
    }

    func overrideStatusBarForSelectedSimulator() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await overrideStatusBar(for: udid)
    }

    func overrideStatusBar(for udid: String) async {
        let trimmedTime = statusBarTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTime.isEmpty else {
            statusMessage = "Set a status bar time, for example 9:41."
            return
        }

        let config = SimulatorStatusBarOverrideConfig(
            time: trimmedTime,
            network: statusBarNetwork,
            wifiBars: min(max(statusBarWifiBars, 0), 3),
            cellularBars: min(max(statusBarCellularBars, 0), 4),
            batteryState: statusBarBatteryState,
            batteryLevel: min(max(statusBarBatteryLevel, 0), 100)
        )

        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl status_bar <udid> override ...",
            successMessage: "Applied status bar override."
        ) { udid in
            try await self.service.bootSimulator(udid: udid)
            try await self.service.overrideStatusBar(udid: udid, config: config)
        }
    }

    func clearStatusBarOverrideForSelectedSimulator() async {
        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }
        await clearStatusBarOverride(for: udid)
    }

    func clearStatusBarOverride(for udid: String) async {
        await performAction(
            udid: udid,
            commandDescription: "xcrun simctl status_bar <udid> clear",
            successMessage: "Cleared status bar override."
        ) { udid in
            try await self.service.bootSimulator(udid: udid)
            try await self.service.clearStatusBar(udid: udid)
        }
    }

    func setSelectedMediaURLs(_ urls: [URL]) {
        selectedMediaURLs = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    func removeSelectedMedia(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            selectedMediaURLs.remove(at: index)
        }
    }

    private func performSelectedAction(
        commandDescription: String,
        successMessage: String,
        action: @escaping (_ udid: String) async throws -> Void
    ) async {
        guard !isPerformingAction else { return }

        guard let udid = selectedSimulatorUDID else {
            statusMessage = SimulatorControlError.noSimulatorSelected.localizedDescription
            return
        }

        await performAction(
            udid: udid,
            commandDescription: commandDescription,
            successMessage: successMessage,
            action: action
        )
    }

    private func performAction(
        udid: String,
        commandDescription: String,
        successMessage: String,
        action: @escaping (_ udid: String) async throws -> Void
    ) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        let historyID = historyRecorder.start(
            feature: "Simulator",
            command: commandDescription.replacingOccurrences(of: "<udid>", with: udid),
            summary: "Running simulator action for \(udid)."
        )

        do {
            try await action(udid)
            _ = try await reloadCatalog(preferredSelection: udid)
            statusMessage = successMessage
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            statusMessage = error.localizedDescription
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    private func reloadCatalog(preferredSelection: String?) async throws -> [String] {
        let catalog = try await service.loadCatalog()

        simulators = catalog.simulators
        runtimes = catalog.runtimes
        deviceTypes = catalog.deviceTypes

        if let preferredSelection,
           simulators.contains(where: { $0.udid == preferredSelection }) {
            selectedSimulatorUDID = preferredSelection
        } else if let currentSelection = selectedSimulatorUDID,
                  simulators.contains(where: { $0.udid == currentSelection }) {
            selectedSimulatorUDID = currentSelection
        } else {
            selectedSimulatorUDID =
                simulators.first(where: { $0.isBooted && $0.isAvailable })?.udid ??
                simulators.first(where: \.isAvailable)?.udid ??
                simulators.first?.udid
        }

        if !runtimes.contains(where: { $0.identifier == selectedRuntimeIdentifier }) {
            selectedRuntimeIdentifier = preferredRuntimeIdentifier(from: runtimes)
        }

        if !deviceTypes.contains(where: { $0.identifier == selectedDeviceTypeIdentifier }) {
            selectedDeviceTypeIdentifier = preferredDeviceTypeIdentifier(from: deviceTypes)
        }

        return catalog.warnings
    }

    private func preferredRuntimeIdentifier(from runtimes: [SimulatorRuntime]) -> String {
        runtimes.first(where: { $0.name.localizedCaseInsensitiveContains("iOS") })?.identifier
            ?? runtimes.first?.identifier
            ?? ""
    }

    private func preferredDeviceTypeIdentifier(from deviceTypes: [SimulatorDeviceType]) -> String {
        deviceTypes.first(where: { $0.name.localizedCaseInsensitiveContains("iPhone") })?.identifier
            ?? deviceTypes.first?.identifier
            ?? ""
    }

    private func loadPersistedPreferences() {
        let defaults = UserDefaults.standard
        localeIdentifier = defaults.string(forKey: Self.localeIdentifierKey) ?? localeIdentifier
        urlToOpen = defaults.string(forKey: Self.urlToOpenKey) ?? urlToOpen
        statusBarTime = defaults.string(forKey: Self.statusBarTimeKey) ?? statusBarTime

        if let rawNetwork = defaults.string(forKey: Self.statusBarNetworkKey),
           let network = SimulatorStatusBarNetwork(rawValue: rawNetwork) {
            statusBarNetwork = network
        }

        if defaults.object(forKey: Self.statusBarWifiBarsKey) != nil {
            statusBarWifiBars = defaults.integer(forKey: Self.statusBarWifiBarsKey)
        }
        if defaults.object(forKey: Self.statusBarCellularBarsKey) != nil {
            statusBarCellularBars = defaults.integer(forKey: Self.statusBarCellularBarsKey)
        }

        if let rawBatteryState = defaults.string(forKey: Self.statusBarBatteryStateKey),
           let batteryState = SimulatorStatusBarBatteryState(rawValue: rawBatteryState) {
            statusBarBatteryState = batteryState
        }
        if defaults.object(forKey: Self.statusBarBatteryLevelKey) != nil {
            statusBarBatteryLevel = defaults.integer(forKey: Self.statusBarBatteryLevelKey)
        }
    }

    private func configurePreferencePersistence() {
        $localeIdentifier
            .sink { UserDefaults.standard.set($0, forKey: Self.localeIdentifierKey) }
            .store(in: &cancellables)

        $urlToOpen
            .sink { UserDefaults.standard.set($0, forKey: Self.urlToOpenKey) }
            .store(in: &cancellables)

        $statusBarTime
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarTimeKey) }
            .store(in: &cancellables)

        $statusBarNetwork
            .sink { UserDefaults.standard.set($0.rawValue, forKey: Self.statusBarNetworkKey) }
            .store(in: &cancellables)

        $statusBarWifiBars
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarWifiBarsKey) }
            .store(in: &cancellables)

        $statusBarCellularBars
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarCellularBarsKey) }
            .store(in: &cancellables)

        $statusBarBatteryState
            .sink { UserDefaults.standard.set($0.rawValue, forKey: Self.statusBarBatteryStateKey) }
            .store(in: &cancellables)

        $statusBarBatteryLevel
            .sink { UserDefaults.standard.set($0, forKey: Self.statusBarBatteryLevelKey) }
            .store(in: &cancellables)
    }
}
