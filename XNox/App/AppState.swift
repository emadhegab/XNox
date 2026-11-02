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
    let updateManager: AppUpdateManager
    let settings: AppSettings
    let licenseService: LicenseService

    init(
        activityCenter: GlobalActivityCenter? = nil,
        settings: AppSettings? = nil,
        updateManager: AppUpdateManager? = nil,
        licenseService: LicenseService? = nil
    ) {
        let resolvedSettings = settings ?? .shared
        let sharedActivityCenter = activityCenter ?? GlobalActivityCenter()
        self.activityCenter = sharedActivityCenter
        self.xcodeManagerViewModel = XcodeManagerViewModel(activityCenter: sharedActivityCenter)
        self.storageViewModel = StorageViewModel(activityCenter: sharedActivityCenter)
        self.updateManager = updateManager ?? AppUpdateManager()
        self.settings = resolvedSettings
        self.licenseService = licenseService ?? LicenseService()

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

    func openLicenseSettings() {
        presentSettingsModal()
    }
}
