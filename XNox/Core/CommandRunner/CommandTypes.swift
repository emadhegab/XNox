import Foundation

struct CommandRequest: Sendable {
    let executable: String
    let arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
    var requiresAdministratorPrivileges: Bool

    init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        requiresAdministratorPrivileges: Bool = false
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.requiresAdministratorPrivileges = requiresAdministratorPrivileges
    }
}

struct CommandOutputLine: Identifiable, Sendable {
    let id: UUID
    let text: String
    let isError: Bool
    let date: Date

    init(id: UUID = UUID(), text: String, isError: Bool, date: Date = .now) {
        self.id = id
        self.text = text
        self.isError = isError
        self.date = date
    }
}

struct CommandExecutionResult: Sendable {
    let exitCode: Int32
    let startedAt: Date
    let endedAt: Date
}

enum CommandEvent: Sendable {
    case output(CommandOutputLine)
    case finished(CommandExecutionResult)
}

enum CommandRunnerError: LocalizedError {
    case executableNotAllowed(String)
    case privilegesUnavailable
    case notImplemented

    var errorDescription: String? {
        switch self {
        case let .executableNotAllowed(executable):
            return "Command is not in allowlist: \(executable)"
        case .privilegesUnavailable:
            return "Privileged execution is not wired in this skeleton yet."
        case .notImplemented:
            return "Command execution is skeleton-only at this stage."
        }
    }
}
