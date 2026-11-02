import Foundation

/// Runs `xcrun simctl` commands and reads CoreSimulator state off the main thread.
actor SimulatorControlService {
    private let runner: any CommandRunning
    /// Base delay between erase retries; attempt N waits N times this (capped at 4s). Tests pass 0.
    private let eraseBackoffMicroseconds: Int
    /// CoreSimulator `Devices` directory. Tests point this at a temp dir.
    private let devicesDirectory: URL

    init(
        runner: any CommandRunning = ProcessCommandRunner(),
        eraseBackoffMicroseconds: Int = 500_000,
        devicesDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
    ) {
        self.runner = runner
        self.eraseBackoffMicroseconds = eraseBackoffMicroseconds
        self.devicesDirectory = devicesDirectory
    }

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
        try Self.validateUDID(udid)
        do {
            _ = try runSimctl(["boot", udid], timeoutSeconds: 90)
        } catch let error as CommandError {
            if case let .failed(_, message) = error,
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
        try Self.validateUDID(udid)
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
                    let backoffMicroseconds = useconds_t(min(4_000_000, eraseBackoffMicroseconds * attempt))
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
        try Self.validateUDID(udid)
        _ = try? runSimctl(["shutdown", udid], timeoutSeconds: 90)
        _ = try runSimctl(["delete", udid], timeoutSeconds: 120)
    }

    func renameSimulator(udid: String, name: String) throws {
        try Self.validateUDID(udid)
        _ = try runSimctl(["rename", udid, name], timeoutSeconds: 60)
    }

    func setLocale(udid: String, localeIdentifier: String) throws {
        try Self.validateUDID(udid)
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
        try Self.validateUDID(udid)
        _ = try runSimctl(["openurl", udid, rawURL])
    }

    func addMedia(udid: String, filePaths: [String]) throws -> Int {
        try Self.validateUDID(udid)
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
        try Self.validateUDID(udid)
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
        try Self.validateUDID(udid)
        _ = try runSimctl(["status_bar", udid, "clear"])
    }

    private func fetchRuntimes() throws -> [SimulatorRuntime] {
        let output = try runSimctl(["list", "runtimes", "--json"])
        let root = try SimctlParser.parseRootJSONDictionary(from: output, label: "runtimes")
        let runtimesAny = SimctlParser.arrayValue(root["runtimes"]) ?? []

        let parsedRuntimes: [SimulatorRuntime] = runtimesAny.compactMap { runtimeAny in
            guard let runtime = SimctlParser.dictionaryValue(runtimeAny) else { return nil }
            guard let identifier = SimctlParser.stringValue(runtime["identifier"]), !identifier.isEmpty else {
                return nil
            }

            let name = SimctlParser.stringValue(runtime["name"]) ?? SimctlParser.readableRuntimeName(from: identifier)
            let version = SimctlParser.stringValue(runtime["version"])
            let isAvailable = SimctlParser.availabilityFlag(from: runtime)

            return SimulatorRuntime(
                identifier: identifier,
                name: name,
                version: version,
                isAvailable: isAvailable
            )
        }
        let uniqueParsedRuntimes = SimctlParser.uniqueRuntimes(parsedRuntimes)
            .filter(\.isAvailable)
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }

        if !uniqueParsedRuntimes.isEmpty {
            return uniqueParsedRuntimes
        }

        let fallbackOutput = try runSimctl(["list", "runtimes"])
        return SimctlParser.uniqueRuntimes(SimctlParser.parseRuntimesFromPlainList(fallbackOutput))
    }

    private func fetchDeviceTypes() throws -> [SimulatorDeviceType] {
        let output = try runSimctl(["list", "devicetypes", "--json"])
        let root = try SimctlParser.parseRootJSONDictionary(from: output, label: "device types")

        let rawTypes: [Any] = {
            if let deviceTypes = SimctlParser.arrayValue(root["devicetypes"]) {
                return deviceTypes
            }
            if let deviceTypes = SimctlParser.arrayValue(root["deviceTypes"]) {
                return deviceTypes
            }
            return []
        }()

        var seenIdentifiers = Set<String>()
        let types = rawTypes.compactMap { typeAny -> SimulatorDeviceType? in
            guard let type = SimctlParser.dictionaryValue(typeAny) else { return nil }
            guard let identifier = SimctlParser.stringValue(type["identifier"]), !identifier.isEmpty else {
                return nil
            }

            guard seenIdentifiers.insert(identifier).inserted else {
                return nil
            }

            let name = SimctlParser.stringValue(type["name"]) ?? SimctlParser.readableDeviceTypeName(from: identifier)
            return SimulatorDeviceType(identifier: identifier, name: name)
        }

        let sortedTypes = types.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        if !sortedTypes.isEmpty {
            return sortedTypes
        }

        let fallbackOutput = try runSimctl(["list", "devicetypes"])
        return SimctlParser.parseDeviceTypesFromPlainList(fallbackOutput)
    }

    /// Rejects anything that is not a UUID before it reaches `simctl`, so a malformed
    /// value can never be interpreted as an option or a device specifier like `all`.
    static func validateUDID(_ udid: String) throws {
        guard UUID(uuidString: udid) != nil else {
            throw SimulatorControlError.invalidInput("Invalid simulator identifier: \(udid)")
        }
    }

    private func runSimctl(_ arguments: [String], timeoutSeconds: TimeInterval = 20) throws -> String {
        try runner.run("/usr/bin/xcrun", ["simctl"] + arguments, timeout: timeoutSeconds)
    }

    private func fetchSimulators(
        runtimeByIdentifier: [String: SimulatorRuntime]
    ) throws -> [SimulatorDevice] {
        let devicesOutput = try runSimctl(["list", "devices", "--json"])
        let root = try SimctlParser.parseRootJSONDictionary(from: devicesOutput, label: "devices")
        let devicesRoot = SimctlParser.dictionaryValue(root["devices"]) ?? [:]
        let lastUsedByUDID = loadLastUsedDatesByUDID()

        return devicesRoot.flatMap { runtimeIdentifier, runtimeDevicesAny in
            let runtimeDevices = SimctlParser.arrayValue(runtimeDevicesAny) ?? []
            return runtimeDevices.compactMap { rawDeviceAny -> SimulatorDevice? in
                guard let rawDevice = SimctlParser.dictionaryValue(rawDeviceAny) else { return nil }
                guard let name = SimctlParser.stringValue(rawDevice["name"]),
                      !name.isEmpty,
                      let udid = SimctlParser.stringValue(rawDevice["udid"]),
                      !udid.isEmpty else {
                    return nil
                }

                let runtimeName = runtimeByIdentifier[runtimeIdentifier]?.name ?? SimctlParser.readableRuntimeName(from: runtimeIdentifier)
                let state = SimctlParser.stringValue(rawDevice["state"]) ?? "Unknown"
                let availability = SimctlParser.availabilityDetails(from: rawDevice)
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
                    deviceTypeIdentifier: SimctlParser.stringValue(rawDevice["deviceTypeIdentifier"]) ?? "",
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

    private func launchSimulatorApp(forUDID udid: String) {
        // Best-effort only: boot success should not fail if Simulator.app launch is blocked.
        _ = try? runner.run(
            "/usr/bin/open",
            ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid],
            timeout: 10
        )
    }

    private func shortErrorMessage(from error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.replacingOccurrences(of: "\n", with: " ")
    }

    private func deviceDirectoryExists(forUDID udid: String) -> Bool {
        let path = devicesDirectory
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
        let preferencesURL = devicesDirectory
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
        let devicesRoot = devicesDirectory

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

            let lastUsedAt = SimctlParser.simulatorLastUsedDate(from: plistDictionary)
                ?? (try? plistURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

            if let lastUsedAt {
                result[udid] = lastUsedAt
            }
        }

        return result
    }

}
