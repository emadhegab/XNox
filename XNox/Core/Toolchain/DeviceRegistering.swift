import Foundation

struct DeviceRegistrationRequest: Sendable {
    var name: String
    var udid: String
    var platform: String
    var teamID: String
    var username: String
    var fastlaneSession: String?
    var workingDirectoryPath: String?
}

struct DeviceFetchRequest: Sendable {
    var teamID: String
    var username: String
    var fastlaneSession: String?
    var workingDirectoryPath: String?
}

struct RegisteredDevice: Codable, Hashable, Identifiable, Sendable {
    var id: String { udid }
    var name: String
    var udid: String
    var platform: String
}

struct DeviceRegistrationResult: Sendable {
    var success: Bool
    var output: String
}

struct DeviceFetchResult: Sendable {
    var success: Bool
    var output: String
    var devices: [RegisteredDevice]
}

protocol DeviceRegistering {
    func register(_ request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResult
    func fetchDevices(_ request: DeviceFetchRequest) async throws -> DeviceFetchResult
}

enum DeviceRegistrarError: LocalizedError {
    case skeletonOnly
    case invalidWorkingDirectory(String)
    case unableToParseDevices

    var errorDescription: String? {
        switch self {
        case .skeletonOnly:
            return "Device registration command wiring is not implemented yet."
        case let .invalidWorkingDirectory(path):
            return "Invalid project path for device registration: \(path)"
        case .unableToParseDevices:
            return "Unable to parse device list from Apple Developer Portal output."
        }
    }
}

final class FastlaneDeviceRegistrar: DeviceRegistering {
    func register(_ request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResult {
        let arguments = [
            "run",
            "register_device",
            "name:\(request.name)",
            "udid:\(request.udid)",
            "platform:\(request.platform)",
        ]

        let result = try await runProcess(
            arguments: arguments,
            request: request,
            mode: .fastlane
        )

        return DeviceRegistrationResult(success: result.exitCode == 0, output: result.output)
    }

    func fetchDevices(_ request: DeviceFetchRequest) async throws -> DeviceFetchResult {
        let script = Self.deviceFetchRubyScript
        let processRequest = DeviceRegistrationRequest(
            name: "",
            udid: "",
            platform: "ios",
            teamID: request.teamID,
            username: request.username,
            fastlaneSession: request.fastlaneSession,
            workingDirectoryPath: request.workingDirectoryPath
        )

        let execution = try await runProcess(
            arguments: ["-e", script],
            request: processRequest,
            mode: .ruby
        )

        let devices = try parseDevices(from: execution.output)
        return DeviceFetchResult(
            success: execution.exitCode == 0,
            output: execution.output,
            devices: devices
        )
    }

    private enum ExecutionMode {
        case fastlane
        case ruby
    }

    private struct ProcessExecutionResult {
        var exitCode: Int32
        var output: String
    }

    private func runProcess(
        arguments: [String],
        request: DeviceRegistrationRequest,
        mode: ExecutionMode
    ) async throws -> ProcessExecutionResult {
        let workingDirectory = try resolveWorkingDirectory(path: request.workingDirectoryPath)
        var environment = ProcessInfo.processInfo.environment
        environment["CI"] = "1"
        environment["FASTLANE_SKIP_UPDATE_CHECK"] = "1"
        environment["FASTLANE_DISABLE_COLORS"] = "1"
        environment["FASTLANE_HIDE_TIMESTAMP"] = "1"
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"

        if !request.username.isEmpty {
            environment["FASTLANE_USER"] = request.username
        }
        if !request.teamID.isEmpty {
            environment["FASTLANE_TEAM_ID"] = request.teamID
            environment["REGISTER_DEVICE_TEAM_ID"] = request.teamID
        }
        if let fastlaneSession = request.fastlaneSession,
           !fastlaneSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            environment["FASTLANE_SESSION"] = fastlaneSession
        }

        let searchPath = resolvedSearchPath(currentPath: environment["PATH"])
        environment["PATH"] = searchPath

        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.environment = environment

        switch mode {
        case .fastlane:
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
        case .ruby:
            if FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent("Gemfile").path),
               let bundleExecutable = resolveExecutable(named: "bundle", searchPath: searchPath) {
                process.executableURL = URL(fileURLWithPath: bundleExecutable)
                process.arguments = ["exec", "ruby"] + arguments
            } else if let rubyExecutable = resolveExecutable(named: "ruby", searchPath: searchPath) {
                process.executableURL = URL(fileURLWithPath: rubyExecutable)
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["ruby"] + arguments
            }
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

        return ProcessExecutionResult(
            exitCode: process.terminationStatus,
            output: mergedOutput.isEmpty ? "Command produced no output." : mergedOutput
        )
    }

    private func parseDevices(from output: String) throws -> [RegisteredDevice] {
        let begin = "XNox_DEVICES_JSON_BEGIN"
        let end = "XNox_DEVICES_JSON_END"

        guard let beginRange = output.range(of: begin),
              let endRange = output.range(of: end),
              beginRange.upperBound <= endRange.lowerBound else {
            throw DeviceRegistrarError.unableToParseDevices
        }

        let json = output[beginRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = json.data(using: .utf8) else {
            throw DeviceRegistrarError.unableToParseDevices
        }

        let decoded = try JSONDecoder().decode([RegisteredDevice].self, from: data)
        return decoded.sorted {
            let lhs = $0.name.localizedLowercase
            let rhs = $1.name.localizedLowercase
            if lhs != rhs {
                return lhs < rhs
            }
            return $0.udid < $1.udid
        }
    }

    private func resolveWorkingDirectory(path: String?) throws -> URL {
        let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedPath = rawPath.isEmpty ? FileManager.default.currentDirectoryPath : rawPath
        let url = URL(fileURLWithPath: resolvedPath).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DeviceRegistrarError.invalidWorkingDirectory(resolvedPath)
        }
        return url
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

    private static let deviceFetchRubyScript = #"""
require 'json'
require 'spaceship'

username = ENV['FASTLANE_USER'].to_s.strip
team_id = ENV['FASTLANE_TEAM_ID'].to_s.strip

abort('FASTLANE_USER is required') if username.empty?

Spaceship::Portal.login(username)
Spaceship::Portal.select_team(team_id: team_id) unless team_id.empty?

devices = Spaceship::Portal.device.all.map do |device|
  {
    name: device.name.to_s,
    udid: device.udid.to_s,
    platform: device.platform.to_s
  }
end

puts('XNox_DEVICES_JSON_BEGIN')
puts(JSON.generate(devices))
puts('XNox_DEVICES_JSON_END')
"""#
}
