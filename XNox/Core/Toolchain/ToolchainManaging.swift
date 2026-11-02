import Foundation

protocol ToolchainManaging: Sendable {
    func detectTools() async -> [ToolStatus]
}

struct LocalToolchainManager: ToolchainManaging {
    func detectTools() async -> [ToolStatus] {
        let tools = DevTool.allCases

        return await withTaskGroup(of: (Int, ToolStatus).self, returning: [ToolStatus].self) { group in
            for (index, tool) in tools.enumerated() {
                group.addTask {
                    (index, await status(for: tool))
                }
            }

            var orderedStatuses = Array<ToolStatus?>(repeating: nil, count: tools.count)
            for await (index, status) in group {
                orderedStatuses[index] = status
            }

            return orderedStatuses.compactMap { $0 }
        }
    }

    private func status(for tool: DevTool) async -> ToolStatus {
        let path = await resolveExecutable(named: tool.rawValue)
        let versionOutput: String?

        switch tool {
        case .fastlane:
            if let path {
                versionOutput = await commandOutput(
                    path,
                    ["--version"],
                    extraEnvironment: [
                        "FASTLANE_SKIP_UPDATE_CHECK": "1",
                        "FASTLANE_HIDE_TIMESTAMP": "1",
                    ],
                )
            } else {
                versionOutput = nil
            }
        }

        let parsedVersion = parseVersion(for: tool, from: versionOutput)
        let meetsMinimumVersion = parsedVersion.map {
            isVersion($0, greaterThanOrEqualTo: minimumVersion(for: tool))
        } ?? false
        let installMethod = installMethod(for: path)
        let installedBrewFormula = await installedHomebrewFormula(for: tool, installMethod: installMethod)
        let latestAvailableVersion = await latestVersion(for: tool, installMethod: installMethod)
        let isUpdateAvailable = latestAvailableVersion.map { latest in
            guard let parsedVersion else { return false }
            return isVersion(latest, greaterThan: parsedVersion)
        } ?? false
        let updateCommand = updateCommand(
            for: tool,
            installMethod: installMethod,
            installedBrewFormula: installedBrewFormula,
            isUpdateAvailable: isUpdateAvailable
        )

        return ToolStatus(
            tool: tool,
            path: path,
            version: parsedVersion,
            meetsMinimumVersion: meetsMinimumVersion,
            latestAvailableVersion: latestAvailableVersion,
            updateCommand: updateCommand,
            isUpdateAvailable: isUpdateAvailable,
            installMethod: installMethod,
            note: note(
                for: tool,
                path: path,
                parsedVersion: parsedVersion,
                latestAvailableVersion: latestAvailableVersion,
                installMethod: installMethod,
                installedBrewFormula: installedBrewFormula
            )
        )
    }

    private func resolveExecutable(named executableName: String) async -> String? {
        let searchPath = executableSearchPaths().joined(separator: ":")

        if let whichResult = await commandOutput(
            "/usr/bin/which",
            [executableName],
            extraEnvironment: ["PATH": searchPath]
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !whichResult.isEmpty {
            return whichResult
        }

        for directory in executableSearchPaths() {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executableName).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func executableSearchPaths() -> [String] {
        let processEnvironment = ProcessInfo.processInfo.environment
        var paths = processEnvironment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let home = NSHomeDirectory()

        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(home)/.rbenv/shims",
            "\(home)/.asdf/shims",
            "\(home)/.mint/bin",
        ])

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private func commandOutput(
        _ launchPath: String,
        _ arguments: [String],
        extraEnvironment: [String: String] = [:]
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.environment = mergedEnvironment(extraEnvironment)

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { finishedProcess in
                guard finishedProcess.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                let stdoutText = String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !stdoutText.isEmpty && !stderrText.isEmpty {
                    continuation.resume(returning: "\(stdoutText)\n\(stderrText)")
                    return
                }
                if !stdoutText.isEmpty {
                    continuation.resume(returning: stdoutText)
                    return
                }
                if !stderrText.isEmpty {
                    continuation.resume(returning: stderrText)
                    return
                }

                continuation.resume(returning: nil)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func parseVersion(for tool: DevTool, from output: String?) -> String? {
        guard let output else { return nil }

        let pattern = #"\b\d+\.\d+(?:\.\d+)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, options: [], range: nsRange).compactMap { match -> String? in
            guard let range = Range(match.range, in: output) else { return nil }
            return String(output[range])
        }

        if matches.isEmpty {
            return nil
        }

        switch tool {
        case .fastlane:
            return matches.last
        }
    }

    private func mergedEnvironment(_ extraEnvironment: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executableSearchPaths().joined(separator: ":")
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        return environment
    }

    private func minimumVersion(for tool: DevTool) -> String {
        switch tool {
        case .fastlane:
            return "2.232.0"
        }
    }

    private func isVersion(_ lhs: String, greaterThanOrEqualTo rhs: String) -> Bool {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0

            if leftValue > rightValue { return true }
            if leftValue < rightValue { return false }
        }

        return true
    }

    private func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0

            if leftValue > rightValue { return true }
            if leftValue < rightValue { return false }
        }

        return false
    }

    private func installMethod(for path: String?) -> ToolInstallMethod {
        guard let path else { return .unknown }
        if path.contains("/.rbenv/shims/") || path.contains("/.asdf/shims/") || path.contains("/rbenv/shims/") || path.contains("/asdf/shims/") {
            return .bundler
        }
        if path.contains("/opt/homebrew/") || path.contains("/usr/local/Cellar/") || path.contains("/Homebrew/") {
            return .homebrew
        }
        if path.contains("/gems/") || path.contains("/bundle/") {
            return .gem
        }
        return .unknown
    }

    private func latestVersion(for tool: DevTool, installMethod: ToolInstallMethod) async -> String? {
        switch installMethod {
        case .homebrew:
            return await latestHomebrewVersion(for: tool)
        case .bundler:
            return await latestRemoteGemVersion(for: tool)
        case .gem:
            return await latestRemoteGemVersion(for: tool)
        case .unknown:
            return nil
        }
    }

    private func installedHomebrewFormula(for tool: DevTool, installMethod: ToolInstallMethod) async -> String? {
        guard installMethod == .homebrew else { return nil }
        guard let output = await commandOutput("/usr/bin/env", ["brew", "list", "--formula", "--versions"]) else {
            return nil
        }
        let brewFormulaName = tool.brewFormulaName

        let lines = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var matches: [String] = []
        for line in lines {
            let parts = line.split(separator: " ").map(String.init)
            guard let name = parts.first else { continue }
            if name == brewFormulaName || name.hasPrefix(brewFormulaName + "@") {
                matches.append(name)
            }
        }

        // Prefer exact formula match when present.
        if let exact = matches.first(where: { $0 == brewFormulaName }) {
            return exact
        }
        return matches.first
    }

    private func latestHomebrewVersion(for tool: DevTool) async -> String? {
        guard await resolveExecutable(named: "brew") != nil else { return nil }
        let brewFormulaName = tool.brewFormulaName

        if let output = await commandOutput("/usr/bin/env", ["brew", "outdated", tool.brewFormulaName]) {
            let lines = output
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            for line in lines {
                if line.hasPrefix(brewFormulaName + " "),
                   let version = parseHomebrewLatestVersion(from: line) {
                    return version
                }
            }
        }

        // Fallback for pinned or tap-specific installs.
        return await latestHomebrewStableVersion(for: tool)
    }

    private func parseHomebrewLatestVersion(from line: String) -> String? {
        // Example output: fastlane 2.228.0 < 2.229.0
        guard let range = line.range(of: "<") else { return nil }
        let rhs = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\d+\.\d+(?:\.\d+)?$"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(rhs.startIndex..<rhs.endIndex, in: rhs)
        guard regex.firstMatch(in: rhs, options: [], range: nsRange) != nil else {
            return nil
        }

        return rhs
    }

    private func latestHomebrewStableVersion(for tool: DevTool) async -> String? {
        guard let output = await commandOutput("/usr/bin/env", ["brew", "info", "--json=v2", tool.brewInfoIdentifier]),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]],
              let first = formulae.first,
              let versions = first["versions"] as? [String: Any],
              let stable = versions["stable"] as? String else {
            return nil
        }

        let pattern = #"^\d+\.\d+(?:\.\d+)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(stable.startIndex..<stable.endIndex, in: stable)
        guard regex.firstMatch(in: stable, options: [], range: nsRange) != nil else {
            return nil
        }

        return stable
    }

    private func latestRemoteGemVersion(for tool: DevTool) async -> String? {
        guard tool == .fastlane else { return nil }
        guard await resolveExecutable(named: "gem") != nil else { return nil }
        guard let output = await commandOutput(
            "/usr/bin/env",
            ["gem", "list", "^\(tool.rawValue)$", "--remote", "--all"],
        ) else {
            return nil
        }

        // Example output: fastlane (2.232.2, 2.232.1, ...)
        let lines = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let fastlaneLine = lines.first(where: { $0.hasPrefix(tool.rawValue + " (") }) else {
            return nil
        }

        let pattern = #"^[a-zA-Z0-9_-]+\s+\(([^)]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(fastlaneLine.startIndex..<fastlaneLine.endIndex, in: fastlaneLine)
        guard let match = regex.firstMatch(in: fastlaneLine, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let versionsRange = Range(match.range(at: 1), in: fastlaneLine) else {
            return nil
        }

        let versions = fastlaneLine[versionsRange]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let versionPattern = #"^\d+\.\d+(?:\.\d+)?$"#
        guard let versionRegex = try? NSRegularExpression(pattern: versionPattern) else {
            return nil
        }

        for candidate in versions {
            let candidateRange = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            if versionRegex.firstMatch(in: candidate, options: [], range: candidateRange) != nil {
                return candidate
            }
        }

        return nil
    }

    private func updateCommand(
        for tool: DevTool,
        installMethod: ToolInstallMethod,
        installedBrewFormula: String?,
        isUpdateAvailable: Bool
    ) -> String? {
        guard isUpdateAvailable else { return nil }

        switch installMethod {
        case .homebrew:
            return tool.updateCommand
        case .bundler:
            return "bundle update \(tool.rawValue)"
        case .gem:
            return "gem update \(tool.rawValue)"
        case .unknown:
            return nil
        }
    }

    private func note(
        for tool: DevTool,
        path: String?,
        parsedVersion: String?,
        latestAvailableVersion: String?,
        installMethod: ToolInstallMethod,
        installedBrewFormula: String?
    ) -> String? {
        guard let path else {
            return "\(tool.rawValue) not found. Checked PATH plus common locations (/opt/homebrew/bin, /usr/local/bin, ~/.rbenv/shims)."
        }

        if parsedVersion == nil {
            return "Found at \(path), but unable to parse version output."
        }

        if installMethod == .bundler, tool == .fastlane {
            if let latestAvailableVersion, let parsedVersion, isVersion(latestAvailableVersion, greaterThan: parsedVersion) {
                return "Bundler-managed fastlane. New gem version detected (\(parsedVersion) -> \(latestAvailableVersion)). Run bundle update fastlane in your project."
            }
            return nil
        }

        if installMethod == .unknown {
            return "Installed from an unmanaged path. Update checks are automatic for Homebrew, Bundler-shim, and gem installs."
        }

        if let latestAvailableVersion, let parsedVersion, isVersion(latestAvailableVersion, greaterThan: parsedVersion) {
            return "Update available: \(parsedVersion) -> \(latestAvailableVersion)"
        }

        return nil
    }
}
