import Combine
import Foundation

/// The appearance choices offered in Settings.
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

/// User preferences, backed by `UserDefaults`. Each property writes through when it changes.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings(defaults: .standard)

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

    @Published var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays) }
    }

    private let defaults: UserDefaults

    /// Internal so tests can inject a throwaway `UserDefaults` suite.
    init(defaults: UserDefaults) {
        self.defaults = defaults

        lastSelectedSection = defaults.string(forKey: Keys.lastSelectedSection) ?? AppSection.storage.rawValue
        // Installs that persisted a removed section (e.g. "xcodes") fall back to Storage.
        let persistedDefault = defaults.string(forKey: Keys.defaultSectionOnLaunch) ?? AppSection.storage.rawValue
        defaultSectionOnLaunch = AppSection(rawValue: persistedDefault) == nil ? AppSection.storage.rawValue : persistedDefault
        reopenLastSectionOnLaunch = defaults.object(forKey: Keys.reopenLastSectionOnLaunch) as? Bool ?? true

        let launchAtLoginDefault = LaunchAtLoginManager.isEnabled
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? launchAtLoginDefault

        historyRetentionDays = defaults.object(forKey: Keys.historyRetentionDays) as? Int ?? 30
    }

    /// Remembers the last open sidebar section so it can be reopened on launch.
    func persistLastSelectedSection(_ rawValue: String) {
        guard lastSelectedSection != rawValue else { return }
        lastSelectedSection = rawValue
        defaults.set(rawValue, forKey: Keys.lastSelectedSection)
    }

    /// Restores section, history retention and appearance to their defaults. Launch-at-login is not changed.
    func resetToDefaults() {
        persistLastSelectedSection(AppSection.storage.rawValue)
        defaultSectionOnLaunch = AppSection.storage.rawValue
        reopenLastSectionOnLaunch = true
        historyRetentionDays = 30
        defaults.set(AppAppearanceMode.system.rawValue, forKey: Keys.appearanceMode)
    }
}

/// `UserDefaults` keys for settings. Shared so the history store can read the retention days.
enum AppSettingsKeys {
    static let lastSelectedSection = "settings.lastSelectedSection"
    static let defaultSectionOnLaunch = "settings.defaultSectionOnLaunch"
    static let reopenLastSectionOnLaunch = "settings.reopenLastSectionOnLaunch"
    static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
    static let historyRetentionDays = "settings.historyRetentionDays"
    static let appearanceMode = "settings.appearanceMode"
}

private enum Keys {
    static let lastSelectedSection = AppSettingsKeys.lastSelectedSection
    static let defaultSectionOnLaunch = AppSettingsKeys.defaultSectionOnLaunch
    static let reopenLastSectionOnLaunch = AppSettingsKeys.reopenLastSectionOnLaunch
    static let launchAtLoginEnabled = AppSettingsKeys.launchAtLoginEnabled
    static let historyRetentionDays = AppSettingsKeys.historyRetentionDays
    static let appearanceMode = AppSettingsKeys.appearanceMode
}
