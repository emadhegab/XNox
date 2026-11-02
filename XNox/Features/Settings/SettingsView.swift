import SwiftUI

struct SettingsView: View {
    enum Presentation {
        case embedded
        case modal
    }

    let presentation: Presentation

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updateManager: AppUpdateManager
    @EnvironmentObject private var licenseService: LicenseService
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue

    @State private var launchAtLoginError: String?
    @State private var licenseKey = ""

    init(presentation: Presentation = .embedded) {
        self.presentation = presentation
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Settings",
                    subtitle: "Control startup behavior, safety rails, update checks, and app appearance defaults."
                )

                startupSection
                appearanceSection
                licenseSection
                updatesSection
                operationsSection

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.error)
                        .padding(.horizontal, 2)
                }

                HStack(spacing: 10) {
                    Button("Reset To Defaults") {
                        settings.resetToDefaults()
                    }
                    .xNoxSecondaryButton()
                }
            }
            .padding(XNoxTheme.pagePadding)
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Startup & Window")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Toggle("Launch XNox at login", isOn: launchAtLoginBinding)

            Toggle("Reopen last section on launch", isOn: $settings.reopenLastSectionOnLaunch)

            Picker("Default section", selection: $settings.defaultSectionOnLaunch) {
                ForEach(AppSection.allCases, id: \.rawValue) { section in
                    Text(section.title)
                        .tag(section.rawValue)
                }
            }
            .pickerStyle(.menu)
            .disabled(settings.reopenLastSectionOnLaunch)

            Toggle("Auto refresh Xcodes list when opening section", isOn: $settings.autoRefreshXcodesOnOpen)

            Text("Default section applies when \"Reopen last section\" is disabled.")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
        }
        .cardSurface()
    }

    private var operationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operations & Safety")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Stepper(value: $settings.historyRetentionDays, in: 7 ... 365, step: 1) {
                LabeledContent("History retention") {
                    Text("\(settings.historyRetentionDays) days")
                        .font(XNoxTypography.bodyStrong)
                }
            }

            Toggle("Confirm destructive actions before running", isOn: $settings.confirmDestructiveActions)
        }
        .cardSurface()
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { updateManager.automaticallyChecksForUpdates },
                    set: { updateManager.automaticallyChecksForUpdates = $0 }
                )
            )

            Button("Check for Updates…") {
                updateManager.checkForUpdates()
            }
            .xNoxSecondaryButton()
            .disabled(!updateManager.canCheckForUpdates)
        }
        .cardSurface()
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Picker("Theme", selection: $appearanceModeRawValue) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

           
        }
        .cardSurface()
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("License")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            LabeledContent("Current plan") {
                Text(licenseService.currentPlanTitle)
                    .font(XNoxTypography.bodyStrong)
            }

            if let expirationLabel {
                LabeledContent("Expires") {
                    Text(expirationLabel)
                        .font(XNoxTypography.bodyStrong)
                }
            }

            TextField("Enter license key", text: $licenseKey)
                .xNoxInputField()

            HStack(spacing: 10) {
                Button("Activate License") {
                    Task {
                        await licenseService.activateLicense(licenseKey)
                        if licenseService.isProUnlocked {
                            licenseKey = ""
                        }
                    }
                }
                .xNoxPrimaryButton()
                .disabled(licenseService.isBusy || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Refresh Validation") {
                    Task {
                        await licenseService.refreshValidation()
                    }
                }
                .xNoxSecondaryButton()
                .disabled(licenseService.isBusy)

                Button("Remove License") {
                    licenseService.deactivateLicense()
                }
                .xNoxDestructiveButton()
                .disabled(licenseService.isBusy || !licenseService.isProUnlocked)
            }

            if let statusMessage = licenseService.statusMessage {
                Text(statusMessage)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }

            if let error = licenseService.lastErrorMessage {
                Text(error)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.error)
            }

            Text("Supports monthly, yearly, and lifetime licenses.")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
        }
        .cardSurface()
    }

    private var expirationLabel: String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        switch licenseService.state {
        case let .pro(entitlement), let .expired(entitlement):
            if entitlement.plan.isLifetime {
                return "Never (lifetime)"
            }
            guard let expiresAt = entitlement.expiresAt else {
                return nil
            }
            return formatter.string(from: expiresAt)
        case .free:
            return nil
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLoginEnabled },
            set: { newValue in
                let previousValue = settings.launchAtLoginEnabled
                settings.launchAtLoginEnabled = newValue

                do {
                    try LaunchAtLoginManager.setEnabled(newValue)
                    launchAtLoginError = nil
                } catch {
                    settings.launchAtLoginEnabled = previousValue
                    launchAtLoginError = "Could not update launch-at-login setting: \(error.localizedDescription)"
                }
            }
        )
    }
}

struct SettingsModalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView(presentation: .modal)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
        }
        .frame(width: 780, height: 640)
    }
}
