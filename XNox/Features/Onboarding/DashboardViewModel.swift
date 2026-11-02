import Foundation
import Combine
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var toolStatuses: [ToolStatus] = []
    @Published var isLoading = false
    @Published var installErrorMessage: String?

    private let toolchainManager: any ToolchainManaging
    private let historyRecorder: any OperationHistoryRecording

    init(
        toolchainManager: any ToolchainManaging,
        historyRecorder: (any OperationHistoryRecording)? = nil
    ) {
        self.toolchainManager = toolchainManager
        self.historyRecorder = historyRecorder ?? OperationHistoryRecorder.shared
    }

    convenience init() {
        self.init(
            toolchainManager: LocalToolchainManager(),
            historyRecorder: nil
        )
    }

    func refresh() async {
        isLoading = true
        toolStatuses = await toolchainManager.detectTools()
        isLoading = false
    }

    func installMissingDependency(for tool: DevTool) {
        do {
            try openCommandInTerminal(tool.installCommand)
            installErrorMessage = nil
            historyRecorder.record(
                feature: "Onboarding",
                command: tool.installCommand,
                status: .success,
                summary: "Opened Terminal to install \(tool.displayName).",
                exitCode: 0
            )
        } catch {
            installErrorMessage = "Unable to launch Terminal for \(tool.displayName): \(error.localizedDescription)"
            historyRecorder.record(
                feature: "Onboarding",
                command: tool.installCommand,
                status: .failed,
                summary: installErrorMessage ?? "Unable to launch Terminal for \(tool.displayName).",
                exitCode: 1
            )
        }
    }

    func updateDependency(for status: ToolStatus) {
        guard let command = status.updateCommand else { return }

        do {
            try openCommandInTerminal(command)
            installErrorMessage = nil
            historyRecorder.record(
                feature: "Onboarding",
                command: command,
                status: .success,
                summary: "Opened Terminal to update \(status.tool.displayName).",
                exitCode: 0
            )
        } catch {
            installErrorMessage = "Unable to launch Terminal for \(status.tool.displayName): \(error.localizedDescription)"
            historyRecorder.record(
                feature: "Onboarding",
                command: command,
                status: .failed,
                summary: installErrorMessage ?? "Unable to launch Terminal for \(status.tool.displayName).",
                exitCode: 1
            )
        }
    }

    private func openCommandInTerminal(_ command: String) throws {
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscaped(command))"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let standardError = Pipe()
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            throw TerminalLaunchError.osascriptFailed(message ?? "Unknown osascript error.")
        }
    }

    private func appleScriptEscaped(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private enum TerminalLaunchError: LocalizedError {
    case osascriptFailed(String)

    var errorDescription: String? {
        switch self {
        case let .osascriptFailed(message):
            return message
        }
    }
}
