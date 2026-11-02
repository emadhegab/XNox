import Combine
import SwiftUI

/// App-wide state: selected sidebar section, settings, and the shared Storage view model.
@MainActor
final class AppState: ObservableObject {
    @Published var splitViewVisibility: NavigationSplitViewVisibility = .all
    @Published var selectedSection: AppSection?
    @Published var isSettingsModalPresented = false

    let activityCenter: GlobalActivityCenter
    let storageViewModel: StorageViewModel
    let settings: AppSettings

    init(
        activityCenter: GlobalActivityCenter? = nil,
        settings: AppSettings? = nil
    ) {
        let resolvedSettings = settings ?? .shared
        let sharedActivityCenter = activityCenter ?? GlobalActivityCenter()
        self.activityCenter = sharedActivityCenter
        self.storageViewModel = StorageViewModel(activityCenter: sharedActivityCenter)
        self.settings = resolvedSettings

        if resolvedSettings.reopenLastSectionOnLaunch,
           let persistedSection = AppSection(rawValue: resolvedSettings.lastSelectedSection) {
            self.selectedSection = persistedSection
        } else if let defaultSection = AppSection(rawValue: resolvedSettings.defaultSectionOnLaunch) {
            self.selectedSection = defaultSection
        } else {
            self.selectedSection = .storage
        }
    }

    func presentSettingsModal() {
        isSettingsModalPresented = true
    }
}
