import Foundation

final class SkeletonPrivilegedCommandExecutor: PrivilegedCommandExecuting {
    func runPrivileged(_ request: CommandRequest) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CommandRunnerError.privilegesUnavailable)
        }
    }
}
