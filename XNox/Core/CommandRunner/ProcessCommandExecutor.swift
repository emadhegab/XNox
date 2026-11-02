import Foundation

final class ProcessCommandExecutor: CommandExecuting {
    private let allowlistedExecutables: Set<String>

    init(allowlistedExecutables: Set<String> = ["xcodes", "fastlane", "xcode-select", "xcrun"]) {
        self.allowlistedExecutables = allowlistedExecutables
    }

    func run(_ request: CommandRequest) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            guard allowlistedExecutables.contains(request.executable) else {
                continuation.finish(throwing: CommandRunnerError.executableNotAllowed(request.executable))
                return
            }

            let commandLine = ([request.executable] + request.arguments).joined(separator: " ")
            continuation.yield(.output(CommandOutputLine(text: "Skeleton command runner prepared: \(commandLine)", isError: false)))
            continuation.yield(.finished(CommandExecutionResult(exitCode: 0, startedAt: .now, endedAt: .now)))
            continuation.finish()
        }
    }
}
