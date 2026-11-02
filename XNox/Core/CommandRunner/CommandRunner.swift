import Foundation

/// Runs an external command and returns its stdout. Exists so tests can inject a fake.
protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> String
}

/// Failure modes of `CommandRunning`.
enum CommandError: LocalizedError {
    case failed(command: String, message: String)
    case notAllowed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(command, message):
            if message.isEmpty {
                return "Command failed: \(command)"
            }
            return "Command failed: \(command)\n\(message)"
        case let .notAllowed(executable):
            return "Command is not in allowlist: \(executable)"
        }
    }
}

/// Real `Process`-based runner. Only a fixed set of executables may run; output goes via temp files
/// so large output cannot deadlock a pipe, and a timeout terminates the child.
struct ProcessCommandRunner: CommandRunning {
    static let allowedExecutables: Set<String> = [
        "/usr/bin/xcrun", "/usr/bin/du", "/bin/rm", "/usr/bin/open",
    ]

    func run(_ executable: String, _ arguments: [String], timeout timeoutSeconds: TimeInterval) throws -> String {
        guard Self.allowedExecutables.contains(executable) else {
            throw CommandError.notAllowed(executable)
        }
        let command = ([executable] + arguments).joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let outputURL = temporaryDirectory.appendingPathComponent("xnox-cmd-\(UUID().uuidString)-out.log")
        let errorURL = temporaryDirectory.appendingPathComponent("xnox-cmd-\(UUID().uuidString)-err.log")

        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)

        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path),
              let errorHandle = FileHandle(forWritingAtPath: errorURL.path) else {
            throw CommandError.failed(
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
            throw CommandError.failed(
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

            throw CommandError.failed(
                command: command,
                message: combinedTimeoutMessage
            )
        }

        guard process.terminationStatus == 0 else {
            let combinedMessage = [errorText, outputText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            throw CommandError.failed(
                command: command,
                message: combinedMessage
            )
        }

        return outputText
    }
}
