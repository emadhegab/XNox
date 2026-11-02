import Foundation
import Testing
@testable import XNox

@MainActor
struct LicenseServiceTests {
    @Test func activateLicensePersistsPayloadInUserDefaults() async throws {
        let suiteName = "LicenseServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secretStore = MockSecretStore()
        let entitlement = makeEntitlement()
        let service = LicenseService(
            secretStore: secretStore,
            validator: MockLicenseValidator(activateResult: .success(entitlement), refreshResult: .success(entitlement)),
            defaults: defaults,
            now: { entitlement.lastValidatedAt }
        )

        await service.activateLicense("VALID-KEY")

        #expect(service.isProUnlocked)
        #expect(defaults.string(forKey: "license.storedPayload")?.isEmpty == false)
        #expect(secretStore.savedValues.isEmpty)
        #expect(secretStore.deletedKeys == [.licensePayload])
    }

    @Test func bootstrapMigratesLegacyKeychainPayloadIntoUserDefaults() async throws {
        let suiteName = "LicenseServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stored = StoredLicense(key: "OLD-KEY", entitlement: makeEntitlement())
        let payload = try encode(stored)
        let secretStore = MockSecretStore(readValues: [.licensePayload: payload])
        let service = LicenseService(
            secretStore: secretStore,
            validator: MockLicenseValidator(
                activateResult: .success(stored.entitlement),
                refreshResult: .failure(LicenseValidationError.serverError(message: "offline"))
            ),
            defaults: defaults,
            now: { stored.entitlement.lastValidatedAt }
        )

        await service.bootstrap()

        #expect(service.isProUnlocked)
        #expect(defaults.string(forKey: "license.storedPayload") == payload)
        #expect(secretStore.deletedKeys.contains(.licensePayload))
    }
    private func makeEntitlement() -> LicenseEntitlement {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        return LicenseEntitlement(
            plan: .proLifetime,
            expiresAt: nil,
            activatedAt: now,
            lastValidatedAt: now
        )
    }

    private func encode(_ stored: StoredLicense) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(stored)
        return String(decoding: data, as: UTF8.self)
    }
}

private final class MockSecretStore: SecretStoring {
    var readValues: [SecretKey: String]
    var savedValues: [SecretKey: String] = [:]
    var deletedKeys: [SecretKey] = []

    init(readValues: [SecretKey: String] = [:]) {
        self.readValues = readValues
    }

    func save(_ value: String, for key: SecretKey) throws {
        savedValues[key] = value
        readValues[key] = value
    }

    func read(_ key: SecretKey) throws -> String? {
        readValues[key]
    }

    func delete(_ key: SecretKey) throws {
        deletedKeys.append(key)
        readValues.removeValue(forKey: key)
    }
}

private struct MockLicenseValidator: LicenseValidating {
    let activateResult: Result<LicenseEntitlement, Error>
    let refreshResult: Result<LicenseEntitlement, Error>

    func activate(licenseKey: String, deviceID: String) async throws -> LicenseEntitlement {
        try activateResult.get()
    }

    func refresh(licenseKey: String, deviceID: String) async throws -> LicenseEntitlement {
        try refreshResult.get()
    }

    func migrateLegacyEntitlement(deviceID: String, evidence: LegacyMigrationEvidence) async throws -> LicenseEntitlement? {
        nil
    }
}
