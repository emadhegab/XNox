import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var splitViewVisibility: NavigationSplitViewVisibility = .all
    @Published var selectedSection: AppSection?
    @Published var isSettingsModalPresented = false

    let activityCenter: GlobalActivityCenter
    let xcodeManagerViewModel: XcodeManagerViewModel
    let storageViewModel: StorageViewModel
    let settings: AppSettings

    init(
        activityCenter: GlobalActivityCenter? = nil,
        settings: AppSettings? = nil
    ) {
        let resolvedSettings = settings ?? .shared
        let sharedActivityCenter = activityCenter ?? GlobalActivityCenter()
        self.activityCenter = sharedActivityCenter
        self.xcodeManagerViewModel = XcodeManagerViewModel(activityCenter: sharedActivityCenter)
        self.storageViewModel = StorageViewModel(activityCenter: sharedActivityCenter)
        self.settings = resolvedSettings

        if resolvedSettings.reopenLastSectionOnLaunch,
           let persistedSection = AppSection(rawValue: resolvedSettings.lastSelectedSection) {
            self.selectedSection = persistedSection
        } else if let defaultSection = AppSection(rawValue: resolvedSettings.defaultSectionOnLaunch) {
            self.selectedSection = defaultSection
        } else {
            self.selectedSection = .dashboard
        }
    }

    func presentSettingsModal() {
        isSettingsModalPresented = true
    }
}
