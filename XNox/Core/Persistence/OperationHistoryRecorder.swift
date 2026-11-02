import Foundation

protocol OperationHistoryRecording {
    @discardableResult
    func start(feature: String, command: String, summary: String) -> UUID
    func complete(id: UUID, status: XNoxOperationStatus, summary: String, exitCode: Int?)
    func record(feature: String, command: String, status: XNoxOperationStatus, summary: String, exitCode: Int?)
}

@MainActor
final class OperationHistoryRecorder: OperationHistoryRecording {
    static let shared = OperationHistoryRecorder()
    static let didChangeNotification = Notification.Name("operationHistoryDidChange")

    private let store: OperationHistoryStoring

    init(store: OperationHistoryStoring? = nil) {
        self.store = store ?? JSONOperationHistoryStore()
    }

    @discardableResult
    func start(feature: String, command: String, summary: String = "") -> UUID {
        let log = OperationLog(
            feature: feature,
            command: command,
            status: XNoxOperationStatus.pending.rawValue,
            summary: summary
        )
        upsert(log)
        return log.id
    }

    func complete(id: UUID, status: XNoxOperationStatus, summary: String, exitCode: Int? = nil) {
        var logs = (try? store.loadLogs()) ?? []

        if let index = logs.firstIndex(where: { $0.id == id }) {
            logs[index].status = status.rawValue
            logs[index].summary = summary
            logs[index].exitCode = exitCode
            logs[index].endedAt = .now
            logs.sort { $0.startedAt > $1.startedAt }
            persist(logs)
            return
        }

        let fallback = OperationLog(
            id: id,
            feature: "Unknown",
            command: "Unknown command",
            endedAt: .now,
            exitCode: exitCode,
            status: status.rawValue,
            summary: summary
        )
        upsert(fallback)
    }

    func record(
        feature: String,
        command: String,
        status: XNoxOperationStatus,
        summary: String,
        exitCode: Int? = nil
    ) {
        let log = OperationLog(
            feature: feature,
            command: command,
            endedAt: .now,
            exitCode: exitCode,
            status: status.rawValue,
            summary: summary
        )
        upsert(log)
    }

    private func upsert(_ log: OperationLog) {
        var logs = (try? store.loadLogs()) ?? []
        if let index = logs.firstIndex(where: { $0.id == log.id }) {
            logs[index] = log
        } else {
            logs.insert(log, at: 0)
        }
        logs.sort { $0.startedAt > $1.startedAt }
        persist(logs)
    }

    private func persist(_ logs: [OperationLog]) {
        do {
            try store.saveLogs(logs)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            // Ignore persistence failures here; operation should still continue.
        }
    }
}
