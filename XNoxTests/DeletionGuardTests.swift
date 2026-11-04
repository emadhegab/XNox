import AppKit
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

    @Test func defaultLocationsAreUniqueAndNotNested() {
        let locations = StorageViewModel.defaultLocations
        #expect(Set(locations.map(\.id)).count == locations.count)
        for location in locations {
            #expect(NSImage(systemSymbolName: location.systemImage, accessibilityDescription: nil) != nil, "\(location.id)")
        }
        let paths = locations.map { $0.relativePath + "/" }
        #expect(Set(paths).count == paths.count)
        for path in paths {
            #expect(!path.hasPrefix("/") && !path.contains(".."))
            #expect(paths.filter { $0.hasPrefix(path) }.count == 1, "\(path) contains another root")
        }
    }

    /// Partial roots keep user data out of reach: these siblings hold settings, global tools or logs, not caches.
    @Test func dataNextToCachesIsRejected() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(try f.guardian.validate(f.home.appendingPathComponent(".npm/_cacache/x")).lastPathComponent == "x")
        for path in [
            ".npm/_logs/x",
            ".pub-cache/bin/x",
            ".gradle/gradle.properties",
            ".cargo/bin/x",
            ".m2/repository/x",
            ".android/avd/x",
            "Library/org.swift.swiftpm/x",
        ] {
            #expect(throws: DeletionGuardError.self) { try f.guardian.validate(f.home.appendingPathComponent(path)) }
        }
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

    /// On case-insensitive APFS, symlink resolution returns the on-disk case, so a wrong-case child
    /// is approved only as the same real path inside the root. The root itself in the wrong case must never pass.
    @Test func wrongCasePathsNeverEscapeOrHitTheRoot() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let xcode = f.root.deletingLastPathComponent()
        #expect(try f.guardian.validate(f.root.appendingPathComponent("x")).path == resolved(f.root) + "/x")
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(xcode.appendingPathComponent("deriveddata")) }
        #expect(throws: DeletionGuardError.self) { try f.guardian.validate(xcode.appendingPathComponent("DERIVEDDATA")) }
        if let approved = try? f.guardian.validate(xcode.appendingPathComponent("deriveddata/x")) {
            #expect(approved.path == resolved(f.root) + "/x")
        }
    }

    @Test func trailingSlashChildIsApprovedWithoutTrailingSlashAndRemoved() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let dir = f.root.appendingPathComponent("App-abc", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let withSlash = URL(fileURLWithPath: dir.path + "/")

        #expect(try f.guardian.validate(withSlash).path == resolved(f.root) + "/App-abc")
        try StorageShell.removeItem(at: withSlash, guard: f.guardian)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(f.outsideSurvives)
    }

    @Test func runnerRejectsNonAllowlistedExecutable() {
        #expect(throws: CommandError.self) {
            try ProcessCommandRunner().run("/bin/echo", ["hi"], timeout: 5)
        }
    }
}
