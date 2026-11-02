import SwiftUI

struct DeviceRegistrationView: View {
    @StateObject private var viewModel = DeviceRegistrationViewModel()
    private let onRequestOpenSigning: () -> Void

    init(onRequestOpenSigning: @escaping () -> Void = {}) {
        self.onRequestOpenSigning = onRequestOpenSigning
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Devices",
                    subtitle: "Register physical devices to Apple Developer teams and refresh profiles when needed."
                )

                projectsCard
                registrationCard
                devicesCard
                outputCard
            }
            .padding(XNoxTheme.pagePadding)
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var projectsCard: some View {
        if viewModel.hasProjects {
            VStack(alignment: .leading, spacing: 10) {
                Text("Signing Project")
                    .font(XNoxTypography.cardTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)

                Picker(
                    "Signing Project",
                    selection: Binding(
                        get: { viewModel.selectedProjectID },
                        set: { viewModel.selectProject($0) }
                    )
                ) {
                    ForEach(viewModel.signingProjects) { project in
                        Text(project.displayName)
                            .tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)

                if let project = viewModel.selectedProject {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Team ID: \(project.teamID)")
                            .font(XNoxTypography.caption)
                        Text("Username: \(project.username)")
                            .font(XNoxTypography.caption)
                    }
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .insetSurface()
                }

                HStack(spacing: 10) {
                    Button("Sync from Apple") {
                        Task {
                            await viewModel.refreshDevicesForSelectedProject(force: true)
                        }
                    }
                    .xNoxSecondaryButton()
                    .disabled(viewModel.isSyncingDevices)

                    if viewModel.isSyncingDevices {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(viewModel.statusMessage)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }
            .cardSurface()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                EmptyStateView(
                    title: "Signing Project Required",
                    message: "Add at least one signing project to load team devices and enable registration.",
                    systemImage: "checkmark.shield"
                )

                Button("Go to Signing to Add Project") {
                    onRequestOpenSigning()
                }
                .xNoxPrimaryButton()
            }
        }
    }

    private var registrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Register Device")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            TextField("Device Name", text: $viewModel.deviceName)
                .xNoxInputField()

            TextField("UDID", text: $viewModel.udid)
                .xNoxInputField()

            HStack {
                if viewModel.udid.isEmpty {
                    StatusBadge(kind: .neutral)
                } else {
                    StatusBadge(kind: viewModel.isValidUDID ? .good : .warning)
                }
                Text(viewModel.isValidUDID ? "UDID format looks valid" : "UDID must be 40 hex chars")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }

            Toggle("Refresh development profiles after registration", isOn: $viewModel.shouldRefreshProfiles)
                .font(XNoxTypography.body)
                .foregroundStyle(XNoxPalette.textPrimary)
                .disabled(!viewModel.hasProjects)

            Button("Register Device") {
                Task {
                    await viewModel.submit()
                }
            }
            .xNoxPrimaryButton()
            .disabled(!viewModel.canSubmit)
        }
        .cardSurface()
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Registered Devices")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            if viewModel.devices.isEmpty {
                Text("This team currently has no registered devices in Apple Developer.")
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .insetSurface()
            } else {
                ForEach(viewModel.devices) { device in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                                .font(XNoxTypography.bodyStrong)
                                .foregroundStyle(XNoxPalette.textPrimary)
                            Text(device.udid)
                                .font(XNoxTypography.mono)
                                .foregroundStyle(XNoxPalette.textSecondary)
                        }

                        Spacer(minLength: 12)

                        Text(device.platform.uppercased())
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)
                    }
                    .insetSurface()
                }
            }
        }
        .cardSurface()
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)
            Text(viewModel.output)
                .font(XNoxTypography.mono)
                .foregroundStyle(XNoxPalette.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetSurface()
        }
        .cardSurface()
    }
}
