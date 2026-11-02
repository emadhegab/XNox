import Combine
import Foundation

@MainActor
final class DeviceRegistrationViewModel: ObservableObject {
    @Published private(set) var signingProjects: [SigningProject] = []
    @Published var selectedProjectID: UUID?
    @Published private(set) var devices: [RegisteredDevice] = []
    @Published var deviceName = ""
    @Published var udid = ""
    @Published var shouldRefreshProfiles = true
    @Published var output = "No operation run yet."
    @Published var statusMessage = "Select a signing project to manage devices."
    @Published var isRunningAction = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncingDevices = false

    private let registrar: any DeviceRegistering
    private let signingManager: any SigningManaging
    private let projectsStore: any SigningProjectsStoring
    private let secretsStore: any SigningProjectSecretsStoring
    private let historyRecorder: any OperationHistoryRecording

    private var cachedDevicesByTeamID: [String: [RegisteredDevice]] = [:]
    private var lastFetchedTeamID: String?

    init(
        registrar: any DeviceRegistering,
        signingManager: any SigningManaging,
        projectsStore: any SigningProjectsStoring,
        secretsStore: (any SigningProjectSecretsStoring)? = nil,
        historyRecorder: (any OperationHistoryRecording)? = nil
    ) {
        self.registrar = registrar
        self.signingManager = signingManager
        self.projectsStore = projectsStore
        self.secretsStore = secretsStore ?? SigningProjectSecretsStore()
        self.historyRecorder = historyRecorder ?? OperationHistoryRecorder.shared
    }

    convenience init() {
        self.init(
            registrar: FastlaneDeviceRegistrar(),
            signingManager: FastlaneSigningManager(),
            projectsStore: JSONSigningProjectsStore(),
            secretsStore: nil,
            historyRecorder: nil
        )
    }

    var hasProjects: Bool {
        !signingProjects.isEmpty
    }

    var isValidUDID: Bool {
        let compact = normalizedUDID(udid)
        return compact.count == 40 && compact.allSatisfy { $0.isHexDigit }
    }

    var canSubmit: Bool {
        selectedProject != nil && !deviceNameTrimmed.isEmpty && isValidUDID && !isRunningAction
    }

    var selectedProject: SigningProject? {
        guard let selectedProjectID else { return nil }
        return signingProjects.first { $0.id == selectedProjectID }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try projectsStore.loadProjects()
            signingProjects = Self.sortedProjects(loaded)
        } catch {
            signingProjects = []
            statusMessage = "Unable to load signing projects: \(error.localizedDescription)"
            return
        }

        guard !signingProjects.isEmpty else {
            selectedProjectID = nil
            devices = []
            statusMessage = "No signing projects found. Add one in Signing first."
            return
        }

        if let selectedProjectID,
           signingProjects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = selectedProjectID
        } else {
            self.selectedProjectID = signingProjects.first?.id
        }

        await refreshDevicesForSelectedProject(force: true)
    }

    func selectProject(_ id: UUID?) {
        guard selectedProjectID != id else { return }
        selectedProjectID = id

        Task {
            await refreshDevicesForSelectedProject(force: false)
        }
    }

    func refreshDevicesForSelectedProject(force: Bool) async {
        guard let project = selectedProject else {
            devices = []
            return
        }

        let teamID = project.teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teamID.isEmpty else {
            devices = []
            statusMessage = "Selected project is missing Team ID."
            return
        }

        if !force,
           lastFetchedTeamID == teamID,
           let cached = cachedDevicesByTeamID[teamID] {
            devices = cached
            statusMessage = "Using cached devices for team \(teamID)."
            return
        }

        isSyncingDevices = true
        defer { isSyncingDevices = false }

        do {
            let result = try await registrar.fetchDevices(
                DeviceFetchRequest(
                    teamID: teamID,
                    username: project.username,
                    fastlaneSession: loadFastlaneSession(for: project),
                    workingDirectoryPath: project.localPath
                )
            )

            devices = result.devices
            cachedDevicesByTeamID[teamID] = result.devices
            lastFetchedTeamID = teamID
            output = result.output
            statusMessage = "Loaded \(result.devices.count) Apple-registered device(s) for team \(teamID)."
        } catch {
            devices = []
            output = "Error: \(error.localizedDescription)"
            statusMessage = "Unable to fetch devices from Apple: \(error.localizedDescription)"
        }
    }

    func submit() async {
        guard let selectedProject else {
            statusMessage = "Select a signing project before adding a device."
            return
        }

        guard !deviceNameTrimmed.isEmpty else {
            output = "Device name is required."
            return
        }

        guard isValidUDID else {
            output = "UDID must be 40 hex characters (dashes are ignored)."
            return
        }

        isRunningAction = true
        defer { isRunningAction = false }

        let request = DeviceRegistrationRequest(
            name: deviceNameTrimmed,
            udid: normalizedUDID(udid),
            platform: "ios",
            teamID: selectedProject.teamID,
            username: selectedProject.username,
            fastlaneSession: loadFastlaneSession(for: selectedProject),
            workingDirectoryPath: selectedProject.localPath
        )
        let historyID = historyRecorder.start(
            feature: "Devices",
            command: "fastlane run register_device name:\(request.name) udid:\(request.udid)",
            summary: "Registering device \(request.name) for \(selectedProject.displayName)."
        )

        do {
            let registerResult = try await registrar.register(request)
            var finalOutput = """
            Register Device Output:

            \(registerResult.output)
            """

            guard registerResult.success else {
                output = finalOutput
                statusMessage = "Device registration failed for \(selectedProject.displayName)."
                historyRecorder.complete(
                    id: historyID,
                    status: .failed,
                    summary: statusMessage,
                    exitCode: 1
                )
                return
            }

            if shouldRefreshProfiles {
                let matchResult = try await runMatchRefresh(for: selectedProject)
                finalOutput += """


                Match Refresh Output:

                \(matchResult.output)
                """

                statusMessage = matchResult.success
                    ? "Device registered and provisioning refreshed for \(selectedProject.displayName)."
                    : "Device registered, but provisioning refresh failed for \(selectedProject.displayName)."
            } else {
                statusMessage = "Device registered for \(selectedProject.displayName)."
            }

            output = finalOutput
            deviceName = ""
            udid = ""

            await refreshDevicesForSelectedProject(force: true)
            historyRecorder.complete(
                id: historyID,
                status: shouldRefreshProfiles ? (statusMessage.contains("failed") ? .failed : .success) : .success,
                summary: statusMessage,
                exitCode: statusMessage.contains("failed") ? 1 : 0
            )
        } catch DeviceRegistrarError.skeletonOnly {
            output = previewCommand(for: request, project: selectedProject)
            statusMessage = "Registration is not wired yet. Showing command preview."
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        } catch {
            output = "Error: \(error.localizedDescription)"
            statusMessage = "Device registration failed: \(error.localizedDescription)"
            historyRecorder.complete(
                id: historyID,
                status: .failed,
                summary: statusMessage,
                exitCode: 1
            )
        }
    }

    private func runMatchRefresh(for project: SigningProject) async throws -> MatchResult {
        var request = signingManager.makeMatchRequest(
            for: SigningProjectContext(
                gitURL: project.gitURL,
                gitBranch: project.gitBranch,
                appIdentifiers: project.appIdentifiers,
                teamID: project.teamID,
                username: project.username,
                workingDirectoryPath: project.localPath
            ),
            type: .development,
            readonly: false,
            forceForNewDevices: true
        )

        let secrets = loadSigningSecrets(for: project)
        request.matchPassword = secrets.normalizedMatchPassword
        request.fastlaneSession = secrets.normalizedFastlaneSession
        return try await signingManager.runMatch(request)
    }

    private func loadSigningSecrets(for project: SigningProject) -> SigningActionSecrets {
        guard let projectPath = project.localPath else {
            return SigningActionSecrets()
        }

        do {
            return SigningActionSecrets(
                matchPassword: try secretsStore.read(.matchPassword, projectPath: projectPath) ?? "",
                fastlaneSession: try secretsStore.read(.fastlaneSession, projectPath: projectPath) ?? ""
            )
        } catch {
            return SigningActionSecrets()
        }
    }

    private func loadFastlaneSession(for project: SigningProject) -> String? {
        guard let projectPath = project.localPath else { return nil }
        return try? secretsStore.read(.fastlaneSession, projectPath: projectPath)
    }

    private var deviceNameTrimmed: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedUDID(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func previewCommand(for request: DeviceRegistrationRequest, project: SigningProject) -> String {
        let registerParts = [
            "fastlane run register_device",
            "name:\(request.name)",
            "udid:\(request.udid)",
            "platform:\(request.platform)",
            "team_id:\(project.teamID)",
            "username:\(project.username)",
        ]

        let refreshPreview = shouldRefreshProfiles
            ? "\nThen run: fastlane run match type:development force_for_new_devices:true"
            : ""

        return "Skeleton preview:\n\n\(registerParts.joined(separator: " "))\(refreshPreview)"
    }

    private static func sortedProjects(_ projects: [SigningProject]) -> [SigningProject] {
        projects.sorted {
            let lhs = $0.displayName.localizedLowercase
            let rhs = $1.displayName.localizedLowercase
            if lhs != rhs {
                return lhs < rhs
            }
            return $0.createdAt < $1.createdAt
        }
    }
}
