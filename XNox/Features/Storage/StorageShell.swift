import Foundation

nonisolated enum StorageShellError: LocalizedError {
    case invalidOutput(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case let .invalidOutput(command, output):
            return "\(command) returned unexpected output: \(output)"
        }
    }
}

nonisolated enum StorageShell {
    private static let runner = ProcessCommandRunner()
    /// du timeout.
    private static let commandTimeout: TimeInterval = 300
    /// rm of one huge child (simulator runtimes, DerivedData) can run very long.
    private static let removeTimeout: TimeInterval = 3600

    static func allocatedSize(at url: URL) throws -> Int64 {
        let output = try runner.run("/usr/bin/du", ["-sk", url.path], timeout: commandTimeout)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstField = trimmed.split(whereSeparator: \.isWhitespace).first,
              let sizeInKB = Int64(firstField) else {
            throw StorageShellError.invalidOutput(command: "du -sk", output: output)
        }
        return sizeInKB * 1_024
    }

    /// The only delete entry point: `deletionGuard` must approve `url`, and the resolved path is what gets removed.
    static func removeItem(at url: URL, guard deletionGuard: DeletionGuard) throws {
        let safeURL = try deletionGuard.validate(url)
        _ = try runner.run("/bin/rm", ["-rf", "--", safeURL.path], timeout: removeTimeout)
    }
}
