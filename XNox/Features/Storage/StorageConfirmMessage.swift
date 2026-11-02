import Foundation

/// Pure builders for the Storage delete-confirmation alert bodies, so the exact paths and sizes shown
/// to the user are unit-testable. Sizes use `StorageViewModel.byteString`.
nonisolated enum StorageConfirmMessage {
    /// Most item names listed in the browser alert before collapsing to "and N more".
    static let maxListedNames = 5

    /// Single location: its path and current size.
    static func location(pathLabel: String, bytes: Int64) -> String {
        "This removes all contents in \(pathLabel) (\(size(bytes)))."
    }

    /// Delete-all: one line per location, then the total.
    static func deleteAll(locations: [(pathLabel: String, bytes: Int64)], totalBytes: Int64) -> String {
        let lines = locations.map { "\($0.pathLabel): \(size($0.bytes))" }
        return (lines + ["Total: \(size(totalBytes))", "This may remove simulator app data."]).joined(separator: "\n")
    }

    /// Browser selection: up to `maxListedNames` names, then "and N more", then the total of selected sizes.
    static func browser(names: [String], totalBytes: Int64) -> String {
        var lines = names.prefix(maxListedNames).map { "• \($0)" }
        if names.count > maxListedNames {
            lines.append("and \(names.count - maxListedNames) more")
        }
        lines.append("Total: \(size(totalBytes)). This permanently removes them from disk.")
        return lines.joined(separator: "\n")
    }

    private static func size(_ bytes: Int64) -> String {
        StorageViewModel.byteString(from: bytes)
    }
}

/// A Storage delete that stopped partway: keeps the bytes already freed so history can say how far it got.
nonisolated struct StorageDeleteFailure: Error {
    let freedBytes: Int64
    let underlying: any Error

    /// "Failed to <what>: freed X before failing: <error>"; a cancelled task reads "cancelled".
    func summary(_ what: String, cancelled: Bool) -> String {
        let reason = (cancelled || underlying is CancellationError) ? "cancelled" : underlying.localizedDescription
        return "Failed to \(what): freed \(StorageViewModel.byteString(from: freedBytes)) before failing: \(reason)"
    }

    /// Wraps any error caught outside the delete loop (nothing freed).
    static func unwrap(_ error: any Error) -> StorageDeleteFailure {
        (error as? StorageDeleteFailure) ?? StorageDeleteFailure(freedBytes: 0, underlying: error)
    }
}
