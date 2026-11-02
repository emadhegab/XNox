import Foundation

enum MatchProfileType: String, CaseIterable, Identifiable, Codable, Sendable {
    case development
    case appstore
    case adhoc

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct MatchRequest: Sendable {
    var type: MatchProfileType
    var gitURL: String
    var gitBranch: String
    var appIdentifiers: [String]
    var teamID: String
    var username: String
    var readonly: Bool
    var forceForNewDevices: Bool
    var matchPassword: String?
    var fastlaneSession: String?
    var workingDirectoryPath: String?
}

struct MatchInitRequest: Sendable {
    var gitURL: String
    var gitBranch: String
    var appIdentifiers: [String]
    var teamID: String
    var username: String
    var matchPassword: String?
    var fastlaneSession: String?
    var workingDirectoryPath: String?
}

struct MatchNukeRequest: Sendable {
    var type: MatchProfileType
    var gitURL: String
    var gitBranch: String
    var appIdentifiers: [String]
    var teamID: String
    var username: String
    var matchPassword: String?
    var fastlaneSession: String?
    var workingDirectoryPath: String?
}

struct MatchResult: Sendable {
    var success: Bool
    var output: String
}

struct SigningProjectContext: Sendable {
    var gitURL: String
    var gitBranch: String
    var appIdentifiers: [String]
    var teamID: String
    var username: String
    var workingDirectoryPath: String?
}

protocol SigningManaging {
    func runMatch(_ request: MatchRequest) async throws -> MatchResult
    func initializeMatch(_ request: MatchInitRequest) async throws -> MatchResult
    func nukeMatch(_ request: MatchNukeRequest) async throws -> MatchResult
}

extension SigningManaging {
    func makeMatchRequest(
        for project: SigningProjectContext,
        type: MatchProfileType,
        readonly: Bool,
        forceForNewDevices: Bool
    ) -> MatchRequest {
        MatchRequest(
            type: type,
            gitURL: project.gitURL,
            gitBranch: project.gitBranch,
            appIdentifiers: project.appIdentifiers,
            teamID: project.teamID,
            username: project.username,
            readonly: readonly,
            forceForNewDevices: forceForNewDevices,
            matchPassword: nil,
            fastlaneSession: nil,
            workingDirectoryPath: project.workingDirectoryPath
        )
    }

    func makeInitRequest(for project: SigningProjectContext) -> MatchInitRequest {
        MatchInitRequest(
            gitURL: project.gitURL,
            gitBranch: project.gitBranch,
            appIdentifiers: project.appIdentifiers,
            teamID: project.teamID,
            username: project.username,
            matchPassword: nil,
            fastlaneSession: nil,
            workingDirectoryPath: project.workingDirectoryPath
        )
    }

    func makeNukeRequest(
        for project: SigningProjectContext,
        type: MatchProfileType
    ) -> MatchNukeRequest {
        MatchNukeRequest(
            type: type,
            gitURL: project.gitURL,
            gitBranch: project.gitBranch,
            appIdentifiers: project.appIdentifiers,
            teamID: project.teamID,
            username: project.username,
            matchPassword: nil,
            fastlaneSession: nil,
            workingDirectoryPath: project.workingDirectoryPath
        )
    }

    func previewCommand(for request: MatchRequest) -> String {
        var parts = [
            "fastlane run match",
            "type:\(request.type.rawValue)",
            "git_url:\(request.gitURL)",
            "git_branch:\(request.gitBranch)",
        ]

        if !request.appIdentifiers.isEmpty {
            parts.append("app_identifier:\(request.appIdentifiers.joined(separator: ","))")
        }
        if !request.teamID.isEmpty {
            parts.append("team_id:\(request.teamID)")
        }
        if !request.username.isEmpty {
            parts.append("username:\(request.username)")
        }
        if request.readonly {
            parts.append("readonly:true")
        }
        if request.forceForNewDevices {
            parts.append("force_for_new_devices:true")
        }

        return prefix(for: request.workingDirectoryPath) + parts.joined(separator: " ")
    }

    func previewCommand(for request: MatchInitRequest) -> String {
        var parts = [
            "fastlane match init",
            "git_url:\(request.gitURL)",
            "git_branch:\(request.gitBranch)",
        ]

        if !request.teamID.isEmpty {
            parts.append("team_id:\(request.teamID)")
        }
        if !request.username.isEmpty {
            parts.append("username:\(request.username)")
        }

        return prefix(for: request.workingDirectoryPath) + parts.joined(separator: " ")
    }

    func previewCommand(for request: MatchNukeRequest) -> String {
        let parts = [
            "fastlane match nuke",
            request.type.rawValue,
        ]
        return prefix(for: request.workingDirectoryPath) + parts.joined(separator: " ")
    }

    private func prefix(for workingDirectoryPath: String?) -> String {
        guard let workingDirectoryPath,
              !workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return "cd \"\(workingDirectoryPath)\" && "
    }
}

enum SigningManagerError: LocalizedError {
    case skeletonOnly
    case invalidWorkingDirectory(String)
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .skeletonOnly:
            return "fastlane match command wiring is not implemented yet."
        case let .invalidWorkingDirectory(path):
            return "Invalid project path for signing: \(path)"
        case let .initializationFailed(message):
            return message
        }
    }
}

final class FastlaneSigningManager: SigningManaging {
    func runMatch(_ request: MatchRequest) async throws -> MatchResult {
        var arguments = [
            "match",
            request.type.rawValue,
            "--git_url", request.gitURL,
            "--git_branch", request.gitBranch,
        ]

        if request.readonly {
            arguments.append("--readonly")
        }
        if request.forceForNewDevices {
            arguments.append("--force_for_new_devices")
        }
        if !request.appIdentifiers.isEmpty {
            arguments.append(contentsOf: ["--app_identifier", request.appIdentifiers.joined(separator: ",")])
        }
        if !request.teamID.isEmpty {
            arguments.append(contentsOf: ["--team_id", request.teamID])
        }
        if !request.username.isEmpty {
            arguments.append(contentsOf: ["--username", request.username])
        }

        let result = try await runFastlane(
            arguments: arguments,
            workingDirectoryPath: request.workingDirectoryPath,
            extraEnvironment: environmentOverrides(
                username: request.username,
                teamID: request.teamID,
                matchPassword: request.matchPassword,
                fastlaneSession: request.fastlaneSession
            )
        )

        return result
    }

    func initializeMatch(_ request: MatchInitRequest) async throws -> MatchResult {
        let projectDirectory = try resolveWorkingDirectory(path: request.workingDirectoryPath)
        let fastlaneDirectory = projectDirectory.appendingPathComponent("fastlane", isDirectory: true)
        let matchfileURL = fastlaneDirectory.appendingPathComponent("Matchfile", isDirectory: false)

        try FileManager.default.createDirectory(at: fastlaneDirectory, withIntermediateDirectories: true)

        let body = buildMatchfileBody(request: request)
        guard let data = body.data(using: .utf8) else {
            throw SigningManagerError.initializationFailed("Unable to encode generated Matchfile.")
        }

        try data.write(to: matchfileURL, options: .atomic)

        let output = """
        Initialized project signing without interactive prompts.
        Created/updated Matchfile:
        \(matchfileURL.path)
        """

        return MatchResult(success: true, output: output)
    }

    func nukeMatch(_ request: MatchNukeRequest) async throws -> MatchResult {
        var arguments = [
            "match",
            "nuke",
            request.type.rawValue,
            "--skip_confirmation",
            "--git_url", request.gitURL,
            "--git_branch", request.gitBranch,
        ]

        if !request.appIdentifiers.isEmpty {
            arguments.append(contentsOf: ["--app_identifier", request.appIdentifiers.joined(separator: ",")])
        }
        if !request.teamID.isEmpty {
            arguments.append(contentsOf: ["--team_id", request.teamID])
        }
        if !request.username.isEmpty {
            arguments.append(contentsOf: ["--username", request.username])
        }

        let result = try await runFastlane(
            arguments: arguments,
            workingDirectoryPath: request.workingDirectoryPath,
            extraEnvironment: environmentOverrides(
                username: request.username,
                teamID: request.teamID,
                matchPassword: request.matchPassword,
                fastlaneSession: request.fastlaneSession
            )
        )

        return result
    }

    private func resolveWorkingDirectory(path: String?) throws -> URL {
        let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedPath = rawPath.isEmpty ? FileManager.default.currentDirectoryPath : rawPath
        let url = URL(fileURLWithPath: resolvedPath).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SigningManagerError.invalidWorkingDirectory(resolvedPath)
        }
        return url
    }

    private func buildMatchfileBody(request: MatchInitRequest) -> String {
        var lines: [String] = [
            "git_url(\"\(escaped(request.gitURL))\")",
            "storage_mode(\"git\")",
            "git_branch(\"\(escaped(request.gitBranch))\")",
        ]

        if !request.appIdentifiers.isEmpty {
            let identifiers = request.appIdentifiers
                .map { "\"\(escaped($0))\"" }
                .joined(separator: ", ")
            lines.append("app_identifier([\(identifiers)])")
        }

        if !request.username.isEmpty {
            lines.append("username(\"\(escaped(request.username))\")")
        }

        if !request.teamID.isEmpty {
            lines.append("team_id(\"\(escaped(request.teamID))\")")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runFastlane(
        arguments: [String],
        workingDirectoryPath: String?,
        extraEnvironment: [String: String]
    ) async throws -> MatchResult {
        let workingDirectory = try resolveWorkingDirectory(path: workingDirectoryPath)

        var environment = ProcessInfo.processInfo.environment
        environment["CI"] = "1"
        environment["FASTLANE_SKIP_UPDATE_CHECK"] = "1"
        environment["FASTLANE_DISABLE_COLORS"] = "1"
        environment["FASTLANE_HIDE_TIMESTAMP"] = "1"
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        for (key, value) in extraEnvironment {
            environment[key] = value
        }

        let searchPath = resolvedSearchPath(currentPath: environment["PATH"])
        environment["PATH"] = searchPath

        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.environment = environment

        if FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent("Gemfile").path),
           let bundleExecutable = resolveExecutable(named: "bundle", searchPath: searchPath) {
            process.executableURL = URL(fileURLWithPath: bundleExecutable)
            process.arguments = ["exec", "fastlane"] + arguments
        } else if let fastlaneExecutable = resolveExecutable(named: "fastlane", searchPath: searchPath) {
            process.executableURL = URL(fileURLWithPath: fastlaneExecutable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["fastlane"] + arguments
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        async let stdoutData = stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
        async let stderrData = stderrPipe.fileHandleForReading.readToEnd() ?? Data()

        process.waitUntilExit()

        let output = String(data: try await stdoutData, encoding: .utf8) ?? ""
        let errorOutput = String(data: try await stderrData, encoding: .utf8) ?? ""
        var mergedOutput = ([output, errorOutput].filter { !$0.isEmpty }).joined(separator: "\n")

        if process.terminationStatus != 0,
           mergedOutput.localizedCaseInsensitiveContains("fastlane"),
           mergedOutput.localizedCaseInsensitiveContains("No such file or directory") {
            mergedOutput += "\n\nfastlane could not be found in PATH.\nResolved PATH:\n\(searchPath)"
        }

        return MatchResult(
            success: process.terminationStatus == 0,
            output: mergedOutput.isEmpty
                ? "fastlane produced no output."
                : mergedOutput
        )
    }

    private func resolvedSearchPath(currentPath: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.rbenv/shims",
            "\(home)/.asdf/shims",
            "\(home)/.gem/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        let current = (currentPath ?? "")
            .split(separator: ":")
            .map(String.init)

        var seen = Set<String>()
        var merged: [String] = []
        for entry in defaults + current {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            merged.append(trimmed)
        }
        return merged.joined(separator: ":")
    }

    private func resolveExecutable(named executable: String, searchPath: String?) -> String? {
        guard let searchPath else { return nil }
        let directories = searchPath.split(separator: ":").map(String.init)
        for directory in directories {
            let path = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(executable, isDirectory: false)
                .path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func environmentOverrides(
        username: String,
        teamID: String,
        matchPassword: String?,
        fastlaneSession: String?
    ) -> [String: String] {
        var values: [String: String] = [:]
        if !username.isEmpty {
            values["FASTLANE_USER"] = username
        }
        if !teamID.isEmpty {
            values["FASTLANE_TEAM_ID"] = teamID
        }
        if let matchPassword,
           !matchPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["MATCH_PASSWORD"] = matchPassword
        }
        if let fastlaneSession,
           !fastlaneSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["FASTLANE_SESSION"] = fastlaneSession
        }
        return values
    }
}
