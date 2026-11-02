import Combine
import Foundation

@MainActor
final class SigningViewModel: ObservableObject {
    @Published private(set) var projects: [SigningProject] = []
    @Published var setupDraft = SigningProjectSetupDraft()
    @Published var setupStep: SigningSetupStep = .displayName
    @Published var setupValidationMessage: String?
    @Published var output = "No operation run yet."
    @Published var statusMessage = "Add a signing project to begin."
    @Published var isLoadingProjects = false
    @Published var isRunningAction = false
    @Published var activeActionSummary: String?

    private let signingManager: any SigningManaging
    private let projectsStore: any SigningProjectsStoring
    private let secretsStore: any SigningProjectSecretsStoring
    private let historyRecorder: any OperationHistoryRecording

    init(
        signingManager: any SigningManaging,
        projectsStore: any SigningProjectsStoring,
        secretsStore: (any SigningProjectSecretsStoring)? = nil,
        historyRecorder: (any OperationHistoryRecording)? = nil
    ) {
        self.signingManager = signingManager
        self.projectsStore = projectsStore
        self.secretsStore = secretsStore ?? SigningProjectSecretsStore()
        self.historyRecorder = historyRecorder ?? OperationHistoryRecorder.shared
        Task {
            await loadProjects()
        }
    }

    convenience init() {
        self.init(
            signingManager: FastlaneSigningManager(),
            projectsStore: JSONSigningProjectsStore(),
            secretsStore: nil,
            historyRecorder: nil
        )
    }

    func loadProjects() async {
        isLoadingProjects = true
        defer { isLoadingProjects = false }

        do {
            let loaded = try projectsStore.loadProjects().map { project in
                var normalized = project
                if detectMatchInitialized(for: project.localPath) {
                    normalized.isMatchInitialized = true
                }
                return normalized
            }
            projects = Self.sortedProjects(loaded)
            statusMessage = projects.isEmpty
                ? "Add a signing project to begin."
                : "Loaded \(projects.count) signing project(s)."
        } catch {
            projects = []
            statusMessage = "Unable to load signing projects: \(error.localizedDescription)"
        }
    }

    func beginSetupWizard() {
        setupDraft = SigningProjectSetupDraft()
        setupStep = .displayName
        setupValidationMessage = nil
    }

    func moveToPreviousSetupStep() {
        guard let previous = setupStep.previousStep else { return }
        setupStep = previous
        setupValidationMessage = nil
    }

    func selectSetupProjectFolder(_ path: String) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        setupDraft.localPath = normalizedPath

        if setupDraft.normalizedDisplayName.isEmpty {
            setupDraft.displayName = URL(fileURLWithPath: normalizedPath).lastPathComponent
        }

        _ = applyMatchfileDefaults(to: &setupDraft, projectPath: normalizedPath)
        setupValidationMessage = nil
    }

    @discardableResult
    func applyMatchfileDefaults(
        to draft: inout SigningProjectSetupDraft,
        projectPath: String
    ) -> Bool {
        guard let values = MatchfileScanner.load(fromProjectPath: projectPath) else {
            return false
        }

        if let gitURL = values.gitURL {
            draft.gitURL = gitURL
        }
        if let gitBranch = values.gitBranch {
            draft.gitBranch = gitBranch
        }
        if let teamID = values.teamID {
            draft.teamID = teamID
        }
        if let username = values.username {
            draft.username = username
        }
        if let appIdentifiers = values.appIdentifiers, !appIdentifiers.isEmpty {
            draft.appIdentifiers = appIdentifiers.joined(separator: ", ")
        }
        if let profileType = values.profileType {
            draft.preferredProfileType = profileType
        }

        statusMessage = "Imported settings from fastlane/Matchfile for \(URL(fileURLWithPath: projectPath).lastPathComponent)."
        return true
    }

    func continueSetupWizard() async -> Bool {
        if let message = validationMessage(for: setupStep) {
            setupValidationMessage = message
            return false
        }

        setupValidationMessage = nil
        if let next = setupStep.nextStep {
            setupStep = next
            return false
        }

        let project = SigningProject(
            displayName: setupDraft.normalizedDisplayName,
            localPath: setupDraft.normalizedLocalPath,
            teamID: setupDraft.normalizedTeamID,
            gitURL: setupDraft.normalizedGitURL,
            gitBranch: setupDraft.normalizedGitBranch,
            appIdentifiers: setupDraft.normalizedAppIdentifiers,
            username: setupDraft.normalizedUsername,
            preferredProfileType: setupDraft.preferredProfileType,
            isMatchInitialized: detectMatchInitialized(for: setupDraft.normalizedLocalPath)
        )

        if let localPath = project.localPath,
           projects.contains(where: { item in
               item.localPath?.caseInsensitiveCompare(localPath) == .orderedSame
           }) {
            setupValidationMessage = "A project with this local path already exists."
            statusMessage = "Project path is already configured."
            return false
        }

        projects = Self.sortedProjects(projects + [project])

        do {
            try projectsStore.saveProjects(projects)
            statusMessage = "Saved signing project: \(project.displayName)."
            return true
        } catch {
            projects.removeAll { $0.id == project.id }
            statusMessage = "Unable to save signing project: \(error.localizedDescription)"
            return false
        }
    }

    func project(for id: UUID) -> SigningProject? {
        projects.first { $0.id == id }
    }

    func editDraft(for projectID: UUID) -> SigningProjectSetupDraft? {
        guard let project = project(for: projectID) else {
            return nil
        }

        var draft = SigningProjectSetupDraft()
        draft.displayName = project.displayName
        draft.localPath = project.localPath ?? ""
        draft.teamID = project.teamID
        draft.gitURL = project.gitURL
        draft.gitBranch = project.gitBranch
        draft.appIdentifiers = project.appIdentifiers.joined(separator: ", ")
        draft.username = project.username
        draft.preferredProfileType = project.preferredProfileType
        return draft
    }

    @discardableResult
    func saveProjectEdits(_ draft: SigningProjectSetupDraft, for projectID: UUID) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            statusMessage = "Selected project no longer exists."
            return false
        }

        if draft.normalizedDisplayName.isEmpty {
            statusMessage = "Project display name is required."
            return false
        }
        guard let normalizedPath = draft.normalizedLocalPath else {
            statusMessage = "Project local path is required."
            return false
        }
        if draft.normalizedTeamID.isEmpty {
            statusMessage = "Team ID is required."
            return false
        }
        if draft.normalizedGitURL.isEmpty {
            statusMessage = "Match Git URL is required."
            return false
        }

        if projects.contains(where: { item in
            guard item.id != projectID else { return false }
            return item.localPath?.caseInsensitiveCompare(normalizedPath) == .orderedSame
        }) {
            statusMessage = "Another project already uses this local path."
            return false
        }

        let original = projects
        var updatedProject = projects[index]
        updatedProject.displayName = draft.normalizedDisplayName
        updatedProject.localPath = normalizedPath
        updatedProject.teamID = draft.normalizedTeamID
        updatedProject.gitURL = draft.normalizedGitURL
        updatedProject.gitBranch = draft.normalizedGitBranch
        updatedProject.appIdentifiers = draft.normalizedAppIdentifiers
        updatedProject.username = draft.normalizedUsername
        updatedProject.preferredProfileType = draft.preferredProfileType
        updatedProject.isMatchInitialized = detectMatchInitialized(for: draft.normalizedLocalPath)
        updatedProject.updatedAt = .now

        projects[index] = updatedProject
        projects = Self.sortedProjects(projects)

        do {
            try projectsStore.saveProjects(projects)
            statusMessage = "Updated signing project: \(updatedProject.displayName)."
            return true
        } catch {
            projects = original
            statusMessage = "Unable to save project changes: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func removeProject(_ projectID: UUID) -> Bool {
        guard let project = project(for: projectID) else {
            statusMessage = "Selected project no longer exists."
            return false
        }

        let previous = projects
        projects.removeAll { $0.id == projectID }

        do {
            try projectsStore.saveProjects(projects)
            if let projectPath = project.localPath {
                try? secretsStore.delete(.matchPassword, projectPath: projectPath)
                try? secretsStore.delete(.fastlaneSession, projectPath: projectPath)
            }
            statusMessage = "Removed signing project: \(project.displayName)."
            return true
        } catch {
            projects = previous
            statusMessage = "Unable to remove signing project: \(error.localizedDescription)"
            return false
        }
    }

    func runAction(
        _ action: SigningProjectActionKind,
        projectID: UUID,
        profileType: MatchProfileType,
        secrets: SigningActionSecrets? = nil
    ) async {
        guard let project = project(for: projectID) else {
            statusMessage = "Selected project no longer exists."
            return
        }

        let resolvedSecrets = secrets ?? loadSecrets(for: projectID)

        let context = SigningProjectContext(
            gitURL: project.gitURL,
            gitBranch: project.gitBranch,
            appIdentifiers: project.appIdentifiers,
            teamID: project.teamID,
            username: project.username,
            workingDirectoryPath: project.localPath
        )

        isRunningAction = true
        activeActionSummary = "\(action.title) • \(project.displayName)"
        statusMessage = "Running \(action.title.lowercased()) for \(project.displayName)..."
        let historyID = historyRecorder.start(
            feature: "Signing",
            command: action.title.lowercased(),
            summary: "Running \(action.title) for \(project.displayName)."
        )
        defer {
            isRunningAction = false
            activeActionSummary = nil
        }

        do {
            let result: MatchResult
            switch action {
            case .initializeMatch:
                var request = signingManager.makeInitRequest(for: context)
                request.matchPassword = resolvedSecrets.normalizedMatchPassword
                request.fastlaneSession = resolvedSecrets.normalizedFastlaneSession
                result = try await signingManager.initializeMatch(request)
                if result.success {
                    updateProject(projectID) { item in
                        item.isMatchInitialized = true
                    }
                }
            case .create:
                var request = signingManager.makeMatchRequest(
                    for: context,
                    type: profileType,
                    readonly: false,
                    forceForNewDevices: false
                )
                request.matchPassword = resolvedSecrets.normalizedMatchPassword
                request.fastlaneSession = resolvedSecrets.normalizedFastlaneSession
                result = try await signingManager.runMatch(request)
            case .read:
                var request = signingManager.makeMatchRequest(
                    for: context,
                    type: profileType,
                    readonly: true,
                    forceForNewDevices: false
                )
                request.matchPassword = resolvedSecrets.normalizedMatchPassword
                request.fastlaneSession = resolvedSecrets.normalizedFastlaneSession
                result = try await signingManager.runMatch(request)
            case .nuke:
                var request = signingManager.makeNukeRequest(for: context, type: profileType)
                request.matchPassword = resolvedSecrets.normalizedMatchPassword
                request.fastlaneSession = resolvedSecrets.normalizedFastlaneSession
                result = try await signingManager.nukeMatch(request)
            }

            output = result.output
            updateProject(projectID) { item in
                item.preferredProfileType = profileType
                if action == .create || action == .read || action == .initializeMatch {
                    item.isMatchInitialized = true
                }
            }
            try projectsStore.saveProjects(projects)
            statusMessage = result.success
                ? "\(action.title) completed for \(project.displayName)."
                : "\(action.title) failed for \(project.displayName)."
            historyRecorder.complete(
                id: historyID,
                status: result.success ? .success : .failed,
                summary: statusMessage,
                exitCode: result.success ? 0 : 1
            )
        } catch SigningManagerError.skeletonOnly {
            output = fallbackPreview(for: action, context: context, profileType: profileType)
            statusMessage = "\(action.title) is not wired yet. Showing command preview."
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        } catch {
            output = "Error: \(error.localizedDescription)"
            statusMessage = "\(action.title) failed for \(project.displayName): \(error.localizedDescription)"
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    func loadSecrets(for projectID: UUID) -> SigningActionSecrets {
        guard let path = project(for: projectID)?.localPath else {
            return SigningActionSecrets()
        }

        do {
            let matchPassword = try secretsStore.read(.matchPassword, projectPath: path) ?? ""
            let fastlaneSession = try secretsStore.read(.fastlaneSession, projectPath: path) ?? ""
            return SigningActionSecrets(
                matchPassword: matchPassword,
                fastlaneSession: fastlaneSession
            )
        } catch {
            statusMessage = "Unable to load saved signing secrets: \(error.localizedDescription)"
            return SigningActionSecrets()
        }
    }

    func saveSecrets(_ secrets: SigningActionSecrets, for projectID: UUID) {
        guard let path = project(for: projectID)?.localPath else {
            return
        }

        do {
            try upsert(secret: .matchPassword, value: secrets.normalizedMatchPassword, projectPath: path)
            try upsert(secret: .fastlaneSession, value: secrets.normalizedFastlaneSession, projectPath: path)
        } catch {
            statusMessage = "Unable to save signing secrets: \(error.localizedDescription)"
        }
    }

    func launchSpaceauth(for projectID: UUID) {
        guard let project = project(for: projectID) else {
            statusMessage = "Selected project no longer exists."
            return
        }

        let username = project.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            statusMessage = "Username is required to generate FASTLANE_SESSION."
            return
        }

        do {
            let command = try SpaceauthLauncher.launch(
                username: username,
                workingDirectoryPath: project.localPath
            )
            output = """
            Opened Terminal for fastlane authentication.
            Command:
            \(command)

            Complete login + 2FA in Terminal, then paste the generated FASTLANE_SESSION here.
            """
            statusMessage = "Opened Terminal to run fastlane spaceauth for \(project.displayName)."
            historyRecorder.record(
                feature: "Signing",
                command: command,
                status: .success,
                summary: statusMessage,
                exitCode: 0
            )
        } catch {
            output = "Error: \(error.localizedDescription)"
            statusMessage = "Unable to launch fastlane spaceauth: \(error.localizedDescription)"
            historyRecorder.record(
                feature: "Signing",
                command: "fastlane spaceauth -u \(username)",
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    private func validationMessage(for step: SigningSetupStep) -> String? {
        switch step {
        case .displayName where setupDraft.normalizedDisplayName.isEmpty:
            return "Project display name is required."
        case .localPath where setupDraft.normalizedLocalPath == nil:
            return "Project local path is required."
        case .teamID where setupDraft.normalizedTeamID.isEmpty:
            return "Team ID is required."
        case .gitURL where setupDraft.normalizedGitURL.isEmpty:
            return "Match Git URL is required."
        default:
            return nil
        }
    }

    private func fallbackPreview(
        for action: SigningProjectActionKind,
        context: SigningProjectContext,
        profileType: MatchProfileType
    ) -> String {
        switch action {
        case .initializeMatch:
            let request = signingManager.makeInitRequest(for: context)
            return "Skeleton preview (Init Match):\n\n\(signingManager.previewCommand(for: request))"
        case .create:
            let request = signingManager.makeMatchRequest(
                for: context,
                type: profileType,
                readonly: false,
                forceForNewDevices: false
            )
            return "Skeleton preview (Create):\n\n\(signingManager.previewCommand(for: request))"
        case .read:
            let request = signingManager.makeMatchRequest(
                for: context,
                type: profileType,
                readonly: true,
                forceForNewDevices: false
            )
            return "Skeleton preview (Read):\n\n\(signingManager.previewCommand(for: request))"
        case .nuke:
            let request = signingManager.makeNukeRequest(for: context, type: profileType)
            return "Skeleton preview (Nuke):\n\n\(signingManager.previewCommand(for: request))"
        }
    }

    private func updateProject(_ id: UUID, change: (inout SigningProject) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        var updated = projects[index]
        change(&updated)
        updated.updatedAt = .now
        projects[index] = updated
        projects = Self.sortedProjects(projects)
    }

    private static func sortedProjects(_ projects: [SigningProject]) -> [SigningProject] {
        projects.sorted { lhs, rhs in
            let lhsName = lhs.displayName.localizedLowercase
            let rhsName = rhs.displayName.localizedLowercase
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func upsert(
        secret: SigningProjectSecret,
        value: String?,
        projectPath: String
    ) throws {
        if let value {
            try secretsStore.save(value, for: secret, projectPath: projectPath)
        } else {
            try secretsStore.delete(secret, projectPath: projectPath)
        }
    }

    private func detectMatchInitialized(for localPath: String?) -> Bool {
        guard let localPath,
              !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let matchfilePath = URL(fileURLWithPath: localPath, isDirectory: true)
            .appendingPathComponent("fastlane", isDirectory: true)
            .appendingPathComponent("Matchfile", isDirectory: false)
            .path
        return FileManager.default.fileExists(atPath: matchfilePath)
    }
}

private enum SpaceauthLauncher {
    static func launch(username: String, workingDirectoryPath: String?) throws -> String {
        #if os(macOS)
        var parts: [String] = []
        if let workingDirectoryPath,
           !workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("cd \(shellQuoted(workingDirectoryPath))")
        }
        parts.append("fastlane spaceauth -u \(shellQuoted(username))")

        let shellCommand = parts.joined(separator: " && ")
        let appleScriptCommand = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(appleScriptCommand)\"",
        ]

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SigningManagerError.initializationFailed("osascript failed with exit code \(process.terminationStatus).")
        }

        return shellCommand
        #else
        throw SigningManagerError.initializationFailed("Generating FASTLANE_SESSION from app is supported on macOS only.")
        #endif
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
