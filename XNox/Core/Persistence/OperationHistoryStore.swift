import Foundation

protocol OperationHistoryStoring {
    func loadLogs() throws -> [OperationLog]
    func saveLogs(_ logs: [OperationLog]) throws
}

final class JSONOperationHistoryStore: OperationHistoryStoring {
    static let defaultRetentionDays = 30

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let retentionDaysProvider: () -> Int
    private let now: () -> Date

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        retentionDaysProvider: @escaping () -> Int = {
            let storedDays = UserDefaults.standard.integer(forKey: AppSettingsKeys.historyRetentionDays)
            return storedDays > 0 ? storedDays : JSONOperationHistoryStore.defaultRetentionDays
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.retentionDaysProvider = retentionDaysProvider
        self.now = now
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let fallback = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/XNox/operation-history.json", isDirectory: false)
            self.fileURL = appSupport?
                .appendingPathComponent("XNox", isDirectory: true)
                .appendingPathComponent("operation-history.json", isDirectory: false) ?? fallback
        }
    }

    func loadLogs() throws -> [OperationLog] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let logs = try decoder.decode([OperationLog].self, from: data)
        let prunedLogs = prune(logs)
        if prunedLogs.count != logs.count {
            try persist(prunedLogs)
        }
        return prunedLogs
    }

    func saveLogs(_ logs: [OperationLog]) throws {
        try persist(prune(logs))
    }

    private func persist(_ logs: [OperationLog]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(logs)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func prune(_ logs: [OperationLog]) -> [OperationLog] {
        let retentionDays = max(1, retentionDaysProvider())
        let retentionInterval = TimeInterval(retentionDays * 24 * 60 * 60)
        let cutoffDate = now().addingTimeInterval(-retentionInterval)
        return logs
            .filter { $0.startedAt >= cutoffDate }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
