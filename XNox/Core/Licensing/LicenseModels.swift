import Foundation

enum LicensePlan: String, Codable, CaseIterable {
    case free
    case proMonthly
    case proYearly
    case proLifetime

    var title: String {
        switch self {
        case .free:
            return "Free"
        case .proMonthly:
            return "Pro Monthly"
        case .proYearly:
            return "Pro Yearly"
        case .proLifetime:
            return "Pro Lifetime"
        }
    }

    var isPro: Bool {
        self != .free
    }

    var isLifetime: Bool {
        self == .proLifetime
    }
}

struct LicenseEntitlement: Codable, Equatable {
    let plan: LicensePlan
    let expiresAt: Date?
    let activatedAt: Date
    let lastValidatedAt: Date

    var isActive: Bool {
        guard plan.isPro else { return false }
        guard let expiresAt else { return true }
        return expiresAt > Date()
    }
}

struct StoredLicense: Codable {
    let key: String
    let entitlement: LicenseEntitlement
}

struct LegacyMigrationEvidence: Codable {
    let currentAppVersion: String
    let knownLegacyVersions: [String]
    let hasStoredSettings: Bool
    let hasOperationHistory: Bool
    let hasSigningProjects: Bool
}

enum LicenseState: Equatable {
    case free
    case pro(LicenseEntitlement)
    case expired(LicenseEntitlement)

    var isProUnlocked: Bool {
        switch self {
        case .pro:
            return true
        case .free, .expired:
            return false
        }
    }

    var currentPlanTitle: String {
        switch self {
        case .free:
            return LicensePlan.free.title
        case let .pro(entitlement), let .expired(entitlement):
            return entitlement.plan.title
        }
    }
}
