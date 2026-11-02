import Foundation

/// One History entry: what ran, when, how it ended. Stored as JSON by `JSONOperationHistoryStore`.
struct OperationLog: Codable, Identifiable, Sendable {
    let id: UUID
    var feature: String
    var command: String
    var startedAt: Date
    var endedAt: Date?
    var exitCode: Int?
    var status: String
    var summary: String

    init(
        id: UUID = UUID(),
        feature: String,
        command: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        exitCode: Int? = nil,
        status: String = "pending",
        summary: String = ""
    ) {
        self.id = id
        self.feature = feature
        self.command = command
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
        self.status = status
        self.summary = summary
    }
}
