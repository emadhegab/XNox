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
