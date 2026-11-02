import AppKit
import Combine
import Foundation

enum StorageItemRecencyBand: Hashable, Sendable {
    case recent
    case month
    case sixMonths
    case year
    case unknown
}

struct StorageLocationBrowserSection: Identifiable, Hashable, Sendable {
    let band: StorageItemRecencyBand
    let title: String
    let detail: String
    let items: [StorageLocationBrowserItem]

    var id: StorageItemRecencyBand {
        band
    }
}

struct StorageBrowserDeletionProgress: Hashable, Sendable {
    let completedUnitCount: Int
    let totalUnitCount: Int

    var fractionCompleted: Double {
        guard totalUnitCount > 0 else { return 0 }
        return min(1, max(0, Double(completedUnitCount) / Double(totalUnitCount)))
    }
}

struct StorageBrowserDeletionResult: Hashable, Sendable {
    let deletedCount: Int
    let reclaimedBytes: Int64
}

struct StorageLocationBrowserItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let absolutePath: String
    let isDirectory: Bool
    let sizeBytes: Int64
    let modifiedAt: Date?
    let createdAt: Date?
    let lastUsedAt: Date?

    var systemImage: String {
        isDirectory ? "folder" : "doc"
    }

    var sizeLabel: String {
        StorageViewModel.byteString(from: sizeBytes)
    }

    var modifiedAtLabel: String {
        guard let modifiedAt else { return "Unknown date" }
        return modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var createdAtLabel: String {
        guard let createdAt else { return "Unknown" }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var lastUsedAtLabel: String {
        guard let lastUsedAt = lastUsedAt ?? modifiedAt else { return "Unknown" }
        return lastUsedAt.formatted(date: .abbreviated, time: .shortened)
    }

    nonisolated var recencyBand: StorageItemRecencyBand {
        guard let lastUsedAt = lastUsedAt ?? modifiedAt else {
            return .unknown
        }

        let age = Date.now.timeIntervalSince(lastUsedAt)
        let day: TimeInterval = 24 * 60 * 60
        if age < (30 * day) {
            return .recent
        }
        if age < (180 * day) {
            return .month
        }
        if age < (365 * day) {
            return .sixMonths
        }
        return .year
    }

    nonisolated var sortDate: Date {
        lastUsedAt ?? modifiedAt ?? createdAt ?? .distantPast
    }
}

@MainActor
final class StorageLocationBrowserViewModel: ObservableObject {
    @Published private(set) var items: [StorageLocationBrowserItem] = []
    @Published var selectedItemIDs: Set<String> = []
    @Published var statusMessage: String
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published private(set) var deletionProgress: StorageBrowserDeletionProgress?

    let locationTitle: String
    let locationID: String
    let basePath: String

    private let baseURL: URL
    private let home: URL
    private let historyRecorder: any OperationHistoryRecording
    private var selectionAnchorItemID: String?
    nonisolated private static let coreSimulatorDevicesLocationID = "core-simulator-devices"
    nonisolated private static let simulatorLastUsedKeys = [
        "lastBootedAt",
        "lastBootedDate",
        "lastUsedAt",
    ]

    init(
        locationTitle: String,
        locationID: String,
        basePath: String,
        initialItems: [StorageLocationBrowserItem] = [],
        historyRecorder: (any OperationHistoryRecording)? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.home = home
        self.locationTitle = locationTitle
        self.locationID = locationID
        self.basePath = basePath
        baseURL = URL(fileURLWithPath: basePath, isDirectory: true)
        self.historyRecorder = historyRecorder ?? OperationHistoryRecorder.shared
        let sortedInitialItems = Self.sortItems(initialItems)
        if sortedInitialItems.isEmpty {
            statusMessage = "Load files to browse and clean items individually."
        } else {
            statusMessage = "Loaded \(sortedInitialItems.count) cached items from \(locationTitle)."
        }
        items = sortedInitialItems
    }

    var selectedCount: Int {
        selectedItemIDs.count
    }

    var selectedReclaimableBytes: Int64 {
        items.reduce(into: 0) { partial, item in
            guard selectedItemIDs.contains(item.id) else { return }
            partial += item.sizeBytes
        }
    }

    var selectedSummaryLabel: String {
        let selectedCount = self.selectedCount
        guard selectedCount > 0 else {
            return "0 selected"
        }
        let reclaimLabel = StorageViewModel.byteString(from: selectedReclaimableBytes)
        return "\(selectedCount.formatted()) selected (\(reclaimLabel) reclaimed)"
    }

    var canDeleteSelected: Bool {
        !selectedItemIDs.isEmpty && !isDeleting && !isLoading
    }

    var sections: [StorageLocationBrowserSection] {
        Self.makeSections(from: items)
    }

    func isSelected(_ itemID: String) -> Bool {
        selectedItemIDs.contains(itemID)
    }

    func setSelected(_ isSelected: Bool, for itemID: String, extendingRange: Bool = false) {
        if extendingRange,
           let anchorItemID = selectionAnchorItemID,
           let anchorIndex = itemIndex(for: anchorItemID),
           let targetIndex = itemIndex(for: itemID) {
            let lowerBound = min(anchorIndex, targetIndex)
            let upperBound = max(anchorIndex, targetIndex)
            let rangedItemIDs = items[lowerBound ... upperBound].map(\.id)

            if isSelected {
                selectedItemIDs.formUnion(rangedItemIDs)
            } else {
                selectedItemIDs.subtract(rangedItemIDs)
            }

            if selectedItemIDs.isEmpty {
                selectionAnchorItemID = nil
            }
            return
        }

        if isSelected {
            selectedItemIDs.insert(itemID)
        } else {
            selectedItemIDs.remove(itemID)
        }

        if selectedItemIDs.isEmpty {
            selectionAnchorItemID = nil
        } else {
            selectionAnchorItemID = itemID
        }
    }

    func selectAll() {
        selectedItemIDs = Set(items.map(\.id))
        selectionAnchorItemID = items.first?.id
    }

    func clearSelection() {
        selectedItemIDs = []
        selectionAnchorItemID = nil
    }

    func openInFinder(itemID: String) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.absolutePath)])
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        statusMessage = "Scanning \(locationTitle) contents..."
        defer { isLoading = false }

        let baseURL = self.baseURL
        let locationID = self.locationID

        do {
            let loadedItems = try await Task.detached(priority: .utility) { () -> [StorageLocationBrowserItem] in
                try Self.loadItems(at: baseURL, locationID: locationID)
            }.value

            let sortedItems = Self.sortItems(loadedItems)

            items = sortedItems

            let validItemIDs = Set(sortedItems.map(\.id))
            selectedItemIDs = selectedItemIDs.intersection(validItemIDs)

            if let selectionAnchorItemID, !validItemIDs.contains(selectionAnchorItemID) {
                self.selectionAnchorItemID = selectedItemIDs.first
            }

            if sortedItems.isEmpty {
                statusMessage = "No files or folders found in \(locationTitle)."
            } else {
                statusMessage = "Loaded \(sortedItems.count) items from \(locationTitle)."
            }
        } catch {
            statusMessage = "Failed to load files: \(error.localizedDescription)"
        }
    }

    func deleteSelected() async -> StorageBrowserDeletionResult? {
        guard !isDeleting else { return nil }

        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        guard !selectedItems.isEmpty else {
            statusMessage = "Select at least one file or folder to delete."
            return nil
        }
        let expectedReclaimedBytes = selectedItems.reduce(into: Int64(0)) { partial, item in
            partial += item.sizeBytes
        }

        isDeleting = true
        statusMessage = "Deleting \(selectedItems.count) selected item(s)..."
        deletionProgress = StorageBrowserDeletionProgress(completedUnitCount: 0, totalUnitCount: selectedItems.count)
        defer {
            isDeleting = false
            deletionProgress = nil
        }
        let historyID = historyRecorder.start(
            feature: "Storage",
            command: "delete-selected \(locationID)",
            summary: "Deleting \(selectedItems.count) item(s) from \(locationTitle)."
        )

        let deletionGuard = DeletionGuard.storage(home: home)

        do {
            let deletionResult = try await Task.detached(priority: .userInitiated) { () throws -> Int in
                var deletedCount = 0
                var freed: Int64 = 0

                for (index, item) in selectedItems.enumerated() {
                    let itemURL = URL(fileURLWithPath: item.absolutePath)
                    do {
                        try StorageShell.removeItem(at: itemURL, guard: deletionGuard)
                    } catch {
                        throw StorageDeleteFailure(freedBytes: freed, underlying: error)
                    }
                    deletedCount += 1
                    freed += item.sizeBytes
                    Task { @MainActor [weak self] in
                        self?.deletionProgress = StorageBrowserDeletionProgress(
                            completedUnitCount: index + 1,
                            totalUnitCount: selectedItems.count
                        )
                    }
                }

                return deletedCount
            }.value

            let deletedItemIDs = Set(selectedItems.map(\.id))
            items.removeAll { deletedItemIDs.contains($0.id) }
            selectedItemIDs = []
            selectionAnchorItemID = nil

            if items.isEmpty {
                statusMessage = "Deleted \(deletionResult) item(s). \(locationTitle) is now empty."
            } else {
                statusMessage = "Deleted \(deletionResult) item(s). Freed approximately \(StorageViewModel.byteString(from: expectedReclaimedBytes))."
            }
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
            return StorageBrowserDeletionResult(
                deletedCount: deletionResult,
                reclaimedBytes: expectedReclaimedBytes
            )
        } catch {
            statusMessage = StorageDeleteFailure.unwrap(error).summary("delete selected items", cancelled: Task.isCancelled)
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
            return nil
        }
    }

    nonisolated private static func loadItems(at url: URL, locationID: String) throws -> [StorageLocationBrowserItem] {
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .nameKey,
            .creationDateKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ]

        let entries = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        var items: [StorageLocationBrowserItem] = []
        items.reserveCapacity(entries.count)

        for entryURL in entries {
            let values = try? entryURL.resourceValues(forKeys: keys)
            let isEntryDirectory = values?.isDirectory == true
            let entrySize = (try? StorageShell.allocatedSize(at: entryURL))
                ?? Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
            let baseName = values?.name ?? entryURL.lastPathComponent
            let simulatorMetadata = coreSimulatorMetadata(
                for: entryURL,
                fallbackName: baseName,
                isDirectory: isEntryDirectory,
                locationID: locationID,
                fileManager: fileManager
            )
            let displayName = simulatorMetadata?.displayName ?? baseName
            let lastUsedAt = simulatorMetadata?.lastUsedAt ?? values?.contentModificationDate

            items.append(
                StorageLocationBrowserItem(
                    id: entryURL.path,
                    name: displayName,
                    absolutePath: entryURL.path,
                    isDirectory: isEntryDirectory,
                    sizeBytes: entrySize,
                    modifiedAt: values?.contentModificationDate,
                    createdAt: values?.creationDate,
                    lastUsedAt: lastUsedAt
                )
            )
        }

        return items
    }

    nonisolated private struct CoreSimulatorMetadata {
        let displayName: String
        let lastUsedAt: Date?
    }

    nonisolated private static func coreSimulatorMetadata(
        for entryURL: URL,
        fallbackName: String,
        isDirectory: Bool,
        locationID: String,
        fileManager: FileManager
    ) -> CoreSimulatorMetadata? {
        guard locationID == coreSimulatorDevicesLocationID, isDirectory else {
            return nil
        }
        guard UUID(uuidString: fallbackName) != nil else {
            return nil
        }

        let devicePlistURL = entryURL.appendingPathComponent("device.plist", isDirectory: false)
        guard fileManager.fileExists(atPath: devicePlistURL.path),
              let plistData = fileManager.contents(atPath: devicePlistURL.path),
              let plistObject = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
              ),
              let plistDictionary = plistObject as? [String: Any] else {
            return nil
        }

        let simulatorName = simulatorName(from: plistDictionary)
        let lastUsedAt = simulatorLastUsedDate(
            from: plistDictionary
        ) ?? (try? devicePlistURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        let displayName: String
        if let simulatorName,
           simulatorName.caseInsensitiveCompare(fallbackName) != .orderedSame {
            displayName = "\(fallbackName) (\(simulatorName))"
        } else {
            displayName = fallbackName
        }

        return CoreSimulatorMetadata(displayName: displayName, lastUsedAt: lastUsedAt)
    }

    nonisolated private static func simulatorName(from plistDictionary: [String: Any]) -> String? {
        guard let rawName = plistDictionary["name"] as? String else {
            return nil
        }

        let simulatorName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !simulatorName.isEmpty else {
            return nil
        }
        return simulatorName
    }

    nonisolated private static func simulatorLastUsedDate(from plistDictionary: [String: Any]) -> Date? {
        for key in simulatorLastUsedKeys {
            guard let rawValue = plistDictionary[key] else {
                continue
            }
            if let parsedDate = parseDate(fromPlistValue: rawValue) {
                return parsedDate
            }
        }
        return nil
    }

    nonisolated private static func parseDate(fromPlistValue value: Any) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let stringValue = value as? String {
            let isoWithFraction = ISO8601DateFormatter()
            isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoWithFraction.date(from: stringValue) {
                return date
            }

            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]
            if let date = isoBasic.date(from: stringValue) {
                return date
            }
        }
        if let timestamp = value as? TimeInterval, timestamp > 0 {
            let seconds = timestamp > 4_102_444_800 ? (timestamp / 1_000) : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = value as? NSNumber {
            let timestamp = number.doubleValue
            guard timestamp > 0 else { return nil }
            let seconds = timestamp > 4_102_444_800 ? (timestamp / 1_000) : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private func itemIndex(for itemID: String) -> Int? {
        items.firstIndex(where: { $0.id == itemID })
    }

    nonisolated private static func sortItems(_ items: [StorageLocationBrowserItem]) -> [StorageLocationBrowserItem] {
        items.sorted { lhs, rhs in
            let lhsBandRank = recencyRank(for: lhs.recencyBand)
            let rhsBandRank = recencyRank(for: rhs.recencyBand)
            if lhsBandRank != rhsBandRank {
                return lhsBandRank < rhsBandRank
            }

            if lhs.sizeBytes != rhs.sizeBytes {
                return lhs.sizeBytes > rhs.sizeBytes
            }

            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            if lhs.sortDate != rhs.sortDate {
                return lhs.sortDate > rhs.sortDate
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func recencyRank(for band: StorageItemRecencyBand) -> Int {
        switch band {
        case .year:
            return 0
        case .sixMonths:
            return 1
        case .month:
            return 2
        case .recent:
            return 3
        case .unknown:
            return 4
        }
    }

    nonisolated private static func makeSections(from items: [StorageLocationBrowserItem]) -> [StorageLocationBrowserSection] {
        let orderedBands: [StorageItemRecencyBand] = [
            .year,
            .sixMonths,
            .month,
            .recent,
            .unknown,
        ]

        return orderedBands.compactMap { band in
            let rank = recencyRank(for: band)
            let sectionItems = items.filter { recencyRank(for: $0.recencyBand) == rank }
            guard !sectionItems.isEmpty else {
                return nil
            }

            let totalBytes = sectionItems.reduce(into: Int64(0)) { partial, item in
                partial += item.sizeBytes
            }
            let itemLabel = sectionItems.count == 1 ? "1 item" : "\(sectionItems.count.formatted()) items"
            let detail = "\(itemLabel) • \(StorageViewModel.byteString(from: totalBytes))"

            return StorageLocationBrowserSection(
                band: band,
                title: sectionTitle(for: band),
                detail: detail,
                items: sectionItems
            )
        }
    }

    nonisolated private static func sectionTitle(for band: StorageItemRecencyBand) -> String {
        switch band {
        case .recent:
            return "Used in the last 30 days"
        case .month:
            return "Unused for 1 to 6 months"
        case .sixMonths:
            return "Unused for 6 to 12 months"
        case .year:
            return "Unused for over 1 year"
        case .unknown:
            return "Unknown last-used date"
        }
    }

    nonisolated private static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return fileSize(at: url)
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ]

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }

            totalSize += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }

        return totalSize
    }

    nonisolated private static func fileSize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
