import Foundation

protocol CommandExecuting {
    func run(_ request: CommandRequest) -> AsyncThrowingStream<CommandEvent, Error>
}

protocol PrivilegedCommandExecuting {
    func runPrivileged(_ request: CommandRequest) -> AsyncThrowingStream<CommandEvent, Error>
}
