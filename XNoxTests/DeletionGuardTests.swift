import Foundation
import Testing
@testable import XNox

/// DeletionGuard and guarded removal, exercised only inside a throwaway fake $HOME in the temp directory.
struct DeletionGuardTests {
    /// Fake home with a DerivedData root and a sibling "outside" folder; removed by `cleanup()`.
    private struct Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var home: URL { base.appendingPathComponent("home", isDirectory: true) }
        var root: URL { home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true) }
        var outside: URL { base.appendingPathComponent("outside", isDirectory: true) }
        var guardian: DeletionGuard { .storage(home: home) }

        init() throws {
            let fm = FileManager.default
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try fm.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: outside.appendingPathComponent("keep.txt"))
        }

        func cleanup() { try? FileManager.default.removeItem(at: base) }
        var outsideSurvives: Bool { FileManager.default.fileExists(atPath: outside.appendingPathComponent("keep.txt").path) }
    }

    private func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    @Test func childAndGrandchildAreAllowed() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let child = f.root.appendingPathComponent("App-abc")
        let grandchild = child.appendingPathComponent("Build/x.o")
        #expect(try f.guardian.validate(child).path == resolved(f.root) + "/App-abc")
        #expect(try f.guardian.validate(grandchild).path == resolved(f.root) + "/App-abc/Build/x.o")
    }

    @Test func rootItselfIsRejected() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(f.root) }
    }

    @Test func siblingWithSharedPrefixIsRejected() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let sibling = f.root.deletingLastPathComponent().appendingPathComponent("DerivedData2/x")
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(sibling) }
    }

    @Test func dotDotEscapeIsRejected() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let escape = URL(fileURLWithPath: f.root.path + "/../Other")
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(escape) }
    }

    @Test func absoluteOutsidePathIsRejected() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(f.outside) }
    }

    @Test func relativeAndEmptyPathsAreRejected() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(try #require(URL(string: "relative/path"))) }
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(URL(fileURLWithPath: "")) }
    }

    @Test func symlinkChildToOutsideIsAllowedAndOnlyLinkIsRemoved() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let link = f.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.outside)

        try StorageShell.removeItem(at: link, guard: f.guardian)

        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(f.outsideSurvives)
    }

    @Test func symlinkedRootWorks() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let fm = FileManager.default
        let realRoot = f.base.appendingPathComponent("real-dd", isDirectory: true)
        try fm.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try fm.removeItem(at: f.root)
        try fm.createSymbolicLink(at: f.root, withDestinationURL: realRoot)
        let child = realRoot.appendingPathComponent("child")
        try fm.createDirectory(at: child, withIntermediateDirectories: true)

        // Reached via the symlinked root and via its real location: both allowed.
        #expect(throws: Never.self) { try f.guardian.validate(f.root.appendingPathComponent("child")) }
        try StorageShell.removeItem(at: f.root.appendingPathComponent("child"), guard: f.guardian)
        #expect(!fm.fileExists(atPath: child.path))
    }

    @Test func intermediateSymlinkPointingOutsideIsRejected() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let hop = f.root.appendingPathComponent("hop")
        try FileManager.default.createSymbolicLink(at: hop, withDestinationURL: f.outside)
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(hop.appendingPathComponent("keep.txt")) }
        #expect(throws: DeletionGuardError.self) { try StorageShell.removeItem(at: hop.appendingPathComponent("keep.txt"), guard: f.guardian) }
        #expect(f.outsideSurvives)
    }

    @Test func guardedRemoveItemDeletesInsideAndLeavesOutside() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let dir = f.root.appendingPathComponent("App-abc/Build")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: dir.appendingPathComponent("a.o"))

        try StorageShell.removeItem(at: f.root.appendingPathComponent("App-abc"), guard: f.guardian)

        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("App-abc").path))
        #expect(FileManager.default.fileExists(atPath: f.root.path))
        #expect(f.outsideSurvives)
    }

    @Test func runnerRejectsNonAllowlistedExecutable() {
        #expect(throws: CommandError.self) {
            try ProcessCommandRunner().run("/bin/echo", ["hi"], timeout: 5)
        }
    }
}
