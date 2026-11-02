import Foundation
@testable import XNox

/// Test double for `CommandRunning`. Records every call and answers via a scripted handler.
/// Lock-protected because the simulator actor calls it off the main thread.
final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let handler: @Sendable (String, [String]) throws -> String

    init(handler: @escaping @Sendable (String, [String]) throws -> String = { _, _ in "" }) {
        self.handler = handler
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Arguments of every recorded `xcrun simctl ...` call (without the leading `simctl`).
    var simctlCalls: [[String]] {
        calls.filter { $0.executable == "/usr/bin/xcrun" }.map { Array($0.arguments.dropFirst()) }
    }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> String {
        lock.lock()
        recorded.append(Call(executable: executable, arguments: arguments))
        lock.unlock()
        return try handler(executable, arguments)
    }
}
