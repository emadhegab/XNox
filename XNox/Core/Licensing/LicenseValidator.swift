import Foundation

protocol LicenseValidating {
    func activate(licenseKey: String, deviceID: String) async throws -> LicenseEntitlement
    func refresh(licenseKey: String, deviceID: String) async throws -> LicenseEntitlement
    func migrateLegacyEntitlement(deviceID: String, evidence: LegacyMigrationEvidence) async throws -> LicenseEntitlement?
}

enum LicenseValidationError: LocalizedError {
    case invalidKey
    case expired
    case serverError(message: String)
    case malformedResponse
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "The license key is invalid."
        case .expired:
            return "The license is expired."
        case let .serverError(message):
            return message
        case .malformedResponse:
            return "License server returned an unexpected response."
        case .configurationMissing:
            return "License server URL is not configured."
        }
    }
}

struct RemoteLicenseValidator: LicenseValidating {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL?
    private let now: () -> Date

    init(
        session: URLSession = .shared,
        baseURL: URL? = RemoteLicenseValidator.resolveBaseURL(),
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.baseURL = baseURL
        self.now = now

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func activate(licenseKey: String, deviceID: String) async throws -> LicenseEntitlement {
        if let local = debugLocalValidation(for: licenseKey) {
            return local
        }

        guard let baseURL else {
            throw LicenseValidationError.configurationMissing
        }

        return try await requestEntitlement(
            endpoint: baseURL.appendingPathComponent("activate"),
            licenseKey: licenseKey,
            deviceID: deviceID
        )
    }

    func refresh(licenseKey: String, deviceID: String) async throws -> LicenseEntitlement {
        if let local = debugLocalValidation(for: licenseKey) {
            return local
        }

        guard let baseURL else {
            throw LicenseValidationError.configurationMissing
        }

        return try await requestEntitlement(
            endpoint: baseURL.appendingPathComponent("validate"),
            licenseKey: licenseKey,
            deviceID: deviceID
        )
    }

    func migrateLegacyEntitlement(deviceID: String, evidence: LegacyMigrationEvidence) async throws -> LicenseEntitlement? {
        guard let baseURL else {
            throw LicenseValidationError.configurationMissing
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("migrate-legacy"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(LegacyMigrationRequest(deviceID: deviceID, evidence: evidence))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseValidationError.malformedResponse
        }

        if http.statusCode == 404 || http.statusCode == 409 {
            return nil
        }

        if http.statusCode >= 500 {
            throw LicenseValidationError.serverError(message: "License server is currently unavailable.")
        }

        let payload = try decoder.decode(ValidationResponse.self, from: data)
        guard payload.valid else {
            return nil
        }

        let plan = LicensePlan(rawValue: payload.plan ?? "") ?? .free
        guard plan == .proLifetime else {
            return nil
        }

        return LicenseEntitlement(
            plan: plan,
            expiresAt: nil,
            activatedAt: payload.activatedAt ?? now(),
            lastValidatedAt: now()
        )
    }

    private func requestEntitlement(endpoint: URL, licenseKey: String, deviceID: String) async throws -> LicenseEntitlement {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(ValidationRequest(key: licenseKey, deviceID: deviceID))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseValidationError.malformedResponse
        }

        if http.statusCode == 401 || http.statusCode == 404 {
            throw LicenseValidationError.invalidKey
        }

        if http.statusCode >= 500 {
            throw LicenseValidationError.serverError(message: "License server is currently unavailable.")
        }

        let payload = try decoder.decode(ValidationResponse.self, from: data)
        guard payload.valid else {
            if payload.reason == "expired" {
                throw LicenseValidationError.expired
            }
            throw LicenseValidationError.serverError(message: payload.message ?? "License validation failed.")
        }

        let plan = LicensePlan(rawValue: payload.plan ?? "") ?? .free
        let entitlement = LicenseEntitlement(
            plan: plan,
            expiresAt: payload.expiresAt,
            activatedAt: payload.activatedAt ?? now(),
            lastValidatedAt: now()
        )

        if !entitlement.plan.isPro {
            throw LicenseValidationError.invalidKey
        }

        return entitlement
    }

    #if DEBUG
    private func debugLocalValidation(for key: String) -> LicenseEntitlement? {
        let now = now()
        if key.hasPrefix("XNOX-LIFETIME-") {
            return LicenseEntitlement(plan: .proLifetime, expiresAt: nil, activatedAt: now, lastValidatedAt: now)
        }
        if key.hasPrefix("XNOX-YEARLY-") {
            return LicenseEntitlement(
                plan: .proYearly,
                expiresAt: Calendar.current.date(byAdding: .day, value: 365, to: now),
                activatedAt: now,
                lastValidatedAt: now
            )
        }
        if key.hasPrefix("XNOX-MONTHLY-") {
            return LicenseEntitlement(
                plan: .proMonthly,
                expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: now),
                activatedAt: now,
                lastValidatedAt: now
            )
        }
        return nil
    }
    #else
    private func debugLocalValidation(for key: String) -> LicenseEntitlement? {
        _ = key
        return nil
    }
    #endif

    private static func resolveBaseURL() -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "XNoxLicenseServerBaseURL") as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }
}

private struct ValidationRequest: Codable {
    let key: String
    let deviceID: String
}

private struct LegacyMigrationRequest: Codable {
    let deviceID: String
    let evidence: LegacyMigrationEvidence
}

private struct ValidationResponse: Codable {
    let valid: Bool
    let plan: String?
    let expiresAt: Date?
    let activatedAt: Date?
    let reason: String?
    let message: String?
}
