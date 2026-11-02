import SwiftUI
import UniformTypeIdentifiers

struct SigningView: View {
    @StateObject private var viewModel = SigningViewModel()
    @State private var presentedSheet: SigningSheet?
    @State private var pendingProjectRemoval: SigningProject?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XNoxTheme.cardSpacing) {
                SectionHeaderView(
                    title: "Signing & Certificates",
                    subtitle: "Store per-project signing context and run fastlane match actions against the selected repo."
                )

                summaryCard

                if viewModel.projects.isEmpty {
                    EmptyStateView(
                        title: "No Saved Signing Projects",
                        message: "Create a project profile with team and repository details before running match actions.",
                        systemImage: "folder.badge.plus"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.projects) { project in
                            projectCard(project)
                        }
                    }
                }

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
            .padding(XNoxTheme.pagePadding)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .setup:
                SigningSetupSheet(viewModel: viewModel)
                    .frame(minWidth: 620, minHeight: 440)
            case let .actions(projectID):
                SigningProjectActionsSheet(viewModel: viewModel, projectID: projectID)
                    .frame(minWidth: 720, minHeight: 520)
            }
        }
        .alert(
            "Remove Project?",
            isPresented: Binding(
                get: { pendingProjectRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingProjectRemoval = nil
                    }
                }
            ),
            presenting: pendingProjectRemoval
        ) { project in
            Button("Remove", role: .destructive) {
                if viewModel.removeProject(project.id),
                   case let .actions(projectID) = presentedSheet,
                   projectID == project.id {
                    presentedSheet = nil
                }
                pendingProjectRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingProjectRemoval = nil
            }
        } message: { project in
            Text("This removes \(project.displayName) from saved projects.")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projects")
                    .font(XNoxTypography.cardTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)
                Spacer()

                Button("Reload") {
                    Task {
                        await viewModel.loadProjects()
                    }
                }
                .xNoxSecondaryButton()
                .disabled(viewModel.isLoadingProjects || viewModel.isRunningAction)

                Button("Add Project") {
                    viewModel.beginSetupWizard()
                    presentedSheet = .setup
                }
                .xNoxPrimaryButton()
                .accessibilityIdentifier("signing.addProject")
                .disabled(viewModel.isRunningAction)
            }

            HStack(spacing: 10) {
                Text("\(viewModel.projects.count) saved project(s)")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)

                if viewModel.isLoadingProjects || viewModel.isRunningAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(viewModel.statusMessage)
                .font(XNoxTypography.body)
                .foregroundStyle(XNoxPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetSurface()
        }
        .cardSurface()
    }

    private func projectCard(_ project: SigningProject) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                presentedSheet = .actions(project.id)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(project.displayName)
                            .font(XNoxTypography.cardTitle)
                            .foregroundStyle(XNoxPalette.textPrimary)

                        Spacer()

                        statusPill(
                            title: project.isMatchInitialized ? "Match Initialized" : "Needs Init",
                            color: project.isMatchInitialized ? XNoxPalette.success : XNoxPalette.warning
                        )
                    }
                    .padding(.trailing, 28)

                    if let localPath = project.localPath,
                       !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(localPath, systemImage: "folder")
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 14) {
                        Label(project.teamID, systemImage: "person.2.fill")
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)

                        Label(project.gitBranch, systemImage: "arrow.triangle.branch")
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)

                        Label(project.preferredProfileType.title, systemImage: "checkmark.shield")
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)
                    }

                    Text(project.gitURL)
                        .font(XNoxTypography.mono)
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !project.appIdentifiers.isEmpty {
                        Text(project.appIdentifiers.joined(separator: ", "))
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)
                            .lineLimit(2)
                    }

                    HStack {
                        Spacer()
                        Label("Open Actions", systemImage: "bolt.horizontal")
                            .font(XNoxTypography.button)
                            .foregroundStyle(XNoxPalette.accentStart)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
            .buttonStyle(.plain)

            Button {
                pendingProjectRemoval = project
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(XNoxTypography.bodyStrong)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("Remove Project")
        }
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(XNoxTypography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .clipShape(Capsule(style: .continuous))
    }
}

private enum SigningSheet: Identifiable {
    case setup
    case actions(UUID)

    var id: String {
        switch self {
        case .setup:
            return "setup"
        case let .actions(projectID):
            return "actions-\(projectID.uuidString)"
        }
    }
}

private struct SigningSetupSheet: View {
    @ObservedObject var viewModel: SigningViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPathPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("Project Signing Setup")
                    .font(XNoxTypography.sectionTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(XNoxTypography.bodyStrong)
                        .foregroundStyle(XNoxPalette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("signing.setup.close")
            }

            Text("Step \(viewModel.setupStep.rawValue + 1) of \(SigningSetupStep.allCases.count)")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.setupStep.prompt)
                    .font(XNoxTypography.bodyStrong)
                    .foregroundStyle(XNoxPalette.textPrimary)

                Text(viewModel.setupStep.description)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)
            }

            stepInput

            if let setupValidationMessage = viewModel.setupValidationMessage {
                Text(setupValidationMessage)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.error)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Back") {
                    viewModel.moveToPreviousSetupStep()
                }
                .xNoxSecondaryButton()
                .disabled(viewModel.setupStep.previousStep == nil)

                Spacer()

                Button(viewModel.setupStep.actionTitle) {
                    Task {
                        let shouldDismiss = await viewModel.continueSetupWizard()
                        if shouldDismiss {
                            dismiss()
                        }
                    }
                }
                .xNoxPrimaryButton()
                .disabled(viewModel.isRunningAction)
            }
        }
        .padding(20)
        .fileImporter(
            isPresented: $isPathPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                viewModel.selectSetupProjectFolder(url.standardizedFileURL.path)
            case let .failure(error):
                viewModel.setupValidationMessage = "Unable to select folder: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private var stepInput: some View {
        switch viewModel.setupStep {
        case .localPath:
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.setupDraft.localPath.isEmpty ? "No folder selected" : viewModel.setupDraft.localPath)
                    .font(XNoxTypography.mono)
                    .foregroundStyle(XNoxPalette.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetSurface()

                HStack(spacing: 8) {
                    Button("Browse Project Folder") {
                        isPathPickerPresented = true
                    }
                    .xNoxPrimaryButton()
                    .accessibilityIdentifier("signing.setup.path.browse")

                    Button("Clear") {
                        viewModel.setupDraft.localPath = ""
                        viewModel.setupValidationMessage = nil
                    }
                    .xNoxSecondaryButton()
                    .disabled(viewModel.setupDraft.localPath.isEmpty)
                }
            }
        case .profileType:
            Picker("Profile Type", selection: $viewModel.setupDraft.preferredProfileType) {
                ForEach(MatchProfileType.allCases) { type in
                    Text(type.title)
                        .font(XNoxTypography.bodyStrong)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
        case .confirm:
            VStack(alignment: .leading, spacing: 8) {
                confirmationRow("Name", value: viewModel.setupDraft.normalizedDisplayName)
                confirmationRow("Path", value: viewModel.setupDraft.normalizedLocalPath ?? "Current directory")
                confirmationRow("Team ID", value: viewModel.setupDraft.normalizedTeamID)
                confirmationRow("Git URL", value: viewModel.setupDraft.normalizedGitURL)
                confirmationRow("Git Branch", value: viewModel.setupDraft.normalizedGitBranch)
                confirmationRow(
                    "App IDs",
                    value: viewModel.setupDraft.normalizedAppIdentifiers.isEmpty
                        ? "None"
                        : viewModel.setupDraft.normalizedAppIdentifiers.joined(separator: ", ")
                )
                confirmationRow("Username", value: viewModel.setupDraft.normalizedUsername)
                confirmationRow("Default Profile", value: viewModel.setupDraft.preferredProfileType.title)
            }
            .insetSurface()
        default:
            TextField(
                viewModel.setupStep.placeholder,
                text: textBinding(for: viewModel.setupStep)
            )
            .xNoxInputField()
        }
    }

    private func confirmationRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)
            Text(value)
                .font(XNoxTypography.body)
                .foregroundStyle(XNoxPalette.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func textBinding(for step: SigningSetupStep) -> Binding<String> {
        switch step {
        case .displayName:
            return $viewModel.setupDraft.displayName
        case .localPath:
            return $viewModel.setupDraft.localPath
        case .teamID:
            return $viewModel.setupDraft.teamID
        case .gitURL:
            return $viewModel.setupDraft.gitURL
        case .gitBranch:
            return $viewModel.setupDraft.gitBranch
        case .appIdentifiers:
            return $viewModel.setupDraft.appIdentifiers
        case .username:
            return $viewModel.setupDraft.username
        case .profileType, .confirm:
            return .constant("")
        }
    }
}

private struct SigningProjectActionsSheet: View {
    @ObservedObject var viewModel: SigningViewModel
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProfileType: MatchProfileType
    @State private var pendingSecretAction: SigningProjectActionKind?
    @State private var isSecretsPromptPresented = false
    @State private var isEditSheetPresented = false
    @State private var isEditPathPickerPresented = false
    @State private var editDraft = SigningProjectSetupDraft()
    @State private var editValidationMessage: String?
    @State private var actionSecrets = SigningActionSecrets()
    @State private var isMatchPasswordVisible = false
    @State private var isFastlaneSessionVisible = false

    init(viewModel: SigningViewModel, projectID: UUID) {
        self.viewModel = viewModel
        self.projectID = projectID
        _selectedProfileType = State(initialValue: viewModel.project(for: projectID)?.preferredProfileType ?? .development)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let project = viewModel.project(for: projectID) {
                Text(project.displayName)
                    .font(XNoxTypography.sectionTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)

                if let localPath = project.localPath,
                   !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(localPath, systemImage: "folder")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(project.isMatchInitialized
                     ? "Match is initialized for this project."
                     : "Match is not initialized for this project. Run Init Match first.")
                    .font(XNoxTypography.body)
                    .foregroundStyle(project.isMatchInitialized ? XNoxPalette.success : XNoxPalette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetSurface()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Type")
                        .font(XNoxTypography.caption)
                        .foregroundStyle(XNoxPalette.textSecondary)

                    Picker("Profile Type", selection: $selectedProfileType) {
                        ForEach(MatchProfileType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 10) {
                    Button("Edit Settings") {
                        beginEdit()
                    }
                    .xNoxSecondaryButton()
                    .disabled(viewModel.isRunningAction)

                    Button(SigningProjectActionKind.initializeMatch.title) {
                        startAction(.initializeMatch)
                    }
                    .xNoxPrimaryButton()
                    .disabled(viewModel.isRunningAction)

                    Button(SigningProjectActionKind.create.title) {
                        startAction(.create)
                    }
                    .xNoxPrimaryButton()
                    .disabled(viewModel.isRunningAction)

                    Button(SigningProjectActionKind.read.title) {
                        startAction(.read)
                    }
                    .xNoxSecondaryButton()
                    .disabled(viewModel.isRunningAction)

                    Button(SigningProjectActionKind.nuke.title) {
                        startAction(.nuke)
                    }
                    .xNoxDestructiveButton()
                    .disabled(viewModel.isRunningAction)
                }

                if let activeActionSummary = viewModel.activeActionSummary {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(activeActionSummary)
                            .font(XNoxTypography.caption)
                            .foregroundStyle(XNoxPalette.textSecondary)
                    }
                    .insetSurface()
                }

                Text("Latest Output")
                    .font(XNoxTypography.cardTitle)
                    .foregroundStyle(XNoxPalette.textPrimary)

                ScrollView(.vertical) {
                    Text(viewModel.output)
                        .font(XNoxTypography.mono)
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260, alignment: .topLeading)
                .insetSurface()

                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .xNoxSecondaryButton()
                }
            } else {
                Text("Project not found.")
                    .font(XNoxTypography.body)
                    .foregroundStyle(XNoxPalette.textSecondary)

                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .xNoxSecondaryButton()
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $isSecretsPromptPresented) {
            secretsPromptSheet
                .frame(minWidth: 480, minHeight: 300)
        }
        .sheet(isPresented: $isEditSheetPresented) {
            editSettingsSheet
                .frame(minWidth: 620, minHeight: 480)
        }
    }

    private func startAction(_ action: SigningProjectActionKind) {
        guard action.requiresSecretsPrompt else {
            run(action)
            return
        }
        actionSecrets = viewModel.loadSecrets(for: projectID)
        isMatchPasswordVisible = false
        isFastlaneSessionVisible = false
        pendingSecretAction = action
        isSecretsPromptPresented = true
    }

    private func beginEdit() {
        guard let draft = viewModel.editDraft(for: projectID) else {
            editValidationMessage = "Project not found."
            return
        }
        editDraft = draft
        editValidationMessage = nil
        isEditSheetPresented = true
    }

    @ViewBuilder
    private var secretsPromptSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Signing Secrets")
                .font(XNoxTypography.sectionTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Text("Enter secrets for this project. Values are saved in Keychain and scoped by project path.")
                .font(XNoxTypography.caption)
                .foregroundStyle(XNoxPalette.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("MATCH_PASSWORD")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)

                HStack(spacing: 8) {
                    if isMatchPasswordVisible {
                        TextField("Enter match password", text: $actionSecrets.matchPassword)
                            .xNoxInputField()
                    } else {
                        SecureField("Enter match password", text: $actionSecrets.matchPassword)
                            .xNoxInputField()
                    }

                    Button {
                        isMatchPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isMatchPasswordVisible ? "eye.slash" : "eye")
                    }
                    .xNoxSecondaryButton()
                    .accessibilityLabel(isMatchPasswordVisible ? "Hide match password" : "Show match password")
                    .accessibilityIdentifier("signing.secrets.matchPassword.visibility")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("FASTLANE_SESSION")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)

                HStack(spacing: 8) {
                    if isFastlaneSessionVisible {
                        TextField("Enter fastlane session", text: $actionSecrets.fastlaneSession)
                            .xNoxInputField()
                    } else {
                        SecureField("Enter fastlane session", text: $actionSecrets.fastlaneSession)
                            .xNoxInputField()
                    }

                    Button {
                        isFastlaneSessionVisible.toggle()
                    } label: {
                        Image(systemName: isFastlaneSessionVisible ? "eye.slash" : "eye")
                    }
                    .xNoxSecondaryButton()
                    .accessibilityLabel(isFastlaneSessionVisible ? "Hide fastlane session" : "Show fastlane session")
                    .accessibilityIdentifier("signing.secrets.fastlaneSession.visibility")
                }

                Button("Generate In Terminal (2FA)") {
                    viewModel.launchSpaceauth(for: projectID)
                }
                .xNoxSecondaryButton()
                .accessibilityIdentifier("signing.secrets.generateSession")
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Cancel") {
                    isSecretsPromptPresented = false
                    pendingSecretAction = nil
                }
                .xNoxSecondaryButton()

                Button("Clear Saved") {
                    actionSecrets = SigningActionSecrets()
                }
                .xNoxSecondaryButton()

                Spacer()

                Button(pendingSecretAction?.title ?? "Run") {
                    guard let action = pendingSecretAction else {
                        isSecretsPromptPresented = false
                        return
                    }
                    viewModel.saveSecrets(actionSecrets, for: projectID)
                    isSecretsPromptPresented = false
                    pendingSecretAction = nil
                    run(action, secrets: actionSecrets)
                }
                .xNoxPrimaryButton()
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var editSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Project Settings")
                .font(XNoxTypography.sectionTitle)
                .foregroundStyle(XNoxPalette.textPrimary)

            Group {
                TextField("Display Name", text: $editDraft.displayName)
                    .xNoxInputField()

                VStack(alignment: .leading, spacing: 8) {
                    Text(editDraft.localPath.isEmpty ? "No folder selected" : editDraft.localPath)
                        .font(XNoxTypography.mono)
                        .foregroundStyle(XNoxPalette.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .insetSurface()

                    HStack(spacing: 8) {
                        Button("Browse Project Folder") {
                            isEditPathPickerPresented = true
                        }
                        .xNoxPrimaryButton()

                        Button("Clear") {
                            editDraft.localPath = ""
                        }
                        .xNoxSecondaryButton()
                        .disabled(editDraft.localPath.isEmpty)
                    }
                }

                TextField("Team ID", text: $editDraft.teamID)
                    .xNoxInputField()

                TextField("Match Git URL", text: $editDraft.gitURL)
                    .xNoxInputField()

                TextField("Git Branch", text: $editDraft.gitBranch)
                    .xNoxInputField()

                TextField("App Identifiers (comma separated)", text: $editDraft.appIdentifiers)
                    .xNoxInputField()

                TextField("Apple ID Username", text: $editDraft.username)
                    .xNoxInputField()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Profile Type")
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.textSecondary)

                Picker("Profile Type", selection: $editDraft.preferredProfileType) {
                    ForEach(MatchProfileType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let editValidationMessage {
                Text(editValidationMessage)
                    .font(XNoxTypography.caption)
                    .foregroundStyle(XNoxPalette.error)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Cancel") {
                    isEditSheetPresented = false
                    editValidationMessage = nil
                }
                .xNoxSecondaryButton()

                Spacer()

                Button("Save Changes") {
                    if viewModel.saveProjectEdits(editDraft, for: projectID) {
                        selectedProfileType = editDraft.preferredProfileType
                        isEditSheetPresented = false
                        editValidationMessage = nil
                    } else {
                        editValidationMessage = viewModel.statusMessage
                    }
                }
                .xNoxPrimaryButton()
            }
        }
        .padding(20)
        .fileImporter(
            isPresented: $isEditPathPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                var draft = editDraft
                draft.localPath = url.standardizedFileURL.path
                _ = viewModel.applyMatchfileDefaults(to: &draft, projectPath: draft.localPath)
                editDraft = draft
                editValidationMessage = nil
            case let .failure(error):
                editValidationMessage = "Unable to select folder: \(error.localizedDescription)"
            }
        }
    }

    private func run(_ action: SigningProjectActionKind, secrets: SigningActionSecrets? = nil) {
        Task {
            await viewModel.runAction(
                action,
                projectID: projectID,
                profileType: selectedProfileType,
                secrets: secrets
            )
        }
    }
}
