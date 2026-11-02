import SwiftUI

struct XcodeManagerView: View {
    @EnvironmentObject private var viewModel: XcodeManagerViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var pendingUninstallRelease: XcodeRelease?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Xcode Manager",
                    subtitle: "Install, activate, and remove Xcode versions with per-row progress and auth prompts."
                )

                actionCard

                Text(viewModel.statusMessage)
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetSurface()
                    .cardSurface()

                versionsCard
            }
            .padding(XNoxTheme.pagePadding)
        }
        .task {
            if settings.autoRefreshXcodesOnOpen {
                await viewModel.load()
            }
        }
        .confirmationDialog(
            "Remove Xcode",
            isPresented: Binding(
                get: { pendingUninstallRelease != nil },
                set: { if !$0 { pendingUninstallRelease = nil } }
            ),
            presenting: pendingUninstallRelease
        ) { release in
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.uninstall(version: release.version)
                }
                pendingUninstallRelease = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUninstallRelease = nil
            }
        } message: { release in
            Text("Remove Xcode \(release.version) from this Mac?")
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use row actions: Install Now, Switch To, or Remove. Auth prompts and live progress appear below that same row.")
                .font(XNoxTypography.body)
                .foregroundStyle(XNoxPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button("Refresh List") {
                    Task {
                        await viewModel.load()
                    }
                }
                .xNoxSecondaryButton()
                .disabled(viewModel.isBusy)

                Button("Sign Out") {
                    Task {
                        await viewModel.signOut()
                    }
                }
                .xNoxDestructiveButton()
                .disabled(viewModel.isBusy)

                if viewModel.isLoading {
                    ProgressView("Refreshing versions...")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                }
            }
        }
        .cardSurface()
    }

    private var versionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Xcode Versions")
                .font(XNoxTypography.cardTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            if viewModel.available.isEmpty {
                Text("No releases loaded. Verify `xcodes` authentication and network access, then refresh the list.")
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.available.enumerated()), id: \.element.id) { index, release in
                        versionRow(for: release)

                        if index < viewModel.available.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
    }

    private func versionRow(for release: XcodeRelease) -> some View {
        let isUserSelected = viewModel.selectedVersion == release.version

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(release.version)
                        .font(XNoxTypography.bodyStrong)
                        .foregroundStyle(XNoxPalette.textPrimary)

                    Text(release.isPrerelease ? "Pre-release" : "Stable")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    if release.isInstalled {
                        statusPill(title: "Installed", color: XNoxPalette.success)
                    }

                    if release.isSelected {
                        statusPill(title: "Active", color: XNoxPalette.accentStart)
                    }

                    if release.isPrerelease {
                        statusPill(title: "Beta", color: XNoxPalette.warning)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Install Now") {
                    Task {
                        await viewModel.install(version: release.version)
                    }
                }
                .xNoxPrimaryButton()
                .disabled(!viewModel.canInstall(release))

                Button("Switch To") {
                    Task {
                        await viewModel.select(version: release.version)
                    }
                }
                .xNoxSecondaryButton()
                .disabled(!viewModel.canSelect(release))

                Button("Remove") {
                    if settings.confirmDestructiveActions {
                        pendingUninstallRelease = release
                    } else {
                        Task {
                            await viewModel.uninstall(version: release.version)
                        }
                    }
                }
                .xNoxDestructiveButton()
                .disabled(!viewModel.canUninstall(release))
            }

            if viewModel.shouldShowInstallDetails(for: release.version) {
                inlineInstallDetails()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground(for: release, isUserSelected: isUserSelected))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    rowBorder(for: release, isUserSelected: isUserSelected),
                    lineWidth: isUserSelected ? 1.6 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectVersion(release.version)
        }
    }

    private func inlineInstallDetails() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Install Progress")
                    .font(XNoxTypography.caption.weight(.semibold))
                    .foregroundStyle(XNoxPalette.textPrimary)

                Spacer()

                if viewModel.isInstalling {
                    Text(viewModel.installElapsedLabel)
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)

                    ProgressView()
                        .controlSize(.small)

                    Button("Cancel") {
                        viewModel.cancelInstall()
                    }
                    .xNoxDestructiveButton()
                    .disabled(!viewModel.canCancelInstall)
                }
            }

            if viewModel.isInstalling {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if let installPromptHint = viewModel.installPromptHint {
                            Text("Prompt: \(installPromptHint)")
                                .font(XNoxTypography.caption)
                                .foregroundStyle(XNoxPalette.warning)
                        } else {
                            Text("Prompt: waiting...")
                                .font(XNoxTypography.caption)
                                .foregroundStyle(XNoxPalette.textSecondary)
                        }

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        ZStack(alignment: .trailing) {
                            Group {
                                if viewModel.isInstallInputSecure {
                                    SecureField("Enter response for prompt", text: $viewModel.pendingInstallInput)
                                        .textContentType(viewModel.shouldUseOneTimeCodeAutofill ? .oneTimeCode : nil)
                                } else {
                                    TextField("Enter response for prompt", text: $viewModel.pendingInstallInput)
                                        .textContentType(viewModel.shouldUseOneTimeCodeAutofill ? .oneTimeCode : nil)
                                }
                            }
                            .padding(.trailing, viewModel.shouldShowPasswordVisibilityToggle ? 30 : 0)
                            .xNoxInputField()
                            .onSubmit {
                                viewModel.sendInstallInput()
                            }

                            if viewModel.shouldShowPasswordVisibilityToggle {
                                Button {
                                    viewModel.isInstallInputSecure.toggle()
                                } label: {
                                    Image(systemName: viewModel.isInstallInputSecure ? "eye.slash" : "eye")
                                        .font(XNoxTypography.caption.weight(.semibold))
                                        .foregroundStyle(XNoxPalette.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 10)
                                .help(viewModel.isInstallInputSecure ? "Show password text" : "Hide password text")
                            }
                        }

                        Button("Send") {
                            viewModel.sendInstallInput()
                        }
                        .xNoxSecondaryButton()
                        .disabled(!viewModel.canSendInstallInput)
                    }

                    if viewModel.shouldUseOneTimeCodeAutofill {
                        Text("One-time code AutoFill is enabled for this prompt.")
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)
                    }
                }
                .insetSurface()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.installProgress.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(XNoxTypography.mono)
                                .foregroundStyle(XNoxPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 110, maxHeight: 220)
                .insetSurface()
                .onChange(of: viewModel.installProgress.count) { _, count in
                    guard count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(XNoxPalette.panelInsetBackground.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(XNoxPalette.panelBorder.opacity(0.55), lineWidth: 1)
        )
    }

    private func rowBackground(for release: XcodeRelease, isUserSelected: Bool) -> Color {
        if isUserSelected {
            return XNoxPalette.accentStart.opacity(0.14)
        }
        if release.isSelected {
            return XNoxPalette.accentStart.opacity(0.10)
        }
        if release.isInstalled {
            return XNoxPalette.success.opacity(0.10)
        }
        return XNoxPalette.panelInsetBackground.opacity(0.45)
    }

    private func rowBorder(for release: XcodeRelease, isUserSelected: Bool) -> Color {
        if isUserSelected {
            return XNoxPalette.accentStart.opacity(0.95)
        }
        if release.isSelected {
            return XNoxPalette.accentStart.opacity(0.45)
        }
        if release.isInstalled {
            return XNoxPalette.success.opacity(0.42)
        }
        return XNoxPalette.panelBorder.opacity(0.75)
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(XNoxTypography.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
