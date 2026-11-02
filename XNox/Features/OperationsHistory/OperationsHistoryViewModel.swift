import Combine
import Foundation

@MainActor
final class OperationsHistoryViewModel: ObservableObject {
    @Published private(set) var logs: [OperationLog] = []
    private let store: OperationHistoryStoring
    private var cancellables = Set<AnyCancellable>()

    init(store: OperationHistoryStoring? = nil) {
        self.store = store ?? JSONOperationHistoryStore()
        NotificationCenter.default.publisher(for: OperationHistoryRecorder.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
        reload()
    }

    func reload() {
        do {
            logs = try store.loadLogs()
        } catch {
            logs = []
        }
    }

    func append(_ log: OperationLog) {
        logs.insert(log, at: 0)
        persist()
    }

    func replace(_ log: OperationLog) {
        guard let index = logs.firstIndex(where: { $0.id == log.id }) else { return }
        logs[index] = log
        logs.sort { $0.startedAt > $1.startedAt }
        persist()
    }

    private func persist() {
        let sortedLogs = logs.sorted { $0.startedAt > $1.startedAt }
        do {
            try store.saveLogs(sortedLogs)
            logs = sortedLogs
        } catch {
            logs = sortedLogs
        }
    }
}
