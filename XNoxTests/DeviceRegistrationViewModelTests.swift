import Foundation
import Testing
@testable import XNox

struct DeviceRegistrationViewModelTests {
    @MainActor
    @Test
    func loadShowsNoProjectsStateWhenSigningIsEmpty() async {
        let registrar = CapturingDeviceRegistrar()
        let viewModel = DeviceRegistrationViewModel(
            registrar: registrar,
            signingManager: CapturingSigningManager(),
            projectsStore: InMemoryProjectsStore(projects: []),
            secretsStore: InMemorySecretsStore()
        )

        await viewModel.load()

        #expect(viewModel.hasProjects == false)
        #expect(viewModel.signingProjects.isEmpty)
        #expect(viewModel.selectedProjectID == nil)
        #expect(registrar.fetchRequests.isEmpty)
    }

    @MainActor
    @Test
    func switchingProjectsFetchesOnlyWhenTeamChanges() async {
        let projectA = SigningProject(
            displayName: "App A",
            localPath: "/tmp/a",
            teamID: "TEAM1",
            gitURL: "https://example.com/a.git",
            gitBranch: "main",
            appIdentifiers: ["com.example.a"],
            username: "a@example.com",
            preferredProfileType: .development
        )

        let projectB = SigningProject(
            displayName: "App B",
            localPath: "/tmp/b",
            teamID: "TEAM1",
            gitURL: "https://example.com/b.git",
            gitBranch: "main",
            appIdentifiers: ["com.example.b"],
            username: "b@example.com",
            preferredProfileType: .development
        )

        let projectC = SigningProject(
            displayName: "App C",
            localPath: "/tmp/c",
            teamID: "TEAM2",
            gitURL: "https://example.com/c.git",
            gitBranch: "main",
            appIdentifiers: ["com.example.c"],
            username: "c@example.com",
            preferredProfileType: .development
        )

        let registrar = CapturingDeviceRegistrar()
        registrar.fetchResult = DeviceFetchResult(
            success: true,
            output: "ok",
            devices: [RegisteredDevice(name: "QA", udid: "UDID1", platform: "ios")]
        )

        let viewModel = DeviceRegistrationViewModel(
            registrar: registrar,
            signingManager: CapturingSigningManager(),
            projectsStore: InMemoryProjectsStore(projects: [projectA, projectB, projectC]),
            secretsStore: InMemorySecretsStore()
        )

        await viewModel.load()
        #expect(registrar.fetchRequests.count == 1)
        #expect(registrar.fetchRequests.last?.teamID == "TEAM1")

        viewModel.selectProject(projectB.id)
        await Task.yield()
        #expect(registrar.fetchRequests.count == 1)

        viewModel.selectProject(projectC.id)
        await Task.yield()
        #expect(registrar.fetchRequests.count == 2)
        #expect(registrar.fetchRequests.last?.teamID == "TEAM2")
    }

    @MainActor
    @Test
    func submitRegistersDeviceRefreshesMatchAndRefetchesDevices() async {
        let project = SigningProject(
            displayName: "App",
            localPath: "/tmp/app",
            teamID: "TEAM123",
            gitURL: "https://example.com/certs.git",
            gitBranch: "main",
            appIdentifiers: ["com.example.app"],
            username: "dev@example.com",
            preferredProfileType: .development
        )

        let registrar = CapturingDeviceRegistrar()
        registrar.registerResult = DeviceRegistrationResult(success: true, output: "device ok")
        registrar.fetchResult = DeviceFetchResult(
            success: true,
            output: "devices ok",
            devices: [RegisteredDevice(name: "QA iPhone", udid: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", platform: "ios")]
        )

        let signingManager = CapturingSigningManager()
        let secretsStore = InMemorySecretsStore(
            values: [
                "\(SigningProjectSecret.fastlaneSession.rawValue):/tmp/app": "session",
                "\(SigningProjectSecret.matchPassword.rawValue):/tmp/app": "pw",
            ]
        )

        let viewModel = DeviceRegistrationViewModel(
            registrar: registrar,
            signingManager: signingManager,
            projectsStore: InMemoryProjectsStore(projects: [project]),
            secretsStore: secretsStore
        )

        await viewModel.load()
        viewModel.deviceName = "QA iPhone"
        viewModel.udid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        viewModel.shouldRefreshProfiles = true
        await viewModel.submit()

        #expect(registrar.registerRequests.count == 1)
        #expect(registrar.registerRequests.last?.teamID == "TEAM123")
        #expect(registrar.registerRequests.last?.fastlaneSession == "session")
        #expect(signingManager.lastRunMatchRequest?.forceForNewDevices == true)
        #expect(signingManager.lastRunMatchRequest?.type == .development)
        #expect(signingManager.lastRunMatchRequest?.matchPassword == "pw")
        #expect(registrar.fetchRequests.count == 2)
        #expect(viewModel.devices.count == 1)
    }
}

private final class CapturingDeviceRegistrar: DeviceRegistering {
    var registerRequests: [DeviceRegistrationRequest] = []
    var fetchRequests: [DeviceFetchRequest] = []
    var registerResult = DeviceRegistrationResult(success: true, output: "ok")
    var fetchResult = DeviceFetchResult(success: true, output: "ok", devices: [])

    func register(_ request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResult {
        registerRequests.append(request)
        return registerResult
    }

    func fetchDevices(_ request: DeviceFetchRequest) async throws -> DeviceFetchResult {
        fetchRequests.append(request)
        return fetchResult
    }
}

private final class InMemoryProjectsStore: SigningProjectsStoring {
    let projects: [SigningProject]

    init(projects: [SigningProject]) {
        self.projects = projects
    }

    func loadProjects() throws -> [SigningProject] {
        projects
    }

    func saveProjects(_ projects: [SigningProject]) throws {
        _ = projects
    }
}

private final class CapturingSigningManager: SigningManaging {
    var lastRunMatchRequest: MatchRequest?

    func runMatch(_ request: MatchRequest) async throws -> MatchResult {
        lastRunMatchRequest = request
        return MatchResult(success: true, output: "match ok")
    }

    func initializeMatch(_ request: MatchInitRequest) async throws -> MatchResult {
        _ = request
        return MatchResult(success: true, output: "init ok")
    }

    func nukeMatch(_ request: MatchNukeRequest) async throws -> MatchResult {
        _ = request
        return MatchResult(success: true, output: "nuke ok")
    }
}

private final class InMemorySecretsStore: SigningProjectSecretsStoring {
    var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func save(_ value: String, for secret: SigningProjectSecret, projectPath: String) throws {
        values["\(secret.rawValue):\(projectPath)"] = value
    }

    func read(_ secret: SigningProjectSecret, projectPath: String) throws -> String? {
        values["\(secret.rawValue):\(projectPath)"]
    }

    func delete(_ secret: SigningProjectSecret, projectPath: String) throws {
        values.removeValue(forKey: "\(secret.rawValue):\(projectPath)")
    }
}
