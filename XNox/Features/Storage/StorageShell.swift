import Foundation

enum StorageShellError: LocalizedError {
    case commandFailed(command: String, message: String)
    case invalidOutput(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, message):
            return "\(command) failed: \(message)"
        case let .invalidOutput(command, output):
            return "\(command) returned unexpected output: \(output)"
        }
    }
}

enum StorageShell {
    static func allocatedSize(at url: URL) throws -> Int64 {
        let output = try run(executablePath: "/usr/bin/du", arguments: ["-sk", url.path])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstField = trimmed.split(whereSeparator: \.isWhitespace).first,
              let sizeInKB = Int64(firstField) else {
            throw StorageShellError.invalidOutput(command: "du -sk", output: output)
        }
        return sizeInKB * 1_024
    }

    static func removeItem(at url: URL) throws {
        _ = try run(executablePath: "/bin/rm", arguments: ["-rf", "--", url.path])
    }

    @discardableResult
    static func run(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw StorageShellError.commandFailed(
                command: ([executablePath] + arguments).joined(separator: " "),
                message: message.isEmpty ? "exit code \(process.terminationStatus)" : message
            )
        }

        return stdout
    }
}
