import Foundation
import Testing
@testable import XNox

/// Records every history call so tests can assert status and summary. Never touches the real log.
final class FakeHistoryRecorder: OperationHistoryRecording {
    struct Entry { var command: String; var status: XNoxOperationStatus; var summary: String }
    private(set) var entries: [UUID: Entry] = [:]

    func start(feature: String, command: String, summary: String) -> UUID {
        let id = UUID()
        entries[id] = Entry(command: command, status: .pending, summary: summary)
        return id
    }

    func complete(id: UUID, status: XNoxOperationStatus, summary: String, exitCode: Int?) {
        entries[id]?.status = status
        entries[id]?.summary = summary
    }

    func record(feature: String, command: String, status: XNoxOperationStatus, summary: String, exitCode: Int?) {
        entries[UUID()] = Entry(command: command, status: status, summary: summary)
    }

    var only: Entry? { entries.count == 1 ? entries.values.first : nil }
}

/// Storage deletes against a fake $HOME in the temp directory, with a fake history recorder.
@MainActor
struct StorageDeleteHistoryTests {
    private struct Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var home: URL { base.appendingPathComponent("home", isDirectory: true) }
        var derived: URL { home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true) }
        var outside: URL { home.appendingPathComponent("Documents", isDirectory: true) }

        init() throws {
            let fm = FileManager.default
            try fm.createDirectory(at: derived, withIntermediateDirectories: true)
            try fm.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: derived.appendingPathComponent("a.bin"))
            try Data(repeating: 1, count: 4096).write(to: outside.appendingPathComponent("keep.bin"))
        }

        func cleanup() { try? FileManager.default.removeItem(at: base) }
    }

    private func location(_ id: String, _ relativePath: String) -> StorageLocation {
        StorageLocation(id: id, title: id, subtitle: "", relativePath: relativePath, cleanupNote: "", systemImage: "folder")
    }

    @Test func locationDeleteSuccessIsRecorded() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let recorder = FakeHistoryRecorder()
        let loc = location("derived", "Library/Developer/Xcode/DerivedData")
        let vm = StorageViewModel(historyRecorder: recorder, locations: [loc], homeDirectory: f.home)

        await vm.delete(locationID: "derived")

        #expect(recorder.only?.status == .success)
        #expect(recorder.only?.summary.contains("Freed") == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.derived.path).isEmpty)
    }

    @Test func guardRejectedLocationIsRecordedAsFailed() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let recorder = FakeHistoryRecorder()
        let vm = StorageViewModel(historyRecorder: recorder, locations: [location("docs", "Documents")], homeDirectory: f.home)

        await vm.delete(locationID: "docs")

        #expect(recorder.only?.status == .failed)
        #expect(recorder.only?.summary.hasPrefix("Failed to") == true)
        #expect(recorder.only?.summary.contains("freed") == false)
        #expect(FileManager.default.fileExists(atPath: f.outside.appendingPathComponent("keep.bin").path))
    }

    @Test func browserPartialFailureRecordsBytesFreedBeforeFailing() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let recorder = FakeHistoryRecorder()
        func item(_ url: URL, size: Int64) -> StorageLocationBrowserItem {
            StorageLocationBrowserItem(
                id: url.path, name: url.lastPathComponent, absolutePath: url.path, isDirectory: false,
                sizeBytes: size, modifiedAt: nil, createdAt: nil, lastUsedAt: nil
            )
        }
        let good = item(f.derived.appendingPathComponent("a.bin"), size: 4096)
        let bad = item(f.outside.appendingPathComponent("keep.bin"), size: 4096)
        let vm = StorageLocationBrowserViewModel(
            locationTitle: "DerivedData", locationID: "derived", basePath: f.derived.path,
            initialItems: [good, bad], historyRecorder: recorder, home: f.home
        )
        vm.selectedItemIDs = [good.id, bad.id]

        let result = await vm.deleteSelected()

        #expect(result == nil)
        #expect(recorder.only?.status == .failed)
        #expect(recorder.only?.summary.contains("freed \(StorageViewModel.byteString(from: 4096)) before failing") == true)
        #expect(!FileManager.default.fileExists(atPath: good.absolutePath))
        #expect(FileManager.default.fileExists(atPath: bad.absolutePath))
    }

    @Test func browserSuccessIsRecorded() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let recorder = FakeHistoryRecorder()
        let url = f.derived.appendingPathComponent("a.bin")
        let good = StorageLocationBrowserItem(
            id: url.path, name: "a.bin", absolutePath: url.path, isDirectory: false,
            sizeBytes: 4096, modifiedAt: nil, createdAt: nil, lastUsedAt: nil
        )
        let vm = StorageLocationBrowserViewModel(
            locationTitle: "DerivedData", locationID: "derived", basePath: f.derived.path,
            initialItems: [good], historyRecorder: recorder, home: f.home
        )
        vm.selectedItemIDs = [good.id]

        #expect(await vm.deleteSelected()?.deletedCount == 1)
        #expect(recorder.only?.status == .success)
    }
}
