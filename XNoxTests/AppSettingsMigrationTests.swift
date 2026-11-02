import Foundation
import Testing
@testable import XNox

/// Covers installs that persisted the removed "xcodes" section.
@MainActor
struct AppSettingsMigrationTests {
    @Test
    func removedSectionFallsBackToDashboard() {
        let suite = "XNoxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("xcodes", forKey: AppSettingsKeys.defaultSectionOnLaunch)
        defaults.set("xcodes", forKey: AppSettingsKeys.lastSelectedSection)
        defaults.set(true, forKey: AppSettingsKeys.reopenLastSectionOnLaunch)

        let settings = AppSettings(defaults: defaults)
        let state = AppState(settings: settings)

        #expect(settings.defaultSectionOnLaunch == AppSection.dashboard.rawValue)
        #expect(state.selectedSection == .dashboard)
    }
}
