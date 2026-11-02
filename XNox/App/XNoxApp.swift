import AppKit
import ServiceManagement
import SwiftUI

@main
struct XNoxApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var appState: AppState
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue

    init() {
        let sharedSettings = AppSettings.shared
        _settings = StateObject(wrappedValue: sharedSettings)
        _appState = StateObject(wrappedValue: AppState(settings: sharedSettings))

        do {
            try LaunchAtLoginManager.setEnabled(sharedSettings.launchAtLoginEnabled)
        } catch {
            NSLog("XNox launch-at-login sync failed: %@", error.localizedDescription)
        }
    }

    var body: some Scene {
        Window("XNox", id: "main") {
            AppRootView()
                .environmentObject(appState)
                .environmentObject(appState.activityCenter)
                .environmentObject(appState.storageViewModel)
                .environmentObject(settings)
                .task(id: appearanceModeRawValue) {
                    applyAppAppearance(currentAppearanceMode)
                }
                .font(XNoxTypography.body)
                .frame(minWidth: 1100, minHeight: 700)
        }

        MenuBarExtra {
            XNoxMenuBarView()
                .environmentObject(appState)
        } label: {
            Image("Logo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            XNoxAppCommands(appState: appState)
        }
    }
}

private extension XNoxApp {
    var currentAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    func applyAppAppearance(_ mode: AppAppearanceMode) {
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

private struct XNoxMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Open XNox") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Divider()

        Button("Settings") {
            openSettingsModal()
        }

        Button("Quit XNox") {
            NSApp.terminate(nil)
        }
    }

    private func openSettingsModal() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        appState.presentSettingsModal()
    }
}

private struct XNoxAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                appState.presentSettingsModal()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            SMAppService.mainApp.status == .enabled
        } else {
            false
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }

        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, .enabled), (false, .notRegistered):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }
    }
}
