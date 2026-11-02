import Foundation

protocol CommandExecuting {
    func run(_ request: CommandRequest) -> AsyncThrowingStream<CommandEvent, Error>
}
