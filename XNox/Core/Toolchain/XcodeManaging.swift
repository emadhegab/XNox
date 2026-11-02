import Foundation
import Darwin
import Security

struct XcodeInstallation: Identifiable, Sendable {
    let id: UUID
    let version: String
    let path: String
    let isSelected: Bool

    init(id: UUID = UUID(), version: String, path: String, isSelected: Bool) {
        self.id = id
        self.version = version
        self.path = path
        self.isSelected = isSelected
    }
}

struct XcodeRelease: Identifiable, Sendable {
    let id: UUID
    let version: String
    let isPrerelease: Bool
    let isInstalled: Bool
    let isSelected: Bool

    init(
        id: UUID = UUID(),
        version: String,
        isPrerelease: Bool,
        isInstalled: Bool = false,
        isSelected: Bool = false
    ) {
        self.id = id
        self.version = version
        self.isPrerelease = isPrerelease
        self.isInstalled = isInstalled
        self.isSelected = isSelected
    }
}

protocol XcodeManaging {
    func installedXcodes() async throws -> [XcodeInstallation]
    func availableXcodes() async throws -> [XcodeRelease]
    func installWithProgress(
        version: String,
        selectAfterInstall: Bool,
        requiresAdministratorPrivileges: Bool
    ) throws -> AsyncThrowingStream<String, Error>
    func sendInstallInput(_ input: String) throws
    func cancelInstall()
    func signOut() async throws
    func install(version: String, selectAfterInstall: Bool) async throws
    func select(versionOrPath: String) async throws
    func uninstall(version: String, emptyTrash: Bool) async throws
}

enum XcodeManagerError: LocalizedError {
    case executableNotFound
    case commandFailed(command: String, output: String)
    case parseFailure(command: String)
    case noActiveInstallSession

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Could not find the xcodes executable in PATH."
        case let .commandFailed(command, output):
            return "Command failed: \(command)\n\(output)"
        case let .parseFailure(command):
            return "Command succeeded but returned unparseable output: \(command)"
        case .noActiveInstallSession:
            return "No active install is waiting for input."
        }
    }
}

enum XcodeVersionOrdering {
    static func isPrerelease(_ version: String) -> Bool {
        let lowered = version.lowercased()
        return lowered.contains("beta")
            || lowered.contains("rc")
            || lowered.contains("release candidate")
            || lowered.contains("gm")
    }

    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = parse(version: lhs)
        let right = parse(version: rhs)

        let maxComponentCount = max(left.numericComponents.count, right.numericComponents.count)
        for index in 0..<maxComponentCount {
            let leftValue = index < left.numericComponents.count ? left.numericComponents[index] : 0
            let rightValue = index < right.numericComponents.count ? right.numericComponents[index] : 0
            if leftValue != rightValue {
                return leftValue > rightValue
            }
        }

        if left.channelRank != right.channelRank {
            return left.channelRank > right.channelRank
        }

        if left.channelNumber != right.channelNumber {
            return left.channelNumber > right.channelNumber
        }

        return lhs.localizedStandardCompare(rhs) == .orderedDescending
    }

    private struct VersionSortKey {
        let numericComponents: [Int]
        let channelRank: Int
        let channelNumber: Int
    }

    private static func parse(version: String) -> VersionSortKey {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        let numericPrefix = firstMatch(
            pattern: #"^\d+(?:\.\d+)*"#,
            in: trimmed
        ) ?? ""
        let numericComponents = numericPrefix
            .split(separator: ".")
            .compactMap { Int($0) }

        let channelRank: Int
        if lowercased.contains("beta") {
            channelRank = 0
        } else if lowercased.contains("rc") || lowercased.contains("release candidate") {
            channelRank = 1
        } else if lowercased.contains("gm") {
            channelRank = 2
        } else {
            channelRank = 3
        }

        let channelNumber: Int
        if let betaNumber = firstMatch(pattern: #"beta\s*(\d+)"#, in: lowercased, captureGroup: 1),
           let value = Int(betaNumber) {
            channelNumber = value
        } else if let rcNumber = firstMatch(pattern: #"release\s+candidate\s*(\d+)"#, in: lowercased, captureGroup: 1),
                  let value = Int(rcNumber) {
            channelNumber = value
        } else if let rcNumber = firstMatch(pattern: #"rc\s*(\d+)"#, in: lowercased, captureGroup: 1),
                  let value = Int(rcNumber) {
            channelNumber = value
        } else if let gmNumber = firstMatch(pattern: #"gm(?:\s*seed)?\s*(\d+)"#, in: lowercased, captureGroup: 1),
                  let value = Int(gmNumber) {
            channelNumber = value
        } else {
            channelNumber = 0
        }

        return VersionSortKey(
            numericComponents: numericComponents,
            channelRank: channelRank,
            channelNumber: channelNumber
        )
    }

    private static func firstMatch(pattern: String, in input: String, captureGroup: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: nsRange),
              match.numberOfRanges > captureGroup,
              let range = Range(match.range(at: captureGroup), in: input) else {
            return nil
        }

        return String(input[range])
    }
}

enum XcodesOutputParser {
    static func parseInstalled(_ output: String) -> [XcodeInstallation] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseInstalledLine(String($0)) }
            .sorted { XcodeVersionOrdering.isNewer($0.version, than: $1.version) }
    }

    static func parseAvailable(_ output: String) -> [XcodeRelease] {
        var byVersion: [String: XcodeRelease] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let version = parseVersion(from: line) else { continue }
            let normalizedLine = line.lowercased()

            let isSelected = normalizedLine.contains("(selected)")
                || normalizedLine.contains(" selected")
                || line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("*")
            let isInstalled = normalizedLine.contains("(installed)")
                || normalizedLine.contains(" installed")
                || isSelected

            let existing = byVersion[version]
            byVersion[version] = XcodeRelease(
                version: version,
                isPrerelease: XcodeVersionOrdering.isPrerelease(version),
                isInstalled: (existing?.isInstalled ?? false) || isInstalled,
                isSelected: (existing?.isSelected ?? false) || isSelected
            )
        }

        return byVersion.values.sorted {
            XcodeVersionOrdering.isNewer($0.version, than: $1.version)
        }
    }

    static func mergedAvailableReleases(
        available: [XcodeRelease],
        installed: [XcodeInstallation]
    ) -> [XcodeRelease] {
        var byVersion: [String: XcodeRelease] = [:]

        for release in available {
            byVersion[release.version] = release
        }

        for installation in installed {
            let existing = byVersion[installation.version]
            byVersion[installation.version] = XcodeRelease(
                version: installation.version,
                isPrerelease: existing?.isPrerelease ?? XcodeVersionOrdering.isPrerelease(installation.version),
                isInstalled: true,
                isSelected: (existing?.isSelected ?? false) || installation.isSelected
            )
        }

        return byVersion.values.sorted {
            XcodeVersionOrdering.isNewer($0.version, than: $1.version)
        }
    }

    private static func parseInstalledLine(_ line: String) -> XcodeInstallation? {
        guard let version = parseVersion(from: line) else { return nil }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        let isSelected = normalized.contains("(selected)") || normalized.contains(" selected") || trimmed.hasPrefix("*")

        let path = parsePath(fromInstalledLine: line) ?? "/Applications/Xcode-\(version).app"

        return XcodeInstallation(version: version, path: path, isSelected: isSelected)
    }

    private static func parsePath(fromInstalledLine line: String) -> String? {
        if let tabIndex = line.firstIndex(of: "\t") {
            let value = line[line.index(after: tabIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        guard let slashIndex = line.firstIndex(of: "/") else { return nil }
        let value = line[slashIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func parseVersion(from line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        while let first = trimmed.first,
              first == "*" || first == "-" || first == "•" || first == ">" || first == "✓" || first == "✔" || first == "☑" {
            trimmed.removeFirst()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmed.hasPrefix("->") {
            trimmed.removeFirst(2)
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let tabIndex = trimmed.firstIndex(of: "\t") {
            trimmed = String(trimmed[..<tabIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let parenIndex = trimmed.firstIndex(of: "(") {
            trimmed = String(trimmed[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else { return nil }

        let pattern = #"^\d+(?:\.\d+)*(?:\s+(?:beta|rc|release\s+candidate|gm(?:\s+seed)?)(?:\s+\d+)?)?$"#
        guard trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }

        return trimmed
    }
}

final class XcodesCLIService: XcodeManaging {
    private let fileManager: FileManager
    private let processEnvironment: [String: String]
    private let blockingCommandQueue = DispatchQueue(label: "app.hegab.XNox.xcodes.blocking", qos: .userInitiated)
    private let installIOQueue = DispatchQueue(label: "app.hegab.XNox.xcodes.install.io")
    private var activeInstallInputHandle: FileHandle?
    private var activeInstallProcess: Process?
    private var activeInstallWorker: Task<Void, Never>?
    private var installCancellationRequested = false

    init(
        fileManager: FileManager = .default,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.processEnvironment = processEnvironment
    }

    func installWithProgress(
        version: String,
        selectAfterInstall: Bool,
        requiresAdministratorPrivileges: Bool
    ) throws -> AsyncThrowingStream<String, Error> {
        if requiresAdministratorPrivileges {
            return try runInstallWithNativePrivileges(
                version: version,
                selectAfterInstall: selectAfterInstall
            )
        }

        var arguments = ["install", version, "--no-color"]
        if selectAfterInstall {
            arguments.append("--select")
        }
        return try runXcodesStreaming(arguments: arguments)
    }

    func sendInstallInput(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }

        let payload = "\(trimmed)\n"
        let data = Data(payload.utf8)
        var handle: FileHandle?

        installIOQueue.sync {
            handle = activeInstallInputHandle
        }

        guard let handle else {
            throw XcodeManagerError.noActiveInstallSession
        }

        handle.writeabilityHandler = nil
        try handle.write(contentsOf: data)
    }

    func cancelInstall() {
        var process: Process?
        var worker: Task<Void, Never>?
        var inputHandle: FileHandle?

        installIOQueue.sync {
            installCancellationRequested = true
            process = activeInstallProcess
            worker = activeInstallWorker
            inputHandle = activeInstallInputHandle
            activeInstallInputHandle = nil
            activeInstallProcess = nil
            activeInstallWorker = nil
        }

        worker?.cancel()
        try? inputHandle?.close()

        if let process, process.isRunning {
            terminateDescendants(of: process.processIdentifier, signal: SIGTERM)
            process.terminate()

            let timeout = Date().addingTimeInterval(1.5)
            while process.isRunning && Date() < timeout {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }

            terminateDescendants(of: process.processIdentifier, signal: SIGKILL)
        }
    }

    func signOut() async throws {
        _ = try await runXcodesAsync(arguments: ["signout", "--no-color"])
    }

    func installedXcodes() async throws -> [XcodeInstallation] {
        let output = try await runXcodesAsync(arguments: ["installed", "--no-color"])
        return XcodesOutputParser.parseInstalled(output)
    }

    func availableXcodes() async throws -> [XcodeRelease] {
        let output = try await runXcodesAsync(arguments: ["list", "--no-color"])
        let releases = XcodesOutputParser.parseAvailable(output)

        guard !releases.isEmpty else {
            throw XcodeManagerError.parseFailure(command: "xcodes list --no-color")
        }

        return releases
    }

    func install(version: String, selectAfterInstall: Bool) async throws {
        let stream = try installWithProgress(
            version: version,
            selectAfterInstall: selectAfterInstall,
            requiresAdministratorPrivileges: true
        )
        for try await _ in stream {
        }
    }

    func select(versionOrPath: String) async throws {
        try await runBlockingCommand {
            let selectedPath = try self.resolveInstalledXcodePath(for: versionOrPath)
            let developerDirectory = "\(selectedPath)/Contents/Developer"
            let command = "/usr/bin/xcode-select -s \(Self.shellQuoted(developerDirectory))"
            _ = try self.runShellCommandWithAdministratorPrivileges(command)
        }
    }

    func uninstall(version: String, emptyTrash: Bool) async throws {
        var arguments = ["uninstall", version, "--no-color"]
        if emptyTrash {
            arguments.append("--empty-trash")
        }
        _ = try await runXcodesAsync(arguments: arguments)
    }

    private func runXcodes(arguments: [String]) throws -> String {
        let executablePath = try resolveXcodesExecutable()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = mergedEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw XcodeManagerError.commandFailed(
                command: commandLine(arguments),
                output: error.localizedDescription
            )
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let output = stderr.isEmpty ? stdout : stderr
            throw XcodeManagerError.commandFailed(command: commandLine(arguments), output: output)
        }

        if !stdout.isEmpty && !stderr.isEmpty {
            return "\(stdout)\n\(stderr)"
        }

        return stdout.isEmpty ? stderr : stdout
    }

    private func runXcodesAsync(arguments: [String]) async throws -> String {
        let executablePath = try resolveXcodesExecutable()
        let command = commandLine(arguments)
        let baseEnvironment = mergedEnvironment()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.environment = baseEnvironment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { completedProcess in
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if completedProcess.terminationStatus == 0 {
                    if !stdout.isEmpty && !stderr.isEmpty {
                        continuation.resume(returning: "\(stdout)\n\(stderr)")
                    } else {
                        continuation.resume(returning: stdout.isEmpty ? stderr : stdout)
                    }
                    return
                }

                let output = stderr.isEmpty ? stdout : stderr
                continuation.resume(
                    throwing: XcodeManagerError.commandFailed(command: command, output: output)
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    throwing: XcodeManagerError.commandFailed(
                        command: command,
                        output: error.localizedDescription
                    )
                )
            }
        }
    }

    private func runBlockingCommand<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            blockingCommandQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func resolveInstalledXcodePath(for versionOrPath: String) throws -> String {
        if versionOrPath.hasPrefix("/") {
            guard fileManager.fileExists(atPath: versionOrPath) else {
                throw XcodeManagerError.commandFailed(
                    command: "xcode-select -s \(versionOrPath)",
                    output: "Xcode path does not exist: \(versionOrPath)"
                )
            }
            return versionOrPath
        }

        let installedOutput = try runXcodes(arguments: ["installed", "--no-color"])
        let installations = XcodesOutputParser.parseInstalled(installedOutput)

        if let exactMatch = installations.first(where: { $0.version == versionOrPath }),
           fileManager.fileExists(atPath: exactMatch.path) {
            return exactMatch.path
        }

        let normalizedTarget = versionOrPath
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        if let normalizedMatch = installations.first(where: {
            $0.version.lowercased().replacingOccurrences(of: " ", with: "") == normalizedTarget
        }),
           fileManager.fileExists(atPath: normalizedMatch.path) {
            return normalizedMatch.path
        }

        throw XcodeManagerError.commandFailed(
            command: "xcodes installed --no-color",
            output: "Could not resolve installed path for Xcode \(versionOrPath)."
        )
    }

    private func runXcodesStreaming(
        arguments: [String]
    ) throws -> AsyncThrowingStream<String, Error> {
        let xcodesExecutablePath = try resolveXcodesExecutable()
        let command = commandLine(arguments)
        let baseEnvironment = mergedEnvironment()

        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: xcodesExecutablePath)
            process.arguments = arguments
            process.environment = baseEnvironment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            let coordinationQueue = DispatchQueue(label: "app.hegab.XNox.xcodes.install.stream")
            var stdoutBuffer = Data()
            var stderrBuffer = Data()
            var combinedOutput: [String] = []
            var didFinish = false

            installIOQueue.sync {
                installCancellationRequested = false
                activeInstallInputHandle = stdinPipe.fileHandleForWriting
                activeInstallProcess = process
            }

            @Sendable func yieldParsedLines(from data: Data, isError: Bool) {
                coordinationQueue.async {
                    guard !didFinish else { return }

                    if isError {
                        stderrBuffer.append(data)
                    } else {
                        stdoutBuffer.append(data)
                    }

                    let lines = isError
                        ? Self.extractLines(from: &stderrBuffer, flushRemainder: false)
                        : Self.extractLines(from: &stdoutBuffer, flushRemainder: false)

                    for rawLine in lines {
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }
                        combinedOutput.append(line)
                        continuation.yield(line)
                    }

                    if lines.isEmpty {
                        let partial = isError
                            ? String(decoding: stderrBuffer, as: UTF8.self)
                            : String(decoding: stdoutBuffer, as: UTF8.self)
                        let cleanedPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                        let loweredPartial = cleanedPartial.lowercased()

                        if cleanedPartial.count >= 6
                            || cleanedPartial.hasSuffix(":")
                            || loweredPartial.contains("apple id")
                            || loweredPartial.contains("password")
                            || loweredPartial.contains("verification")
                            || loweredPartial.contains("2fa")
                            || loweredPartial.contains("two-factor") {
                            combinedOutput.append(cleanedPartial)
                            continuation.yield(cleanedPartial)

                            if isError {
                                stderrBuffer.removeAll(keepingCapacity: true)
                            } else {
                                stdoutBuffer.removeAll(keepingCapacity: true)
                            }
                        }
                    }
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                yieldParsedLines(from: data, isError: false)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                yieldParsedLines(from: data, isError: true)
            }

            process.terminationHandler = { completedProcess in
                coordinationQueue.async {
                    guard !didFinish else { return }

                    let remainingStdout = Self.extractLines(from: &stdoutBuffer, flushRemainder: true)
                    let remainingStderr = Self.extractLines(from: &stderrBuffer, flushRemainder: true)
                    for rawLine in remainingStdout + remainingStderr {
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }
                        combinedOutput.append(line)
                        continuation.yield(line)
                    }

                    didFinish = true
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    var wasCancelled = false
                    self.installIOQueue.sync {
                        wasCancelled = self.installCancellationRequested
                        self.installCancellationRequested = false
                        self.activeInstallInputHandle = nil
                        self.activeInstallProcess = nil
                    }
                    try? stdinPipe.fileHandleForWriting.close()

                    if wasCancelled {
                        continuation.finish(throwing: CancellationError())
                    } else if completedProcess.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        let output = combinedOutput.isEmpty
                            ? "Unknown error."
                            : combinedOutput.joined(separator: "\n")
                        continuation.finish(
                            throwing: XcodeManagerError.commandFailed(command: command, output: output)
                        )
                    }
                }
            }

            continuation.onTermination = { _ in
                coordinationQueue.async {
                    guard !didFinish else { return }
                    didFinish = true
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    self.installIOQueue.sync {
                        self.installCancellationRequested = false
                        self.activeInstallInputHandle = nil
                        self.activeInstallProcess = nil
                    }
                    try? stdinPipe.fileHandleForWriting.close()
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                installIOQueue.sync {
                    installCancellationRequested = false
                    activeInstallInputHandle = nil
                    activeInstallProcess = nil
                }
                try? stdinPipe.fileHandleForWriting.close()
                continuation.finish(
                    throwing: XcodeManagerError.commandFailed(
                        command: command,
                        output: error.localizedDescription
                    )
                )
            }
        }
    }

    private func runInstallWithNativePrivileges(
        version: String,
        selectAfterInstall: Bool
    ) throws -> AsyncThrowingStream<String, Error> {
        let userInstallDirectory = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/XNox/XcodeStaging")
        let userInstallURL = URL(fileURLWithPath: userInstallDirectory, isDirectory: true)
        try fileManager.createDirectory(at: userInstallURL, withIntermediateDirectories: true)

        let arguments = [
            "install",
            version,
            "--no-color",
            "--no-superuser",
            "--directory",
            userInstallDirectory,
        ]

        return AsyncThrowingStream { continuation in
            let worker = Task {
                defer {
                    self.installIOQueue.sync {
                        self.activeInstallWorker = nil
                    }
                }
                self.installIOQueue.sync {
                    self.installCancellationRequested = false
                }
                do {
                    continuation.yield("Installing Xcode into a temporary staging folder first.")
                    continuation.yield("Staging location: \(userInstallDirectory)")
                    continuation.yield("A native macOS authorization prompt will appear before moving into /Applications.")

                    var movedPathFromTool: String?
                    let stream = try self.runXcodesStreaming(arguments: arguments)
                    for try await line in stream {
                        if let parsedPath = Self.parseMoveTargetPath(from: line),
                           parsedPath.hasPrefix(userInstallDirectory) {
                            movedPathFromTool = parsedPath
                        }
                        continuation.yield(line)
                    }

                    let sourcePath = try self.resolveInstalledPath(
                        version: version,
                        preferredPath: movedPathFromTool,
                        userInstallDirectory: userInstallDirectory
                    )
                    let destinationPath = "/Applications/\((sourcePath as NSString).lastPathComponent)"

                    continuation.yield("Requesting macOS authorization to move Xcode into /Applications.")
                    let moveCommand = """
                    /bin/rm -rf \(Self.shellQuoted(destinationPath)) && \
                    ( \
                      /bin/mv \(Self.shellQuoted(sourcePath)) \(Self.shellQuoted(destinationPath)) || \
                      ( /usr/bin/ditto \(Self.shellQuoted(sourcePath)) \(Self.shellQuoted(destinationPath)) && /bin/rm -rf \(Self.shellQuoted(sourcePath)) ) \
                    ) && \
                    [ -d \(Self.shellQuoted(destinationPath)) ] && [ ! -e \(Self.shellQuoted(sourcePath)) ]
                    """
                    _ = try self.runShellCommandWithAdministratorPrivileges(moveCommand)
                    let destinationExists = self.fileManager.fileExists(atPath: destinationPath)
                    let sourceStillExists = self.fileManager.fileExists(atPath: sourcePath)
                    guard destinationExists && !sourceStillExists else {
                        throw XcodeManagerError.commandFailed(
                            command: moveCommand,
                            output: "Move verification failed. Destination exists: \(destinationExists). Source still exists: \(sourceStillExists)."
                        )
                    }
                    continuation.yield("Moved Xcode to \(destinationPath).")

                    if selectAfterInstall {
                        continuation.yield("Requesting macOS authorization to set active developer directory.")
                        let developerDirectory = "\(destinationPath)/Contents/Developer"
                        let selectCommand = "/usr/bin/xcode-select -s \(Self.shellQuoted(developerDirectory))"
                        _ = try self.runShellCommandWithAdministratorPrivileges(selectCommand)
                        continuation.yield("Selected Xcode at \(destinationPath).")
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            self.installIOQueue.sync {
                self.activeInstallWorker = worker
            }

            continuation.onTermination = { _ in
                worker.cancel()
                self.installIOQueue.sync {
                    self.activeInstallWorker = nil
                }
            }
        }
    }

    private func resolveInstalledPath(
        version: String,
        preferredPath: String?,
        userInstallDirectory: String
    ) throws -> String {
        if let preferredPath,
           fileManager.fileExists(atPath: preferredPath) {
            return preferredPath
        }

        if let installedOutput = try? runXcodes(arguments: ["installed", "--no-color"]) {
            let installations = XcodesOutputParser.parseInstalled(installedOutput)
            if let installedPath = installations.first(where: { installation in
                installation.version == version && installation.path.hasPrefix(userInstallDirectory)
            })?.path,
               fileManager.fileExists(atPath: installedPath) {
                return installedPath
            }
        }

        let directoryURL = URL(fileURLWithPath: userInstallDirectory, isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        let candidates = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.pathExtension.lowercased() == "app" else { return false }
            return url.lastPathComponent.lowercased().contains("xcode")
        }

        let sortedByModificationDate = candidates.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: resourceKeys).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: resourceKeys).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        if let fallback = sortedByModificationDate.first {
            return fallback.path
        }

        throw XcodeManagerError.commandFailed(
            command: "xcodes install \(version) --no-superuser --directory \(userInstallDirectory)",
            output: "Installed Xcode bundle could not be located in \(userInstallDirectory)."
        )
    }

    private func runShellCommandWithAdministratorPrivileges(_ shellCommand: String) throws -> String {
        do {
            return try runShellCommandWithAuthorizationServices(shellCommand)
        } catch PrivilegedAuthorizationError.apiUnavailable {
            return try runShellCommandWithAppleScriptPrivileges(shellCommand)
        }
    }

    private func runShellCommandWithAuthorizationServices(_ shellCommand: String) throws -> String {
        typealias AuthorizationExecuteFunction = @convention(c) (
            AuthorizationRef?,
            UnsafePointer<CChar>?,
            AuthorizationFlags,
            UnsafeMutableRawPointer?,
            UnsafeMutableRawPointer?
        ) -> OSStatus

        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges") else {
            throw PrivilegedAuthorizationError.apiUnavailable
        }

        let authorizationExecute = unsafeBitCast(symbol, to: AuthorizationExecuteFunction.self)

        var authorizationRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authorizationRef)
        guard createStatus == errAuthorizationSuccess, let authorizationRef else {
            throw XcodeManagerError.commandFailed(
                command: shellCommand,
                output: Self.authorizationStatusMessage(createStatus)
            )
        }

        defer {
            AuthorizationFree(authorizationRef, [])
        }

        let promptText = "XNox needs administrator access to move and select Xcode."
        let rightsStatus: OSStatus = kAuthorizationRightExecute.withCString { executeRightNamePointer in
            "system.privilege.admin".withCString { adminRightNamePointer in
                var rightItems: [AuthorizationItem] = [
                    AuthorizationItem(name: executeRightNamePointer, valueLength: 0, value: nil, flags: 0),
                    AuthorizationItem(name: adminRightNamePointer, valueLength: 0, value: nil, flags: 0),
                ]
                return rightItems.withUnsafeMutableBufferPointer { rightItemsPointer in
                    var rights = AuthorizationRights(
                        count: UInt32(rightItemsPointer.count),
                        items: rightItemsPointer.baseAddress
                    )
                    return promptText.withCString { promptValuePointer in
                        kAuthorizationEnvironmentPrompt.withCString { promptNamePointer in
                            var environmentItem = AuthorizationItem(
                                name: promptNamePointer,
                                valueLength: strlen(promptValuePointer),
                                value: UnsafeMutableRawPointer(mutating: promptValuePointer),
                                flags: 0
                            )
                            return withUnsafeMutablePointer(to: &environmentItem) { environmentItemPointer in
                                var environment = AuthorizationEnvironment(count: 1, items: environmentItemPointer)
                                return AuthorizationCopyRights(
                                    authorizationRef,
                                    &rights,
                                    &environment,
                                    [.interactionAllowed, .extendRights, .preAuthorize],
                                    nil
                                )
                            }
                        }
                    }
                }
            }
        }

        guard rightsStatus == errAuthorizationSuccess else {
            throw XcodeManagerError.commandFailed(
                command: shellCommand,
                output: Self.authorizationStatusMessage(rightsStatus)
            )
        }

        let wrappedCommand = "{ \(shellCommand); } 2>&1; status=$?; printf '\\n__XNoxExit:%d\\n' \"$status\"; exit \"$status\""

        var cArguments: [UnsafeMutablePointer<CChar>?] = [
            strdup("-c"),
            strdup(wrappedCommand),
            nil,
        ]
        defer {
            cArguments.forEach { pointer in
                free(pointer)
            }
        }

        var communicationPipe: UnsafeMutablePointer<FILE>?
        let executeStatus: OSStatus = cArguments.withUnsafeMutableBufferPointer { argumentsPointer in
            guard let argumentsBaseAddress = argumentsPointer.baseAddress else {
                return errAuthorizationInternal
            }

            return "/bin/sh".withCString { toolPathPointer in
                withUnsafeMutablePointer(to: &communicationPipe) { communicationPipePointer in
                    authorizationExecute(
                        authorizationRef,
                        toolPathPointer,
                        [],
                        UnsafeMutableRawPointer(argumentsBaseAddress),
                        UnsafeMutableRawPointer(communicationPipePointer)
                    )
                }
            }
        }

        guard executeStatus == errAuthorizationSuccess else {
            throw XcodeManagerError.commandFailed(
                command: shellCommand,
                output: Self.authorizationStatusMessage(executeStatus)
            )
        }

        var commandOutput = ""
        if let communicationPipe {
            defer {
                fclose(communicationPipe)
            }

            var lineBuffer = [CChar](repeating: 0, count: 4096)
            while fgets(&lineBuffer, Int32(lineBuffer.count), communicationPipe) != nil {
                commandOutput += String(cString: lineBuffer)
            }
        }

        let parsed = Self.extractPrivilegedExecutionResult(from: commandOutput)
        guard parsed.exitCode == 0 else {
            throw XcodeManagerError.commandFailed(
                command: shellCommand,
                output: parsed.output.isEmpty
                    ? "Privileged command exited with status \(parsed.exitCode)."
                    : parsed.output
            )
        }

        return parsed.output
    }

    private func runShellCommandWithAppleScriptPrivileges(_ shellCommand: String) throws -> String {
        let prompt = "XNox needs administrator access to move and select Xcode."
        let scriptSource = """
        do shell script "\(Self.appleScriptEscaped(shellCommand))" with administrator privileges with prompt "\(Self.appleScriptEscaped(prompt))"
        """

        var scriptResult = ""
        var executionError: String?

        let executeScript = {
            guard let appleScript = NSAppleScript(source: scriptSource) else {
                executionError = "Failed to initialize AppleScript authorization request."
                return
            }

            var errorInfo: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&errorInfo)

            if let errorInfo {
                if let message = errorInfo[NSAppleScript.errorMessage] as? String {
                    executionError = message
                } else {
                    executionError = "\(errorInfo)"
                }
                return
            }

            scriptResult = descriptor.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if Thread.isMainThread {
            executeScript()
        } else {
            DispatchQueue.main.sync(execute: executeScript)
        }

        if let executionError {
            throw XcodeManagerError.commandFailed(command: shellCommand, output: executionError)
        }

        return scriptResult
    }

    private static func parseMoveTargetPath(from line: String) -> String? {
        guard let marker = line.range(of: "Moving Xcode to ") else { return nil }
        let value = line[marker.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard value.hasPrefix("/"), value.hasSuffix(".app") else { return nil }
        return value
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func authorizationStatusMessage(_ status: OSStatus) -> String {
        if status == errAuthorizationCanceled {
            return "Authentication was cancelled."
        }

        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }

        return "Authorization failed with status \(status)."
    }

    private static func extractPrivilegedExecutionResult(from rawOutput: String) -> (output: String, exitCode: Int32) {
        let marker = "__XNoxExit:"
        guard let markerRange = rawOutput.range(of: marker, options: .backwards) else {
            return (rawOutput.trimmingCharacters(in: .whitespacesAndNewlines), -1)
        }

        let outputPrefix = rawOutput[..<markerRange.lowerBound]
        let trailing = rawOutput[markerRange.upperBound...]
        let exitCodeText = trailing
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let exitCode = Int32(exitCodeText) ?? -1
        let output = outputPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return (output, exitCode)
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private enum PrivilegedAuthorizationError: Error {
        case apiUnavailable
    }

    private func resolveXcodesExecutable() throws -> String {
        let paths = executableSearchPaths()

        if let whichResult = commandOutput(
            "/usr/bin/which",
            ["xcodes"],
            extraEnvironment: ["PATH": paths.joined(separator: ":")]
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !whichResult.isEmpty {
            return whichResult
        }

        for directory in paths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("xcodes").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw XcodeManagerError.executableNotFound
    }

    private func executableSearchPaths() -> [String] {
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

    private func mergedEnvironment(_ extra: [String: String] = [:]) -> [String: String] {
        var environment = processEnvironment
        environment["PATH"] = executableSearchPaths().joined(separator: ":")
        for (key, value) in extra {
            environment[key] = value
        }
        return environment
    }

    private func commandOutput(
        _ launchPath: String,
        _ arguments: [String],
        extraEnvironment: [String: String] = [:]
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = mergedEnvironment(extraEnvironment)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !stdoutText.isEmpty && !stderrText.isEmpty {
            return "\(stdoutText)\n\(stderrText)"
        }
        if !stdoutText.isEmpty {
            return stdoutText
        }
        if !stderrText.isEmpty {
            return stderrText
        }
        return nil
    }

    private func commandLine(_ arguments: [String]) -> String {
        (["xcodes"] + arguments).joined(separator: " ")
    }

    private func terminateDescendants(of pid: Int32, signal: Int32) {
        let children = childProcessIdentifiers(of: pid)
        for child in children {
            terminateDescendants(of: child, signal: signal)
            _ = kill(child, signal)
        }
    }

    private func childProcessIdentifiers(of pid: Int32) -> [Int32] {
        guard let output = commandOutput("/usr/bin/pgrep", ["-P", String(pid)]) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func extractLines(from buffer: inout Data, flushRemainder: Bool) -> [String] {
        guard !buffer.isEmpty else { return [] }

        var lines: [String] = []
        var segmentStart = buffer.startIndex
        var index = buffer.startIndex

        while index < buffer.endIndex {
            let byte = buffer[index]
            if byte == 0x0A || byte == 0x0D {
                let lineData = buffer[segmentStart..<index]
                if !lineData.isEmpty {
                    lines.append(String(decoding: lineData, as: UTF8.self))
                }

                if byte == 0x0D {
                    let nextIndex = buffer.index(after: index)
                    if nextIndex < buffer.endIndex && buffer[nextIndex] == 0x0A {
                        index = nextIndex
                    }
                }

                segmentStart = buffer.index(after: index)
            }

            index = buffer.index(after: index)
        }

        if flushRemainder {
            let remainder = buffer[segmentStart..<buffer.endIndex]
            if !remainder.isEmpty {
                lines.append(String(decoding: remainder, as: UTF8.self))
            }
            buffer.removeAll(keepingCapacity: true)
        } else if segmentStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<segmentStart)
        }

        return lines
    }
}
