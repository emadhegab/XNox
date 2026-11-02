import Combine
import Foundation

struct SimulatorDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let udid: String
    let runtimeIdentifier: String
    let runtimeName: String
    let state: String
    let isAvailable: Bool
    let availabilityIssue: String?
    let deviceTypeIdentifier: String
    let lastUsedAt: Date?

    nonisolated init(
        name: String,
        udid: String,
        runtimeIdentifier: String,
        runtimeName: String,
        state: String,
        isAvailable: Bool,
        availabilityIssue: String? = nil,
        deviceTypeIdentifier: String,
        lastUsedAt: Date? = nil
    ) {
        id = udid
        self.name = name
        self.udid = udid
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeName = runtimeName
        self.state = state
        self.isAvailable = isAvailable
        self.availabilityIssue = availabilityIssue
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.lastUsedAt = lastUsedAt
    }

    nonisolated var isBooted: Bool {
        state.caseInsensitiveCompare("Booted") == .orderedSame
    }

    nonisolated var category: SimulatorDeviceCategory {
        let identifierSource = deviceTypeIdentifier.lowercased()
        if identifierSource.contains("iphone") { return .iPhone }
        if identifierSource.contains("ipad") { return .iPad }
        if identifierSource.contains("watch") { return .appleWatch }
        if identifierSource.contains("appletv") || identifierSource.contains("apple-tv") { return .appleTV }
        if identifierSource.contains("vision") { return .appleVision }
        if identifierSource.contains("ipod") { return .iPod }
        if identifierSource.contains("mac") { return .mac }

        // Fallback only when identifier is missing/unknown.
        let nameSource = name.lowercased()
        if nameSource.contains("iphone") { return .iPhone }
        if nameSource.contains("ipad") { return .iPad }
        if nameSource.contains("watch") { return .appleWatch }
        if nameSource.contains("appletv") || nameSource.contains("apple tv") || nameSource.contains("tv") { return .appleTV }
        if nameSource.contains("vision") { return .appleVision }
        if nameSource.contains("ipod") { return .iPod }
        if nameSource.contains("mac") { return .mac }
        return .other
    }
}

enum SimulatorDeviceCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case iPhone
    case iPad
    case appleWatch
    case appleTV
    case appleVision
    case iPod
    case mac
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhone:
            return "iPhone"
        case .iPad:
            return "iPad"
        case .appleWatch:
            return "Apple Watch"
        case .appleTV:
            return "Apple TV"
        case .appleVision:
            return "Apple Vision"
        case .iPod:
            return "iPod"
        case .mac:
            return "Mac"
        case .other:
            return "Other"
        }
    }
}

struct SimulatorRuntime: Identifiable, Hashable, Sendable {
    let id: String
    let identifier: String
    let name: String
    let version: String?
    let isAvailable: Bool

    nonisolated init(identifier: String, name: String, version: String?, isAvailable: Bool) {
        id = identifier
        self.identifier = identifier
        self.name = name
        self.version = version
        self.isAvailable = isAvailable
    }
}

struct SimulatorDeviceType: Identifiable, Hashable, Sendable {
    let id: String
    let identifier: String
    let name: String

    nonisolated init(identifier: String, name: String) {
        id = identifier
        self.identifier = identifier
        self.name = name
    }
}

enum SimulatorStatusBarNetwork: String, CaseIterable, Identifiable {
    case wifi
    case lte
    case fourG = "4g"
    case fiveG = "5g"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .lte:
            return "LTE"
        case .fourG:
            return "4G"
        case .fiveG:
            return "5G"
        }
    }
}

enum SimulatorStatusBarBatteryState: String, CaseIterable, Identifiable {
    case charging
    case charged

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct SimulatorStatusBarOverrideConfig: Sendable {
    let time: String
    let network: SimulatorStatusBarNetwork
    let wifiBars: Int
    let cellularBars: Int
    let batteryState: SimulatorStatusBarBatteryState
    let batteryLevel: Int
}

struct SimulatorCatalog: Sendable {
    let simulators: [SimulatorDevice]
    let runtimes: [SimulatorRuntime]
    let deviceTypes: [SimulatorDeviceType]
    let warnings: [String]
}

enum SimulatorControlError: LocalizedError {
    case commandFailed(command: String, message: String)
    case invalidJSON(String)
    case noSimulatorSelected
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, message):
            if message.isEmpty {
                return "Command failed: \(command)"
            }
            return "Command failed: \(command)\n\(message)"
        case let .invalidJSON(message):
            return "Unable to parse simulator response: \(message)"
        case .noSimulatorSelected:
            return "Select a simulator first."
        case let .invalidInput(message):
            return message
        }
    }
}

actor SimulatorControlService {
    private let simulatorLastUsedKeys = [
        "lastBootedAt",
        "lastBootedDate",
        "lastUsedAt",
    ]

    func loadCatalog() throws -> SimulatorCatalog {
        var warnings: [String] = []

        let runtimes: [SimulatorRuntime]
        do {
            runtimes = try fetchRuntimes()
        } catch {
            runtimes = []
            warnings.append("Runtimes unavailable: \(shortErrorMessage(from: error))")
        }

        let runtimeByIdentifier = Dictionary(
            runtimes.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let simulators: [SimulatorDevice]
        do {
            simulators = try fetchSimulators(runtimeByIdentifier: runtimeByIdentifier)
        } catch {
            simulators = []
            warnings.append("Simulators unavailable: \(shortErrorMessage(from: error))")
        }

        let deviceTypes: [SimulatorDeviceType]
        do {
            deviceTypes = try fetchDeviceTypes()
        } catch {
            deviceTypes = []
            warnings.append("Device types unavailable: \(shortErrorMessage(from: error))")
        }

        return SimulatorCatalog(
            simulators: simulators,
            runtimes: runtimes,
            deviceTypes: deviceTypes,
            warnings: warnings
        )
    }

    func createSimulator(name: String, deviceTypeIdentifier: String, runtimeIdentifier: String) throws -> String {
        let output = try runSimctl([
            "create",
            name,
            deviceTypeIdentifier,
            runtimeIdentifier,
        ])

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func bootSimulator(udid: String) throws {
        do {
            _ = try runSimctl(["boot", udid], timeoutSeconds: 90)
        } catch let error as SimulatorControlError {
            if case let .commandFailed(_, message) = error,
               message.localizedCaseInsensitiveContains("already booted") ||
               message.localizedCaseInsensitiveContains("current state: Booted") {
                // Already booted.
            } else {
                throw error
            }
        }

        // Wait for readiness and then bring Simulator.app to the selected device window.
        _ = try? runSimctl(["bootstatus", udid, "-b"], timeoutSeconds: 120)
        launchSimulatorApp(forUDID: udid)
    }

    func eraseSimulator(udid: String) throws {
        var eraseError: Error?

        // Erase can fail while simulator is transitioning states; retry with shutdown each cycle.
        for attempt in 1 ... 6 {
            _ = try? runSimctl(["shutdown", udid], timeoutSeconds: 90)

            do {
                _ = try runSimctl(["erase", udid], timeoutSeconds: 180)
                return
            } catch {
                eraseError = error
                if attempt < 6 {
                    let backoffMicroseconds = useconds_t(min(4_000_000, 500_000 * attempt))
                    usleep(backoffMicroseconds)
                }
            }
        }

        // Some stale or broken simulators cannot be erased but can still be removed.
        do {
            _ = try runSimctl(["delete", udid], timeoutSeconds: 120)
            return
        } catch {
            let eraseMessage = shortErrorMessage(from: eraseError ?? error)
            let deleteMessage = shortErrorMessage(from: error)
            throw SimulatorControlError.commandFailed(
                command: "xcrun simctl erase \(udid)",
                message: "Erase failed (\(eraseMessage)). Delete fallback failed (\(deleteMessage))."
            )
        }
    }

    func deleteSimulator(udid: String) throws {
        _ = try? runSimctl(["shutdown", udid], timeoutSeconds: 90)
        _ = try runSimctl(["delete", udid], timeoutSeconds: 120)
    }

    func renameSimulator(udid: String, name: String) throws {
        _ = try runSimctl(["rename", udid, name], timeoutSeconds: 60)
    }

    func setLocale(udid: String, localeIdentifier: String) throws {
        let normalizedLocale = localeIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")

        guard !normalizedLocale.isEmpty else {
            throw SimulatorControlError.invalidInput("Locale cannot be empty.")
        }

        let languageCode = normalizedLocale
            .split(separator: "_")
            .first
            .map(String.init) ?? normalizedLocale

        var commandError: Error?
        do {
            _ = try runSimctl(["spawn", udid, "defaults", "write", "NSGlobalDomain", "AppleLocale", normalizedLocale])
            _ = try runSimctl(["spawn", udid, "defaults", "write", "NSGlobalDomain", "AppleLanguages", "-array", languageCode])
        } catch {
            commandError = error
        }

        let didWritePreferencesFile = writeLocaleToGlobalPreferencesFile(
            udid: udid,
            locale: normalizedLocale,
            languageCode: languageCode
        )

        _ = try? runSimctl(["spawn", udid, "killall", "-9", "cfprefsd"])
        _ = try? runSimctl(["spawn", udid, "killall", "-HUP", "SpringBoard"])

        if !didWritePreferencesFile, let commandError {
            throw commandError
        }
    }

    func openURL(udid: String, rawURL: String) throws {
        _ = try runSimctl(["openurl", udid, rawURL])
    }

    func addMedia(udid: String, filePaths: [String]) throws -> Int {
        guard !filePaths.isEmpty else {
            throw SimulatorControlError.invalidInput("Choose at least one file first.")
        }

        let fileManager = FileManager.default
        let accessiblePaths = filePaths.filter { fileManager.isReadableFile(atPath: $0) }
        guard !accessiblePaths.isEmpty else {
            throw SimulatorControlError.invalidInput("Selected files are not readable by the app.")
        }

        do {
            _ = try runSimctl(["addmedia", udid] + accessiblePaths, timeoutSeconds: 90)
            return accessiblePaths.count
        } catch {
            var importedCount = 0
            var lastError: Error = error

            for path in accessiblePaths {
                do {
                    _ = try runSimctl(["addmedia", udid, path], timeoutSeconds: 45)
                    importedCount += 1
                    continue
                } catch {
                    lastError = error
                }

                do {
                    _ = try runSimctl(["addmedia", "booted", path], timeoutSeconds: 45)
                    importedCount += 1
                } catch {
                    lastError = error
                }
            }

            guard importedCount > 0 else {
                throw lastError
            }
            return importedCount
        }
    }

    func overrideStatusBar(udid: String, config: SimulatorStatusBarOverrideConfig) throws {
        let normalizedBatteryLevel = min(max(config.batteryLevel, 0), 100)
        let normalizedNetworkArgument = simctlDataNetworkArgument(for: config.network)
        // "charged" in simulator can still display as charging on some runtimes.
        // Map to a non-charging state to consistently remove the bolt icon.
        let batteryStateArgument = (config.batteryState == .charging) ? "charging" : "discharging"
        let baseArguments = [
            "status_bar",
            udid,
            "override",
            "--time", config.time,
            "--batteryState", batteryStateArgument,
            "--batteryLevel", "\(normalizedBatteryLevel)",
        ]

        var candidateArguments: [[String]] = []
        if config.network == .wifi {
            candidateArguments.append(baseArguments + [
                "--dataNetwork", normalizedNetworkArgument,
                "--wifiMode", "active",
                "--wifiBars", "\(config.wifiBars)",
                "--cellularMode", "notSupported",
                "--cellularBars", "0",
            ])
            candidateArguments.append(baseArguments + [
                "--wifiMode", "active",
                "--wifiBars", "\(config.wifiBars)",
                "--cellularMode", "notSupported",
                "--cellularBars", "0",
            ])
        } else {
            let fallbackNetworks = [normalizedNetworkArgument, "lte", "5g"]
            var seenNetworks = Set<String>()
            for network in fallbackNetworks where seenNetworks.insert(network).inserted {
                candidateArguments.append(baseArguments + [
                    "--dataNetwork", network,
                    "--cellularMode", "active",
                    "--cellularBars", "\(config.cellularBars)",
                ])
            }
            candidateArguments.append(baseArguments + [
                "--cellularMode", "active",
                "--cellularBars", "\(config.cellularBars)",
            ])
        }

        // Clear previous overrides so network/icon state does not bleed between modes.
        _ = try? runSimctl(["status_bar", udid, "clear"], timeoutSeconds: 20)
        usleep(140_000)

        var lastError: Error?
        for arguments in candidateArguments {
            do {
                _ = try runSimctl(arguments, timeoutSeconds: 45)
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private func simctlDataNetworkArgument(for network: SimulatorStatusBarNetwork) -> String {
        switch network {
        case .wifi:
            return "wifi"
        case .lte:
            return "lte"
        case .fourG:
            return "4g"
        case .fiveG:
            return "5g"
        }
    }

    func clearStatusBar(udid: String) throws {
        _ = try runSimctl(["status_bar", udid, "clear"])
    }

    private func fetchRuntimes() throws -> [SimulatorRuntime] {
        let output = try runSimctl(["list", "runtimes", "--json"])
        let root = try parseRootJSONDictionary(from: output, label: "runtimes")
        let runtimesAny = arrayValue(root["runtimes"]) ?? []

        let parsedRuntimes: [SimulatorRuntime] = runtimesAny.compactMap { runtimeAny in
            guard let runtime = dictionaryValue(runtimeAny) else { return nil }
            guard let identifier = stringValue(runtime["identifier"]), !identifier.isEmpty else {
                return nil
            }

            let name = stringValue(runtime["name"]) ?? readableRuntimeName(from: identifier)
            let version = stringValue(runtime["version"])
            let isAvailable = availabilityFlag(from: runtime)

            return SimulatorRuntime(
                identifier: identifier,
                name: name,
                version: version,
                isAvailable: isAvailable
            )
        }
        let uniqueParsedRuntimes = uniqueRuntimes(parsedRuntimes)
            .filter(\.isAvailable)
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }

        if !uniqueParsedRuntimes.isEmpty {
            return uniqueParsedRuntimes
        }

        let fallbackOutput = try runSimctl(["list", "runtimes"])
        return uniqueRuntimes(parseRuntimesFromPlainList(fallbackOutput))
    }

    private func fetchDeviceTypes() throws -> [SimulatorDeviceType] {
        let output = try runSimctl(["list", "devicetypes", "--json"])
        let root = try parseRootJSONDictionary(from: output, label: "device types")

        let rawTypes: [Any] = {
            if let deviceTypes = arrayValue(root["devicetypes"]) {
                return deviceTypes
            }
            if let deviceTypes = arrayValue(root["deviceTypes"]) {
                return deviceTypes
            }
            return []
        }()

        var seenIdentifiers = Set<String>()
        let types = rawTypes.compactMap { typeAny -> SimulatorDeviceType? in
            guard let type = dictionaryValue(typeAny) else { return nil }
            guard let identifier = stringValue(type["identifier"]), !identifier.isEmpty else {
                return nil
            }

            guard seenIdentifiers.insert(identifier).inserted else {
                return nil
            }

            let name = stringValue(type["name"]) ?? readableDeviceTypeName(from: identifier)
            return SimulatorDeviceType(identifier: identifier, name: name)
        }

        let sortedTypes = types.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        if !sortedTypes.isEmpty {
            return sortedTypes
        }

        let fallbackOutput = try runSimctl(["list", "devicetypes"])
        return parseDeviceTypesFromPlainList(fallbackOutput)
    }

    private func runSimctl(_ arguments: [String], timeoutSeconds: TimeInterval = 20) throws -> String {
        try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl"] + arguments,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func fetchSimulators(
        runtimeByIdentifier: [String: SimulatorRuntime]
    ) throws -> [SimulatorDevice] {
        let devicesOutput = try runSimctl(["list", "devices", "--json"])
        let root = try parseRootJSONDictionary(from: devicesOutput, label: "devices")
        let devicesRoot = dictionaryValue(root["devices"]) ?? [:]
        let lastUsedByUDID = loadLastUsedDatesByUDID()

        return devicesRoot.flatMap { runtimeIdentifier, runtimeDevicesAny in
            let runtimeDevices = arrayValue(runtimeDevicesAny) ?? []
            return runtimeDevices.compactMap { rawDeviceAny -> SimulatorDevice? in
                guard let rawDevice = dictionaryValue(rawDeviceAny) else { return nil }
                guard let name = stringValue(rawDevice["name"]),
                      !name.isEmpty,
                      let udid = stringValue(rawDevice["udid"]),
                      !udid.isEmpty else {
                    return nil
                }

                let runtimeName = runtimeByIdentifier[runtimeIdentifier]?.name ?? readableRuntimeName(from: runtimeIdentifier)
                let state = stringValue(rawDevice["state"]) ?? "Unknown"
                let availability = availabilityDetails(from: rawDevice)
                let hasDeviceDirectory = deviceDirectoryExists(forUDID: udid)
                let isAvailable = availability.isAvailable && hasDeviceDirectory
                let availabilityIssue = availability.issue ?? (hasDeviceDirectory ? nil : "Device files are missing")

                return SimulatorDevice(
                    name: name,
                    udid: udid,
                    runtimeIdentifier: runtimeIdentifier,
                    runtimeName: runtimeName,
                    state: state,
                    isAvailable: isAvailable,
                    availabilityIssue: availabilityIssue,
                    deviceTypeIdentifier: stringValue(rawDevice["deviceTypeIdentifier"]) ?? "",
                    lastUsedAt: lastUsedByUDID[udid]
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.isBooted != rhs.isBooted {
                return lhs.isBooted && !rhs.isBooted
            }
            if lhs.runtimeName != rhs.runtimeName {
                return lhs.runtimeName.localizedStandardCompare(rhs.runtimeName) == .orderedAscending
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func runCommand(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 20
    ) throws -> String {
        let command = ([executable] + arguments).joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let outputURL = temporaryDirectory.appendingPathComponent("xnox-simctl-\(UUID().uuidString)-out.log")
        let errorURL = temporaryDirectory.appendingPathComponent("xnox-simctl-\(UUID().uuidString)-err.log")

        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)

        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path),
              let errorHandle = FileHandle(forWritingAtPath: errorURL.path) else {
            throw SimulatorControlError.commandFailed(
                command: command,
                message: "Unable to open temporary output files."
            )
        }

        process.standardOutput = outputHandle
        process.standardError = errorHandle

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: errorURL)
            throw SimulatorControlError.commandFailed(
                command: command,
                message: error.localizedDescription
            )
        }

        let completedInTime = terminationSemaphore.wait(timeout: .now() + timeoutSeconds) == .success
        if !completedInTime, process.isRunning {
            process.terminate()
            _ = terminationSemaphore.wait(timeout: .now() + 2)
        }

        try? outputHandle.close()
        try? errorHandle.close()

        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
        try? fileManager.removeItem(at: outputURL)
        try? fileManager.removeItem(at: errorURL)

        let outputText = String(decoding: outputData, as: UTF8.self)
        let errorText = String(decoding: errorData, as: UTF8.self)

        if !completedInTime {
            let timeoutMessage = "Timed out after \(Int(timeoutSeconds))s."
            let combinedTimeoutMessage = [timeoutMessage, errorText, outputText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            throw SimulatorControlError.commandFailed(
                command: command,
                message: combinedTimeoutMessage
            )
        }

        guard process.terminationStatus == 0 else {
            let combinedMessage = [errorText, outputText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            throw SimulatorControlError.commandFailed(
                command: command,
                message: combinedMessage
            )
        }

        return outputText
    }

    private func launchSimulatorApp(forUDID udid: String) {
        // Best-effort only: boot success should not fail if Simulator.app launch is blocked.
        _ = try? runCommand(
            executable: "/usr/bin/open",
            arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid],
            timeoutSeconds: 10
        )
    }

    private func readableRuntimeName(from runtimeIdentifier: String) -> String {
        runtimeIdentifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func readableDeviceTypeName(from identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimDeviceType.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func parseRootJSONDictionary(from output: String, label: String) throws -> [String: Any] {
        guard let data = output.data(using: .utf8) else {
            throw SimulatorControlError.invalidJSON("simctl \(label) output is not UTF-8")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SimulatorControlError.invalidJSON(error.localizedDescription)
        }

        guard let root = jsonObject as? [String: Any] else {
            throw SimulatorControlError.invalidJSON("simctl \(label) JSON root is not an object")
        }

        return root
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let boolean = value as? Bool {
            return boolean
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = stringValue(value) {
            switch string.lowercased() {
            case "1", "true", "yes", "available":
                return true
            case "0", "false", "no", "unavailable":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private func arrayValue(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    private func availabilityFlag(from payload: [String: Any]) -> Bool {
        if let explicitAvailability = boolValue(payload["isAvailable"]) {
            return explicitAvailability
        }

        if let availability = stringValue(payload["availability"]) {
            let normalized = availability.lowercased()
            if normalized.contains("unavailable") || normalized.contains("not available") {
                return false
            }
            if normalized.contains("available") {
                return true
            }
        }

        if let availabilityError = stringValue(payload["availabilityError"]) {
            return availabilityError.isEmpty
        }

        return true
    }

    private func availabilityDetails(from payload: [String: Any]) -> (isAvailable: Bool, issue: String?) {
        let isAvailable = availabilityFlag(from: payload)
        guard !isAvailable else {
            return (true, nil)
        }

        if let availabilityError = stringValue(payload["availabilityError"]), !availabilityError.isEmpty {
            return (false, availabilityError)
        }

        if let availability = stringValue(payload["availability"]), !availability.isEmpty {
            return (false, availability)
        }

        return (false, "Unavailable in CoreSimulator")
    }

    private func shortErrorMessage(from error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.replacingOccurrences(of: "\n", with: " ")
    }

    private func deviceDirectoryExists(forUDID udid: String) -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
            .appendingPathComponent(udid, isDirectory: true)
            .path
        return FileManager.default.fileExists(atPath: path)
    }

    private func writeLocaleToGlobalPreferencesFile(
        udid: String,
        locale: String,
        languageCode: String
    ) -> Bool {
        let fileManager = FileManager.default
        let preferencesURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
            .appendingPathComponent(udid, isDirectory: true)
            .appendingPathComponent("data/Library/Preferences/.GlobalPreferences.plist", isDirectory: false)

        do {
            try fileManager.createDirectory(
                at: preferencesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }

        var plist: [String: Any] = [:]
        if let existingData = fileManager.contents(atPath: preferencesURL.path),
           let plistObject = try? PropertyListSerialization.propertyList(from: existingData, options: [], format: nil),
           let dictionary = plistObject as? [String: Any] {
            plist = dictionary
        }

        plist["AppleLocale"] = locale
        plist["AppleLanguages"] = [languageCode]

        guard let updatedData = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        ) else {
            return false
        }

        do {
            try updatedData.write(to: preferencesURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func loadLastUsedDatesByUDID() -> [String: Date] {
        let fileManager = FileManager.default
        let devicesRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)

        guard let entries = try? fileManager.contentsOfDirectory(
            at: devicesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: Date] = [:]

        for entry in entries {
            guard ((try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) else {
                continue
            }

            let udid = entry.lastPathComponent
            guard UUID(uuidString: udid) != nil else {
                continue
            }

            let plistURL = entry.appendingPathComponent("device.plist", isDirectory: false)
            guard fileManager.fileExists(atPath: plistURL.path),
                  let plistData = fileManager.contents(atPath: plistURL.path),
                  let plistObject = try? PropertyListSerialization.propertyList(
                    from: plistData,
                    options: [],
                    format: nil
                  ),
                  let plistDictionary = plistObject as? [String: Any] else {
                continue
            }

            let lastUsedAt = simulatorLastUsedDate(from: plistDictionary)
                ?? (try? plistURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

            if let lastUsedAt {
                result[udid] = lastUsedAt
            }
        }

        return result
    }

    private func simulatorLastUsedDate(from plistDictionary: [String: Any]) -> Date? {
        for key in simulatorLastUsedKeys {
            guard let rawValue = plistDictionary[key] else {
                continue
            }
            if let parsedDate = parseDate(fromPlistValue: rawValue) {
                return parsedDate
            }
        }
        return nil
    }

    private func parseDate(fromPlistValue value: Any) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let stringValue = value as? String {
            let isoWithFraction = ISO8601DateFormatter()
            isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoWithFraction.date(from: stringValue) {
                return date
            }

            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]
            if let date = isoBasic.date(from: stringValue) {
                return date
            }
        }
        if let timestamp = value as? TimeInterval, timestamp > 0 {
            let seconds = timestamp > 4_102_444_800 ? (timestamp / 1_000) : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = value as? NSNumber {
            let timestamp = number.doubleValue
            guard timestamp > 0 else { return nil }
            let seconds = timestamp > 4_102_444_800 ? (timestamp / 1_000) : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private func uniqueRuntimes(_ runtimes: [SimulatorRuntime]) -> [SimulatorRuntime] {
        var seenIdentifiers = Set<String>()
        return runtimes.filter { runtime in
            seenIdentifiers.insert(runtime.identifier).inserted
        }
    }

    private func parseRuntimesFromPlainList(_ output: String) -> [SimulatorRuntime] {
        let parsedRuntimes = output
            .split(separator: "\n")
            .compactMap { line -> SimulatorRuntime? in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.contains("SimRuntime."),
                      let identifierStart = text.range(of: "com.apple.CoreSimulator.SimRuntime.") else {
                    return nil
                }

                let identifier = String(text[identifierStart.lowerBound...])
                    .split(separator: " ")
                    .first
                    .map(String.init) ?? ""
                guard !identifier.isEmpty else { return nil }

                let name = text.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? readableRuntimeName(from: identifier)
                let isAvailable = !text.localizedCaseInsensitiveContains("unavailable")

                return SimulatorRuntime(
                    identifier: identifier,
                    name: name,
                    version: nil,
                    isAvailable: isAvailable
                )
            }
        return uniqueRuntimes(parsedRuntimes)
            .filter(\.isAvailable)
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }
    }

    private func parseDeviceTypesFromPlainList(_ output: String) -> [SimulatorDeviceType] {
        var seenIdentifiers = Set<String>()

        return output
            .split(separator: "\n")
            .compactMap { line in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.contains("SimDeviceType."),
                      let identifierStart = text.range(of: "com.apple.CoreSimulator.SimDeviceType.") else {
                    return nil
                }

                let identifier = String(text[identifierStart.lowerBound...])
                    .split(separator: ")")
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard !identifier.isEmpty,
                      seenIdentifiers.insert(identifier).inserted else {
                    return nil
                }

                let name = text.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? readableDeviceTypeName(from: identifier)

                return SimulatorDeviceType(identifier: identifier, name: name)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

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
