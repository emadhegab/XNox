import Combine
import Foundation

@MainActor
final class LicenseService: ObservableObject {
    @Published private(set) var state: LicenseState = .free
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    @Published var lastErrorMessage: String?

    private let secretStore: SecretStoring
    private let validator: LicenseValidating
    private let defaults: UserDefaults
    private let now: () -> Date
    private let offlineGraceDays: Int
    private let initialLegacySignalSnapshot: String?

    private static let installationIDKey = "license.installationID"
    private static let legacyMigrationCompletedKey = "license.legacyMigrationCompleted"
    private static let legacyMigrationLastAttemptAtKey = "license.legacyMigrationLastAttemptAt"
    private static let legacyMigrationRetryIntervalHours = 24
    private static let legacyAutoProvisioningKey = "LEGACY-AUTO-PROVISIONED"
    private static let legacyLocalProvisioningKey = "LEGACY-LOCAL-MIGRATION"
    private static let legacySignalSnapshotKey = "license.legacySignalSnapshot"
    private static let legacyServerSyncCompletedKey = "license.legacyServerSyncCompleted"
    private static let legacyLocalEligibilityWindowClosedKey = "license.legacyLocalEligibilityWindowClosed"
    private static let storedLicensePayloadKey = "license.storedPayload"

    init(
        secretStore: SecretStoring? = nil,
        validator: LicenseValidating? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        offlineGraceDays: Int = 14
    ) {
        self.secretStore = secretStore ?? KeychainSecretStore()
        self.validator = validator ?? RemoteLicenseValidator()
        self.defaults = defaults
        self.now = now
        self.offlineGraceDays = offlineGraceDays
        self.initialLegacySignalSnapshot = LicenseService.detectLegacySignal(in: defaults)
    }

    var isProUnlocked: Bool {
        state.isProUnlocked
    }

    var currentPlanTitle: String {
        state.currentPlanTitle
    }

    func bootstrap() async {
        reconcileLegacyState()

        if let stored = readStoredLicense() {
            apply(entitlement: stored.entitlement)
        }

        if !isProUnlocked || shouldAttemptLegacyServerSync {
            await runLegacyMigrationIfNeeded()
        }

        await refreshValidation()
    }

    func activateLicense(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastErrorMessage = "Enter a license key."
            return
        }

        setBusy(true)
        defer { setBusy(false) }

        do {
            let entitlement = try await validator.activate(licenseKey: key, deviceID: installationID)
            try persistLicense(key: key, entitlement: entitlement)
            apply(entitlement: entitlement)
            statusMessage = entitlement.plan.isLifetime ? "Lifetime license is active." : "License activated."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func deactivateLicense() {
        do {
            defaults.removeObject(forKey: Self.storedLicensePayloadKey)
            try secretStore.delete(.licensePayload)
            state = .free
            statusMessage = "License removed. Free mode is active."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshValidation() async {
        guard let stored = readStoredLicense() else {
            state = .free
            return
        }

        if stored.key == Self.legacyAutoProvisioningKey || stored.key == Self.legacyLocalProvisioningKey {
            apply(entitlement: stored.entitlement)
            return
        }

        setBusy(true)
        defer { setBusy(false) }

        do {
            let entitlement = try await validator.refresh(licenseKey: stored.key, deviceID: installationID)
            try persistLicense(key: stored.key, entitlement: entitlement)
            apply(entitlement: entitlement)
            statusMessage = nil
            lastErrorMessage = nil
        } catch {
            handleRefreshFailure(error: error, stored: stored)
        }
    }

    private func handleRefreshFailure(error: Error, stored: StoredLicense) {
        if canUseOfflineGrace(with: stored.entitlement) {
            apply(entitlement: stored.entitlement)
            statusMessage = "Using cached license (offline grace mode)."
            lastErrorMessage = nil
            return
        }

        if case .some(.expired) = (error as? LicenseValidationError) {
            state = .expired(stored.entitlement)
        } else {
            state = .free
        }
        lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func runLegacyMigrationIfNeeded() async {
        if legacyMigrationCompleted {
            await syncLegacyEntitlementToServer()
            return
        }

        let didProvisionLocally = runLocalLegacyMigrationIfEligible()

        // Even after local grandfathering succeeds, sync with server so this device
        // receives a backend-backed legacy entitlement when possible.
        if didProvisionLocally {
            await syncLegacyEntitlementToServer()
            return
        }

        guard shouldAttemptLegacyMigration else { return }

        setBusy(true)
        defer { setBusy(false) }

        defaults.set(now(), forKey: Self.legacyMigrationLastAttemptAtKey)

        do {
            let evidence = makeLegacyMigrationEvidence()
            if let entitlement = try await validator.migrateLegacyEntitlement(
                deviceID: installationID,
                evidence: evidence
            ) {
                try persistLicense(key: Self.legacyAutoProvisioningKey, entitlement: entitlement)
                apply(entitlement: entitlement)
                legacyMigrationCompleted = true
                legacyServerSyncCompleted = true
                statusMessage = "Legacy lifetime entitlement restored."
                lastErrorMessage = nil
            }
        } catch {
            // Keep app usable in free mode and retry later.
        }
    }

    private func runLocalLegacyMigrationIfEligible() -> Bool {
        guard !legacyLocalEligibilityWindowClosed else {
            return false
        }
        defer { legacyLocalEligibilityWindowClosed = true }

        guard let legacySignal = initialLegacySignalSnapshot else {
            return false
        }

        let entitlement = LicenseEntitlement(
            plan: .proLifetime,
            expiresAt: nil,
            activatedAt: now(),
            lastValidatedAt: now()
        )

        do {
            try persistLicense(key: Self.legacyLocalProvisioningKey, entitlement: entitlement)
            apply(entitlement: entitlement)
            legacyMigrationCompleted = true
            legacyServerSyncCompleted = false
            defaults.set(legacySignal, forKey: Self.legacySignalSnapshotKey)
            statusMessage = "Legacy user detected from local app data. Lifetime Pro unlocked."
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func syncLegacyEntitlementToServer() async {
        guard shouldAttemptLegacyServerSync else { return }

        setBusy(true)
        defer { setBusy(false) }

        defaults.set(now(), forKey: Self.legacyMigrationLastAttemptAtKey)

        do {
            let evidence = makeLegacyMigrationEvidence()
            if let entitlement = try await validator.migrateLegacyEntitlement(
                deviceID: installationID,
                evidence: evidence
            ) {
                try persistLicense(key: Self.legacyAutoProvisioningKey, entitlement: entitlement)
                apply(entitlement: entitlement)
                legacyServerSyncCompleted = true
                statusMessage = "Legacy entitlement synced with server."
                lastErrorMessage = nil
            }
        } catch {
            // Keep local entitlement active; server sync will retry later.
        }
    }

    private func canUseOfflineGrace(with entitlement: LicenseEntitlement) -> Bool {
        guard entitlement.plan.isPro else { return false }
        guard entitlement.expiresAt.map({ $0 > now() }) ?? true else { return false }
        guard let graceLimit = Calendar.current.date(byAdding: .day, value: offlineGraceDays, to: entitlement.lastValidatedAt) else {
            return false
        }
        return now() <= graceLimit
    }

    private func apply(entitlement: LicenseEntitlement) {
        if entitlement.plan.isPro, entitlement.expiresAt.map({ $0 > now() }) ?? true {
            state = .pro(entitlement)
            return
        }
        if entitlement.plan.isPro {
            state = .expired(entitlement)
            return
        }
        state = .free
    }

    private var shouldAttemptLegacyMigration: Bool {
        if let lastAttempt = defaults.object(forKey: Self.legacyMigrationLastAttemptAtKey) as? Date {
            guard let nextAttempt = Calendar.current.date(byAdding: .hour, value: Self.legacyMigrationRetryIntervalHours, to: lastAttempt) else {
                return true
            }
            return now() >= nextAttempt
        }
        return true
    }

    private var legacyMigrationCompleted: Bool {
        get { defaults.bool(forKey: Self.legacyMigrationCompletedKey) }
        set { defaults.set(newValue, forKey: Self.legacyMigrationCompletedKey) }
    }

    private var legacyServerSyncCompleted: Bool {
        get { defaults.bool(forKey: Self.legacyServerSyncCompletedKey) }
        set { defaults.set(newValue, forKey: Self.legacyServerSyncCompletedKey) }
    }

    private var shouldAttemptLegacyServerSync: Bool {
        guard readStoredLicense()?.key == Self.legacyLocalProvisioningKey else {
            return false
        }
        guard !legacyServerSyncCompleted else {
            return false
        }
        return true
    }

    private var legacyLocalEligibilityWindowClosed: Bool {
        get { defaults.bool(forKey: Self.legacyLocalEligibilityWindowClosedKey) }
        set { defaults.set(newValue, forKey: Self.legacyLocalEligibilityWindowClosedKey) }
    }

    private func reconcileLegacyState() {
        if legacyMigrationCompleted, readStoredLicense() == nil {
            legacyMigrationCompleted = false
            legacyServerSyncCompleted = false
        }
    }

    private func makeLegacyMigrationEvidence() -> LegacyMigrationEvidence {
        LegacyMigrationEvidence(
            currentAppVersion: currentAppVersion,
            knownLegacyVersions: ["1.0.0", "1.1.0"],
            hasStoredSettings: hasLegacySettingsFootprint,
            hasOperationHistory: legacyFileExists(named: "operation-history.json"),
            hasSigningProjects: legacyFileExists(named: "signing-projects.json")
        )
    }

    private var hasLegacySettingsFootprint: Bool {
        let legacyKeys: [String] = [
            AppSettingsKeys.lastSelectedSection,
            AppSettingsKeys.defaultSectionOnLaunch,
            AppSettingsKeys.reopenLastSectionOnLaunch,
            AppSettingsKeys.launchAtLoginEnabled,
            AppSettingsKeys.autoRefreshXcodesOnOpen,
            AppSettingsKeys.historyRetentionDays,
            AppSettingsKeys.confirmDestructiveActions,
            AppSettingsKeys.appearanceMode,
        ]
        return legacyKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private static func detectLegacySignal(in defaults: UserDefaults) -> String? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let persistedDomain = defaults.persistentDomain(forName: bundleID) else {
            return nil
        }

        if let selectedSection = persistedDomain[AppSettingsKeys.lastSelectedSection] as? String,
           !selectedSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "lastSelectedSection=\(selectedSection)"
        }

        if let defaultSection = persistedDomain[AppSettingsKeys.defaultSectionOnLaunch] as? String,
           !defaultSection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "defaultSectionOnLaunch=\(defaultSection)"
        }

        if persistedDomain[AppSettingsKeys.reopenLastSectionOnLaunch] != nil {
            return "reopenLastSectionOnLaunch=present"
        }

        return nil
    }

    private func legacyFileExists(named fileName: String) -> Bool {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let fallback = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XNox/\(fileName)", isDirectory: false)
        let fileURL = appSupport?
            .appendingPathComponent("XNox", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false) ?? fallback
        return fileManager.fileExists(atPath: fileURL.path)
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private func readStoredLicense() -> StoredLicense? {
        do {
            if let payload = defaults.string(forKey: Self.storedLicensePayloadKey) {
                return try decodeStoredLicense(from: payload)
            }

            guard let payload = try secretStore.read(.licensePayload) else {
                return nil
            }

            let storedLicense = try decodeStoredLicense(from: payload)
            defaults.set(payload, forKey: Self.storedLicensePayloadKey)

            // Best-effort cleanup so future launches no longer need Keychain access
            // just to recover the local license cache.
            try? secretStore.delete(.licensePayload)
            return storedLicense
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    private func persistLicense(key: String, entitlement: LicenseEntitlement) throws {
        let payload = StoredLicense(key: key, entitlement: entitlement)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw LicenseValidationError.malformedResponse
        }
        defaults.set(encoded, forKey: Self.storedLicensePayloadKey)

        // Best-effort cleanup in case an older build previously stored the license
        // in Keychain and would otherwise keep prompting on launch.
        try? secretStore.delete(.licensePayload)
    }

    private func decodeStoredLicense(from payload: String) throws -> StoredLicense {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredLicense.self, from: Data(payload.utf8))
    }

    private var installationID: String {
        if let existing = defaults.string(forKey: Self.installationIDKey) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Self.installationIDKey)
        return generated
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        if busy {
            statusMessage = nil
        }
    }
}
