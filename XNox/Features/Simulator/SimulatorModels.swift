import Foundation

struct SimulatorDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let udid: String
    let runtimeIdentifier: String
    let runtimeName: String
    let state: String
    let isAvailable: Bool
    let availabilityIssue: String?
    let deviceTypeIdentifier: String
    let lastUsedAt: Date?

    nonisolated init(
        name: String,
        udid: String,
        runtimeIdentifier: String,
        runtimeName: String,
        state: String,
        isAvailable: Bool,
        availabilityIssue: String? = nil,
        deviceTypeIdentifier: String,
        lastUsedAt: Date? = nil
    ) {
        id = udid
        self.name = name
        self.udid = udid
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeName = runtimeName
        self.state = state
        self.isAvailable = isAvailable
        self.availabilityIssue = availabilityIssue
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.lastUsedAt = lastUsedAt
    }

    nonisolated var isBooted: Bool {
        state.caseInsensitiveCompare("Booted") == .orderedSame
    }

    nonisolated var category: SimulatorDeviceCategory {
        let identifierSource = deviceTypeIdentifier.lowercased()
        if identifierSource.contains("iphone") { return .iPhone }
        if identifierSource.contains("ipad") { return .iPad }
        if identifierSource.contains("watch") { return .appleWatch }
        if identifierSource.contains("appletv") || identifierSource.contains("apple-tv") { return .appleTV }
        if identifierSource.contains("vision") { return .appleVision }
        if identifierSource.contains("ipod") { return .iPod }
        if identifierSource.contains("mac") { return .mac }

        // Fallback only when identifier is missing/unknown.
        let nameSource = name.lowercased()
        if nameSource.contains("iphone") { return .iPhone }
        if nameSource.contains("ipad") { return .iPad }
        if nameSource.contains("watch") { return .appleWatch }
        if nameSource.contains("appletv") || nameSource.contains("apple tv") || nameSource.contains("tv") { return .appleTV }
        if nameSource.contains("vision") { return .appleVision }
        if nameSource.contains("ipod") { return .iPod }
        if nameSource.contains("mac") { return .mac }
        return .other
    }
}

enum SimulatorDeviceCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case iPhone
    case iPad
    case appleWatch
    case appleTV
    case appleVision
    case iPod
    case mac
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhone:
            return "iPhone"
        case .iPad:
            return "iPad"
        case .appleWatch:
            return "Apple Watch"
        case .appleTV:
            return "Apple TV"
        case .appleVision:
            return "Apple Vision"
        case .iPod:
            return "iPod"
        case .mac:
            return "Mac"
        case .other:
            return "Other"
        }
    }
}

struct SimulatorRuntime: Identifiable, Hashable, Sendable {
    let id: String
    let identifier: String
    let name: String
    let version: String?
    let isAvailable: Bool

    nonisolated init(identifier: String, name: String, version: String?, isAvailable: Bool) {
        id = identifier
        self.identifier = identifier
        self.name = name
        self.version = version
        self.isAvailable = isAvailable
    }
}

struct SimulatorDeviceType: Identifiable, Hashable, Sendable {
    let id: String
    let identifier: String
    let name: String

    nonisolated init(identifier: String, name: String) {
        id = identifier
        self.identifier = identifier
        self.name = name
    }
}

enum SimulatorStatusBarNetwork: String, CaseIterable, Identifiable {
    case wifi
    case lte
    case fourG = "4g"
    case fiveG = "5g"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .lte:
            return "LTE"
        case .fourG:
            return "4G"
        case .fiveG:
            return "5G"
        }
    }
}

enum SimulatorStatusBarBatteryState: String, CaseIterable, Identifiable {
    case charging
    case charged

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct SimulatorStatusBarOverrideConfig: Sendable {
    let time: String
    let network: SimulatorStatusBarNetwork
    let wifiBars: Int
    let cellularBars: Int
    let batteryState: SimulatorStatusBarBatteryState
    let batteryLevel: Int
}

struct SimulatorCatalog: Sendable {
    let simulators: [SimulatorDevice]
    let runtimes: [SimulatorRuntime]
    let deviceTypes: [SimulatorDeviceType]
    let warnings: [String]
}

enum SimulatorControlError: LocalizedError {
    case invalidJSON(String)
    case noSimulatorSelected
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case let .invalidJSON(message):
            return "Unable to parse simulator response: \(message)"
        case .noSimulatorSelected:
            return "Select a simulator first."
        case let .invalidInput(message):
            return message
        }
    }
}
