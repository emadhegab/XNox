import Foundation
import Testing
@testable import XNox

struct OperationHistoryStoreTests {
    @Test
    func saveAndLoadRoundTrip() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let fileURL = tempRoot.appendingPathComponent("operation-history.json", isDirectory: false)
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let store = JSONOperationHistoryStore(fileURL: fileURL, now: { fixedNow })

        let logs = [
            OperationLog(
                feature: "Xcodes",
                command: "xcodes install 16.4",
                startedAt: fixedNow.addingTimeInterval(-120),
                endedAt: fixedNow.addingTimeInterval(-30),
                exitCode: 0,
                status: XNoxOperationStatus.success.rawValue,
                summary: "Completed"
            ),
            OperationLog(
                feature: "Storage",
                command: "rm -rf DerivedData",
                startedAt: fixedNow.addingTimeInterval(-60),
                endedAt: fixedNow.addingTimeInterval(-10),
                exitCode: 0,
                status: XNoxOperationStatus.success.rawValue,
                summary: "Completed"
            ),
        ]

        try store.saveLogs(logs)
        let loaded = try store.loadLogs()

        #expect(loaded.count == 2)
        #expect(loaded[0].command == "rm -rf DerivedData")
        #expect(loaded[1].command == "xcodes install 16.4")
    }

    @Test
    func prunesEntriesOlderThan30Days() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let fileURL = tempRoot.appendingPathComponent("operation-history.json", isDirectory: false)
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let store = JSONOperationHistoryStore(fileURL: fileURL, now: { fixedNow })

        let logs = [
            OperationLog(
                feature: "Old",
                command: "legacy command",
                startedAt: fixedNow.addingTimeInterval(-(31 * 24 * 60 * 60)),
                endedAt: fixedNow.addingTimeInterval(-(31 * 24 * 60 * 60 - 30)),
                exitCode: 0,
                status: XNoxOperationStatus.success.rawValue,
                summary: "Should be deleted"
            ),
            OperationLog(
                feature: "Recent",
                command: "recent command",
                startedAt: fixedNow.addingTimeInterval(-(29 * 24 * 60 * 60)),
                endedAt: fixedNow.addingTimeInterval(-(29 * 24 * 60 * 60 - 30)),
                exitCode: 0,
                status: XNoxOperationStatus.success.rawValue,
                summary: "Should remain"
            ),
        ]

        try store.saveLogs(logs)
        let loaded = try store.loadLogs()

        #expect(loaded.count == 1)
        #expect(loaded.first?.feature == "Recent")
    }
}
