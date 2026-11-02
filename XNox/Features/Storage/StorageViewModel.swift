import AppKit
import Combine
import Foundation

struct StorageLocation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let relativePath: String
    let cleanupNote: String
    let systemImage: String

    var pathLabel: String {
        "~/\(relativePath)"
    }
}

struct StorageLocationSnapshot: Identifiable, Hashable, Sendable {
    let location: StorageLocation
    let absolutePath: String
    let exists: Bool
    let bytes: Int64
    let fileCount: Int
    let scannedAt: Date
    let errorMessage: String?

    var id: String {
        location.id
    }

    var usageLabel: String {
        StorageViewModel.byteString(from: bytes)
    }

    var fileCountLabel: String {
        if fileCount == 1 {
            return "1 item"
        }
        return "\(fileCount) items"
    }
}

struct LocationScanProgress: Hashable, Sendable {
    let filesScanned: Int
    let bytesScanned: Int64
    let discoveredExists: Bool?
}

struct StorageScanResult: Sendable {
    let snapshot: StorageLocationSnapshot
    let browseItems: [StorageLocationBrowserItem]
}

struct StorageCleanupCelebrationEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let locationID: String
    let reclaimedBytes: Int64
}

struct StorageDeletionProgress: Hashable, Sendable {
    let label: String
    let completedUnitCount: Int
    let totalUnitCount: Int

    var fractionCompleted: Double {
        guard totalUnitCount > 0 else { return 0 }
        return min(1, max(0, Double(completedUnitCount) / Double(totalUnitCount)))
    }
}

@MainActor
final class StorageViewModel: ObservableObject {
    @Published private(set) var snapshots: [StorageLocationSnapshot]
    @Published private(set) var pendingLocationIDs: Set<String> = []
    @Published private(set) var scanProgressByLocationID: [String: LocationScanProgress] = [:]
    @Published private(set) var scannedLocationIDs: Set<String> = []
    @Published private(set) var hasCompletedScan = false
    @Published private(set) var lastCleanupCelebrationEvent: StorageCleanupCelebrationEvent?
    @Published private(set) var deletionProgress: StorageDeletionProgress?
    @Published var statusMessage = "Ready to scan iOS development storage."
    @Published var isRefreshing = false
    @Published var isDeleting = false

    private let activityCenter: GlobalActivityCenter
    private let historyRecorder: any OperationHistoryRecording
    private let locations: [StorageLocation]
    private let homeDirectory: URL
    private var browseCacheByLocationID: [String: [StorageLocationBrowserItem]] = [:]
    private var locationMutationRevisionByID: [String: Int] = [:]
    private var activeScanActivityID: UUID?
    nonisolated static let coreSimulatorDevicesLocationID = "core-simulator-devices"

    init(
        activityCenter: GlobalActivityCenter? = nil,
        historyRecorder: (any OperationHistoryRecording)? = nil,
        locations: [StorageLocation]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.activityCenter = activityCenter ?? GlobalActivityCenter()
        self.historyRecorder = historyRecorder ?? OperationHistoryRecorder.shared
        let resolvedLocations = locations ?? Self.defaultLocations
        self.locations = resolvedLocations
        self.homeDirectory = homeDirectory

        let initialScanTime = Date.now
        snapshots = resolvedLocations.map { location in
            StorageLocationSnapshot(
                location: location,
                absolutePath: homeDirectory
                    .appendingPathComponent(location.relativePath, isDirectory: true)
                    .path,
                exists: false,
                bytes: 0,
                fileCount: 0,
                scannedAt: initialScanTime,
                errorMessage: nil
            )
        }
    }

    var totalKnownBytes: Int64 {
        snapshots.reduce(into: 0) { partial, snapshot in
            partial += snapshot.bytes
        }
    }

    var liveTotalKnownBytes: Int64 {
        locations.reduce(into: 0) { partial, location in
            if let progress = scanProgressByLocationID[location.id] {
                partial += progress.bytesScanned
            } else if let snapshot = snapshots.first(where: { $0.id == location.id }) {
                partial += snapshot.bytes
            }
        }
    }

    var liveExistingLocationCount: Int {
        locations.reduce(into: 0) { count, location in
            if let progress = scanProgressByLocationID[location.id] {
                if progress.discoveredExists == true {
                    count += 1
                }
            } else if let snapshot = snapshots.first(where: { $0.id == location.id }), snapshot.exists {
                count += 1
            }
        }
    }

    var hasContentToDelete: Bool {
        snapshots.contains { $0.exists && $0.bytes > 0 }
    }

    var isScanInProgress: Bool {
        !pendingLocationIDs.isEmpty
    }

    var totalLocationCount: Int {
        locations.count
    }

    var scannedLocationCount: Int {
        max(0, totalLocationCount - pendingLocationIDs.count)
    }

    var scanProgressFraction: Double {
        guard totalLocationCount > 0 else { return 1 }
        return min(1, max(0, Double(scannedLocationCount) / Double(totalLocationCount)))
    }

    var scanProgressPercent: Int {
        Int((scanProgressFraction * 100).rounded())
    }

    func isLocationRefreshing(_ locationID: String) -> Bool {
        pendingLocationIDs.contains(locationID)
    }

    func scanProgress(for locationID: String) -> LocationScanProgress? {
        scanProgressByLocationID[locationID]
    }

    func cachedBrowseItems(for locationID: String) -> [StorageLocationBrowserItem] {
        browseCacheByLocationID[locationID] ?? []
    }

    func updateCachedBrowseItems(_ items: [StorageLocationBrowserItem], for locationID: String) {
        browseCacheByLocationID[locationID] = items
    }

    func applyBrowsedItems(_ items: [StorageLocationBrowserItem], for locationID: String) {
        bumpMutationRevision(for: locationID)
        browseCacheByLocationID[locationID] = items
        guard let index = snapshots.firstIndex(where: { $0.id == locationID }) else { return }

        let currentSnapshot = snapshots[index]
        let bytes = items.reduce(into: Int64(0)) { partial, item in
            partial += item.sizeBytes
        }

        snapshots[index] = StorageLocationSnapshot(
            location: currentSnapshot.location,
            absolutePath: currentSnapshot.absolutePath,
            exists: currentSnapshot.exists,
            bytes: bytes,
            fileCount: items.count,
            scannedAt: .now,
            errorMessage: nil
        )
        scannedLocationIDs.insert(locationID)
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        statusMessage = "Scanning iOS development folders..."
        let activityID = activityCenter.begin(
            title: "Scanning storage locations",
            detail: "0/\(locations.count)",
            source: "Storage"
        )
        activeScanActivityID = activityID
        pendingLocationIDs = Set(locations.map(\.id))
        scannedLocationIDs = []
        scanProgressByLocationID = Dictionary(
            uniqueKeysWithValues: locations.map {
                ($0.id, LocationScanProgress(filesScanned: 0, bytesScanned: 0, discoveredExists: nil))
            }
        )
        defer {
            activityCenter.finish(id: activityID)
            if activeScanActivityID == activityID {
                activeScanActivityID = nil
            }
            pendingLocationIDs = []
            scanProgressByLocationID = [:]
            isRefreshing = false
        }

        let locations = self.locations
        let homeDirectory = self.homeDirectory
        let revisionByLocationID = locationMutationRevisionByID

        await withTaskGroup(of: StorageScanResult.self) { group in
            for location in locations {
                group.addTask(priority: .utility) {
                    let fileManager = FileManager.default
                    return Self.scan(
                        location: location,
                        homeDirectory: homeDirectory,
                        fileManager: fileManager
                    ) { progress in
                        Task { @MainActor [weak self] in
                            self?.scanProgressByLocationID[location.id] = progress
                        }
                    }
                }
            }

            for await result in group {
                let snapshot = result.snapshot
                let shouldApply = locationMutationRevisionByID[snapshot.id, default: 0] == revisionByLocationID[snapshot.id, default: 0]
                if shouldApply {
                    if let existingIndex = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
                        snapshots[existingIndex] = snapshot
                    } else {
                        snapshots.append(snapshot)
                    }
                    browseCacheByLocationID[snapshot.id] = result.browseItems
                }
                pendingLocationIDs.remove(snapshot.id)
                scannedLocationIDs.insert(snapshot.id)
                scanProgressByLocationID.removeValue(forKey: snapshot.id)

                let scannedCount = locations.count - pendingLocationIDs.count
                statusMessage = "Scanning iOS development folders (\(scannedCount)/\(locations.count))..."
                activityCenter.update(
                    id: activityID,
                    detail: "\(scannedCount)/\(locations.count) • Reclaimable \(Self.byteString(from: liveTotalKnownBytes))"
                )
            }
        }

        hasCompletedScan = true
        statusMessage = "Scanned \(locations.count) locations. Reclaimable space: \(Self.byteString(from: totalKnownBytes))."
    }

    func refresh(locationID: String) async {
        guard let location = locations.first(where: { $0.id == locationID }) else { return }
        guard !pendingLocationIDs.contains(locationID) else { return }

        pendingLocationIDs.insert(locationID)
        scanProgressByLocationID[locationID] = LocationScanProgress(
            filesScanned: 0,
            bytesScanned: 0,
            discoveredExists: nil
        )
        statusMessage = "Refreshing \(location.title) in the background..."

        defer {
            pendingLocationIDs.remove(locationID)
            scanProgressByLocationID.removeValue(forKey: locationID)
        }

        let homeDirectory = self.homeDirectory
        let expectedRevision = locationMutationRevisionByID[locationID, default: 0]
        let result = await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            return Self.scan(
                location: location,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            ) { progress in
                Task { @MainActor [weak self] in
                    self?.scanProgressByLocationID[location.id] = progress
                }
            }
        }.value
        let snapshot = result.snapshot

        if locationMutationRevisionByID[locationID, default: 0] == expectedRevision {
            if let existingIndex = snapshots.firstIndex(where: { $0.id == locationID }) {
                snapshots[existingIndex] = snapshot
            } else {
                snapshots.append(snapshot)
            }
            browseCacheByLocationID[locationID] = result.browseItems
        }
        scannedLocationIDs.insert(locationID)

        hasCompletedScan = true
        statusMessage = "Updated \(location.title). Reclaimable space: \(Self.byteString(from: totalKnownBytes))."
    }

    func delete(locationID: String) async {
        guard !isDeleting else { return }
        guard let location = locations.first(where: { $0.id == locationID }) else { return }

        isDeleting = true
        statusMessage = "Cleaning \(location.title)..."
        deletionProgress = StorageDeletionProgress(label: "Cleaning \(location.title)", completedUnitCount: 0, totalUnitCount: 1)
        defer {
            isDeleting = false
            deletionProgress = nil
        }
        let historyID = historyRecorder.start(
            feature: "Storage",
            command: "clean-storage \(location.relativePath)",
            summary: "Cleaning \(location.title)."
        )

        let homeDirectory = self.homeDirectory
        let deletionGuard = DeletionGuard.storage(home: homeDirectory)

        do {
            let reclaimedBytes = try await Task.detached(priority: .userInitiated) { () -> Int64 in
                let fileManager = FileManager.default
                let targetURL = Self.absoluteURL(for: location, homeDirectory: homeDirectory)
                var freed: Int64 = 0
                do {
                    try Self.clearContents(at: targetURL, fileManager: fileManager, deletionGuard: deletionGuard, freed: &freed) { completed, total in
                        Task { @MainActor [weak self] in
                            self?.deletionProgress = StorageDeletionProgress(
                                label: "Cleaning \(location.title)",
                                completedUnitCount: completed,
                                totalUnitCount: max(total, 1)
                            )
                        }
                    }
                } catch {
                    throw StorageDeleteFailure(freedBytes: freed, underlying: error)
                }
                return freed
            }.value

            statusMessage = "Cleaned \(location.title). Freed approximately \(Self.byteString(from: reclaimedBytes))."
            applyDeletionResult(for: locationID)
            lastCleanupCelebrationEvent = StorageCleanupCelebrationEvent(
                id: UUID(),
                locationID: locationID,
                reclaimedBytes: reclaimedBytes
            )
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            statusMessage = StorageDeleteFailure.unwrap(error).summary("clean \(location.title)", cancelled: Task.isCancelled)
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    func deleteAll() async {
        guard !isDeleting else { return }

        let existingLocations = snapshots
            .filter(\.exists)
            .map(\.location)

        guard !existingLocations.isEmpty else {
            statusMessage = "No iOS storage folders were found on this Mac."
            return
        }

        isDeleting = true
        statusMessage = "Cleaning all iOS development storage folders..."
        deletionProgress = StorageDeletionProgress(
            label: "Cleaning all storage locations",
            completedUnitCount: 0,
            totalUnitCount: max(existingLocations.count, 1)
        )
        defer {
            isDeleting = false
            deletionProgress = nil
        }
        let historyID = historyRecorder.start(
            feature: "Storage",
            command: "clean-all-storage",
            summary: "Cleaning all configured storage locations."
        )

        let homeDirectory = self.homeDirectory
        let deletionGuard = DeletionGuard.storage(home: homeDirectory)

        do {
            let reclaimedBytes = try await Task.detached(priority: .userInitiated) { () -> Int64 in
                let fileManager = FileManager.default
                var totalReclaimedBytes: Int64 = 0
                let totalLocations = existingLocations.count
                for (index, location) in existingLocations.enumerated() {
                    let url = Self.absoluteURL(for: location, homeDirectory: homeDirectory)
                    do {
                        try Self.clearContents(at: url, fileManager: fileManager, deletionGuard: deletionGuard, freed: &totalReclaimedBytes)
                    } catch {
                        throw StorageDeleteFailure(freedBytes: totalReclaimedBytes, underlying: error)
                    }
                    let completed = index + 1
                    Task { @MainActor [weak self] in
                        self?.deletionProgress = StorageDeletionProgress(
                            label: "Cleaning all storage locations",
                            completedUnitCount: completed,
                            totalUnitCount: max(totalLocations, 1)
                        )
                    }
                }
                return totalReclaimedBytes
            }.value

            statusMessage = "Cleanup completed. Freed approximately \(Self.byteString(from: reclaimedBytes))."
            for location in existingLocations {
                applyDeletionResult(for: location.id)
            }
            historyRecorder.complete(
                id: historyID,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            statusMessage = StorageDeleteFailure.unwrap(error).summary("clean all storage locations", cancelled: Task.isCancelled)
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    func openInFinder(locationID: String) {
        guard let location = locations.first(where: { $0.id == locationID }) else { return }

        let targetURL = Self.absoluteURL(for: location, homeDirectory: homeDirectory)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: targetURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        } else {
            NSWorkspace.shared.open(targetURL.deletingLastPathComponent())
        }
    }

    nonisolated static func byteString(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, bytes))
    }

    func hasScannedLocation(_ locationID: String) -> Bool {
        scannedLocationIDs.contains(locationID)
    }

    private func applyDeletionResult(for locationID: String) {
        bumpMutationRevision(for: locationID)
        guard let index = snapshots.firstIndex(where: { $0.id == locationID }) else { return }
        let currentSnapshot = snapshots[index]
        let fileManager = FileManager.default
        let stillExists = fileManager.fileExists(atPath: currentSnapshot.absolutePath)

        snapshots[index] = StorageLocationSnapshot(
            location: currentSnapshot.location,
            absolutePath: currentSnapshot.absolutePath,
            exists: stillExists,
            bytes: 0,
            fileCount: 0,
            scannedAt: .now,
            errorMessage: nil
        )
        browseCacheByLocationID[locationID] = []
        scannedLocationIDs.insert(locationID)
    }

    private func bumpMutationRevision(for locationID: String) {
        locationMutationRevisionByID[locationID, default: 0] += 1
    }

    nonisolated static var defaultLocations: [StorageLocation] {
        [
            StorageLocation(
                id: "derived-data",
                title: "DerivedData",
                subtitle: "Build intermediates, indexes, and module caches produced by Xcode builds.",
                relativePath: "Library/Developer/Xcode/DerivedData",
                cleanupNote: "Safe to clear. Xcode will regenerate these files.",
                systemImage: "hammer"
            ),
            StorageLocation(
                id: "archives",
                title: "Archives",
                subtitle: "Archive bundles created for TestFlight and App Store builds.",
                relativePath: "Library/Developer/Xcode/Archives",
                cleanupNote: "Delete old archives only if you no longer need to re-export them.",
                systemImage: "archivebox"
            ),
            StorageLocation(
                id: "core-simulator-devices",
                title: "CoreSimulator Devices",
                subtitle: "Installed apps, simulator runtimes, and app containers for local testing.",
                relativePath: "Library/Developer/CoreSimulator/Devices",
                cleanupNote: "Deleting will remove simulator app data and may reset simulator state.",
                systemImage: "iphone.gen3"
            ),
            StorageLocation(
                id: "device-support",
                title: "iOS DeviceSupport",
                subtitle: "Symbols and support files generated when connecting physical iOS devices.",
                relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
                cleanupNote: "Safe to clear. Files are downloaded again when needed.",
                systemImage: "externaldrive.connected.to.line.below"
            ),
            StorageLocation(
                id: "xcode-cache",
                title: "Xcode Cache",
                subtitle: "Global Xcode cache files shared across projects.",
                relativePath: "Library/Caches/com.apple.dt.Xcode",
                cleanupNote: "Safe to clear. Startup and indexing may be slower until cache warms.",
                systemImage: "internaldrive"
            ),
        ]
    }

    nonisolated private static func absoluteURL(for location: StorageLocation, homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(location.relativePath, isDirectory: true)
    }

    nonisolated private static func scan(
        location: StorageLocation,
        homeDirectory: URL,
        fileManager: FileManager,
        onProgress: (@Sendable (LocationScanProgress) -> Void)? = nil
    ) -> StorageScanResult {
        let directoryURL = absoluteURL(for: location, homeDirectory: homeDirectory)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            onProgress?(LocationScanProgress(filesScanned: 0, bytesScanned: 0, discoveredExists: false))
            return StorageScanResult(
                snapshot: StorageLocationSnapshot(
                    location: location,
                    absolutePath: directoryURL.path,
                    exists: false,
                    bytes: 0,
                    fileCount: 0,
                    scannedAt: .now,
                    errorMessage: nil
                ),
                browseItems: []
            )
        }

        if !isDirectory.boolValue {
            let fileSize = (try? StorageShell.allocatedSize(at: directoryURL)) ?? fileSize(at: directoryURL)
            onProgress?(LocationScanProgress(filesScanned: 1, bytesScanned: fileSize, discoveredExists: true))
            let resourceValues = try? directoryURL.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey]
            )
            let modifiedAt = resourceValues?.contentModificationDate
            let singleItem = StorageLocationBrowserItem(
                id: directoryURL.path,
                name: directoryURL.lastPathComponent,
                absolutePath: directoryURL.path,
                isDirectory: false,
                sizeBytes: fileSize,
                modifiedAt: modifiedAt,
                createdAt: resourceValues?.creationDate,
                lastUsedAt: modifiedAt
            )

            return StorageScanResult(
                snapshot: StorageLocationSnapshot(
                    location: location,
                    absolutePath: directoryURL.path,
                    exists: true,
                    bytes: fileSize,
                    fileCount: 1,
                    scannedAt: .now,
                    errorMessage: nil
                ),
                browseItems: [singleItem]
            )
        }

        let topLevelKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .nameKey,
            .creationDateKey,
            .contentModificationDateKey,
        ]
        var capturedError: String?
        var topLevelEntriesByName: [String: (url: URL, isDirectory: Bool, createdAt: Date?, modifiedAt: Date?)] = [:]
        onProgress?(LocationScanProgress(filesScanned: 0, bytesScanned: 0, discoveredExists: true))

        do {
            let topLevelEntries = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(topLevelKeys),
                options: []
            )

            for entry in topLevelEntries {
                let values = try? entry.resourceValues(forKeys: topLevelKeys)
                let name = values?.name ?? entry.lastPathComponent
                topLevelEntriesByName[name] = (
                    url: entry,
                    isDirectory: values?.isDirectory == true,
                    createdAt: values?.creationDate,
                    modifiedAt: values?.contentModificationDate
                )
            }
        } catch {
            capturedError = error.localizedDescription
        }

        var totalBytes: Int64 = 0
        var totalItems = 0
        var topLevelBytesByName: [String: Int64] = [:]
        let sortedTopLevelNames = topLevelEntriesByName.keys.sorted()

        for topLevelName in sortedTopLevelNames {
            guard let entry = topLevelEntriesByName[topLevelName] else { continue }

            do {
                let entryBytes = try StorageShell.allocatedSize(at: entry.url)
                totalItems += 1
                totalBytes += entryBytes
                topLevelBytesByName[topLevelName] = entryBytes

                onProgress?(
                    LocationScanProgress(
                        filesScanned: totalItems,
                        bytesScanned: totalBytes,
                        discoveredExists: true
                    )
                )
            } catch {
                if capturedError == nil {
                    capturedError = error.localizedDescription
                }
            }
        }

        onProgress?(
            LocationScanProgress(
                filesScanned: totalItems,
                bytesScanned: totalBytes,
                discoveredExists: true
            )
        )
        let cachedItems = buildBrowseItems(
            locationID: location.id,
            topLevelEntriesByName: topLevelEntriesByName,
            topLevelBytesByName: topLevelBytesByName,
            fileManager: fileManager
        )

        return StorageScanResult(
                snapshot: StorageLocationSnapshot(
                    location: location,
                    absolutePath: directoryURL.path,
                    exists: true,
                    bytes: totalBytes,
                    fileCount: totalItems,
                    scannedAt: .now,
                    errorMessage: capturedError
                ),
            browseItems: cachedItems
        )
    }

    nonisolated private static func buildBrowseItems(
        locationID: String,
        topLevelEntriesByName: [String: (url: URL, isDirectory: Bool, createdAt: Date?, modifiedAt: Date?)],
        topLevelBytesByName: [String: Int64],
        fileManager: FileManager
    ) -> [StorageLocationBrowserItem] {
        topLevelEntriesByName.values.map { entry in
            let baseName = entry.url.lastPathComponent
            let simulatorMetadata = coreSimulatorMetadata(
                for: entry.url,
                fallbackName: baseName,
                isDirectory: entry.isDirectory,
                locationID: locationID,
                fileManager: fileManager
            )
            let displayName = simulatorMetadata?.displayName ?? baseName
            let lastUsedAt = simulatorMetadata?.lastUsedAt ?? entry.modifiedAt
            return StorageLocationBrowserItem(
                id: entry.url.path,
                name: displayName,
                absolutePath: entry.url.path,
                isDirectory: entry.isDirectory,
                sizeBytes: topLevelBytesByName[baseName, default: 0],
                modifiedAt: entry.modifiedAt,
                createdAt: entry.createdAt,
                lastUsedAt: lastUsedAt
            )
        }
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
        for key in SimctlParser.lastUsedKeys {
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

    nonisolated private static func clearContents(
        at url: URL,
        fileManager: FileManager,
        deletionGuard: DeletionGuard,
        freed: inout Int64,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            onProgress?(1, 1)
            return
        }

        if !isDirectory.boolValue {
            let size = fileSize(at: url)
            try StorageShell.removeItem(at: url, guard: deletionGuard)
            freed += size
            onProgress?(1, 1)
            return
        }

        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )

        let totalChildren = max(children.count, 1)
        if children.isEmpty {
            onProgress?(1, 1)
        }

        for (index, child) in children.enumerated() {
            let size = (try? StorageShell.allocatedSize(at: child)) ?? directorySize(at: child, fileManager: fileManager)
            try StorageShell.removeItem(at: child, guard: deletionGuard)
            freed += size
            onProgress?(index + 1, totalChildren)
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

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ]

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var totalBytes: Int64 = 0
        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                continue
            }

            totalBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return totalBytes
    }

    nonisolated private static func fileSize(at url: URL) -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ]

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
