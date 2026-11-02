import Combine
import Foundation

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private(set) var lastSelectedSection: String

    @Published var defaultSectionOnLaunch: String {
        didSet { defaults.set(defaultSectionOnLaunch, forKey: Keys.defaultSectionOnLaunch) }
    }

    @Published var reopenLastSectionOnLaunch: Bool {
        didSet { defaults.set(reopenLastSectionOnLaunch, forKey: Keys.reopenLastSectionOnLaunch) }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    @Published var autoRefreshXcodesOnOpen: Bool {
        didSet { defaults.set(autoRefreshXcodesOnOpen, forKey: Keys.autoRefreshXcodesOnOpen) }
    }

    @Published var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) }
    }

    @Published var confirmDestructiveActions: Bool {
        didSet { defaults.set(confirmDestructiveActions, forKey: Keys.confirmDestructiveActions) }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        lastSelectedSection = defaults.string(forKey: Keys.lastSelectedSection) ?? AppSection.dashboard.rawValue
        defaultSectionOnLaunch = defaults.string(forKey: Keys.defaultSectionOnLaunch) ?? AppSection.dashboard.rawValue
        reopenLastSectionOnLaunch = defaults.object(forKey: Keys.reopenLastSectionOnLaunch) as? Bool ?? true

        let launchAtLoginDefault = LaunchAtLoginManager.isEnabled
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? launchAtLoginDefault

        autoRefreshXcodesOnOpen = defaults.object(forKey: Keys.autoRefreshXcodesOnOpen) as? Bool ?? true
        historyRetentionDays = defaults.object(forKey: Keys.historyRetentionDays) as? Int ?? 30
        confirmDestructiveActions = defaults.object(forKey: Keys.confirmDestructiveActions) as? Bool ?? true
    }

    func persistLastSelectedSection(_ rawValue: String) {
        guard lastSelectedSection != rawValue else { return }
        lastSelectedSection = rawValue
        defaults.set(rawValue, forKey: Keys.lastSelectedSection)
    }

    func resetToDefaults() {
        persistLastSelectedSection(AppSection.dashboard.rawValue)
        defaultSectionOnLaunch = AppSection.dashboard.rawValue
        reopenLastSectionOnLaunch = true
        autoRefreshXcodesOnOpen = true
        historyRetentionDays = 30
        confirmDestructiveActions = true
        defaults.set(AppAppearanceMode.system.rawValue, forKey: Keys.appearanceMode)
    }
}

enum AppSettingsKeys {
    static let lastSelectedSection = "settings.lastSelectedSection"
    static let defaultSectionOnLaunch = "settings.defaultSectionOnLaunch"
    static let reopenLastSectionOnLaunch = "settings.reopenLastSectionOnLaunch"
    static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
    static let autoRefreshXcodesOnOpen = "settings.autoRefreshXcodesOnOpen"
    static let historyRetentionDays = "settings.historyRetentionDays"
    static let confirmDestructiveActions = "settings.confirmDestructiveActions"
    static let appearanceMode = "settings.appearanceMode"
}

private enum Keys {
    static let lastSelectedSection = AppSettingsKeys.lastSelectedSection
    static let defaultSectionOnLaunch = AppSettingsKeys.defaultSectionOnLaunch
    static let reopenLastSectionOnLaunch = AppSettingsKeys.reopenLastSectionOnLaunch
    static let launchAtLoginEnabled = AppSettingsKeys.launchAtLoginEnabled
    static let autoRefreshXcodesOnOpen = AppSettingsKeys.autoRefreshXcodesOnOpen
    static let historyRetentionDays = AppSettingsKeys.historyRetentionDays
    static let confirmDestructiveActions = AppSettingsKeys.confirmDestructiveActions
    static let appearanceMode = AppSettingsKeys.appearanceMode
}
