import Foundation
import Testing
@testable import XNox

/// Covers installs that persisted the removed "xcodes", "signing" and "devices" sections.
@MainActor
struct AppSettingsMigrationTests {
    @Test(arguments: ["xcodes", "signing", "devices"])
    func removedSectionFallsBackToDashboard(removed: String) {
        let suite = "XNoxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(removed, forKey: AppSettingsKeys.defaultSectionOnLaunch)
        defaults.set(removed, forKey: AppSettingsKeys.lastSelectedSection)
        defaults.set(true, forKey: AppSettingsKeys.reopenLastSectionOnLaunch)

        let settings = AppSettings(defaults: defaults)
        let state = AppState(settings: settings)

        #expect(settings.defaultSectionOnLaunch == AppSection.dashboard.rawValue)
        #expect(state.selectedSection == .dashboard)
    }
}
