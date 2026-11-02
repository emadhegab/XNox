import Foundation

/// Why `DeletionGuard` refused a path.
nonisolated enum DeletionGuardError: LocalizedError {
    case outsideAllowlist(String)
    case isRoot(String)

    var errorDescription: String? {
        switch self {
        case let .outsideAllowlist(path):
            return "Refusing to delete a path outside the allowed folders: \(path)"
        case let .isRoot(path):
            return "Refusing to delete an allowed root folder itself: \(path)"
        }
    }
}

/// The single allowlist every delete must pass. A path is allowed only if, after collapsing `..`
/// and resolving symlinks on its parent directories, it is strictly inside one of `roots`.
/// The leaf is deliberately not resolved: deleting a symlink removes the link, never its target.
// Accepted TOCTOU: validate-then-rm leaves a window; exploiting it needs a same-user attacker swapping a dir for a symlink.
nonisolated struct DeletionGuard: Sendable {
    let roots: [URL]

    /// Roots are the Storage screen's known locations under `home`.
    static func storage(home: URL) -> DeletionGuard {
        DeletionGuard(roots: StorageViewModel.defaultLocations.map {
            home.appendingPathComponent($0.relativePath, isDirectory: true)
        })
    }

    /// Returns the resolved URL that is safe to delete, or throws.
    func validate(_ url: URL) throws -> URL {
        let path = url.path
        guard path.hasPrefix("/") else { throw DeletionGuardError.outsideAllowlist(path) }

        let standardized = url.standardizedFileURL
        let resolved = standardized
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(standardized.lastPathComponent)
        let resolvedPath = resolved.path

        for root in roots {
            let rootPath = root.resolvingSymlinksInPath().path
            if resolvedPath == rootPath { throw DeletionGuardError.isRoot(resolvedPath) }
            if resolvedPath.hasPrefix(rootPath + "/") { return resolved }
        }
        throw DeletionGuardError.outsideAllowlist(path)
    }
}
