import Foundation
import Testing
@testable import XNox

struct SigningProjectsStoreTests {
    @Test
    @MainActor
    func matchInitCreatesMatchfileWithoutInteractivePrompts() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let request = MatchInitRequest(
            gitURL: "git@github.com:org/certs.git",
            gitBranch: "main",
            appIdentifiers: ["com.example.app", "com.example.app.widget"],
            teamID: "TEAM123456",
            username: "dev@example.com",
            matchPassword: nil,
            fastlaneSession: nil,
            workingDirectoryPath: tempRoot.path
        )

        let manager = FastlaneSigningManager()
        let result = try await manager.initializeMatch(request)
        let matchfileURL = tempRoot
            .appendingPathComponent("fastlane", isDirectory: true)
            .appendingPathComponent("Matchfile", isDirectory: false)

        #expect(result.success)
        #expect(FileManager.default.fileExists(atPath: matchfileURL.path))

        let body = try String(contentsOf: matchfileURL)
        #expect(body.contains("storage_mode(\"git\")"))
        #expect(body.contains("git_url(\"git@github.com:org/certs.git\")"))
        #expect(body.contains("team_id(\"TEAM123456\")"))
    }

    @Test
    func jsonStoreRoundTripPersistsProjects() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let fileURL = tempRoot.appendingPathComponent("signing-projects.json", isDirectory: false)
        let store = JSONSigningProjectsStore(fileURL: fileURL)

        let projects = [
            SigningProject(
                displayName: "AppA",
                localPath: "/tmp/workspace/AppA",
                teamID: "TEAM1",
                gitURL: "https://example.com/certs-a.git",
                gitBranch: "main",
                appIdentifiers: ["com.example.appa"],
                username: "dev+a@example.com",
                preferredProfileType: .development
            ),
            SigningProject(
                displayName: "AppB",
                localPath: "/tmp/workspace/AppB",
                teamID: "TEAM2",
                gitURL: "https://example.com/certs-b.git",
                gitBranch: "release",
                appIdentifiers: ["com.example.appb"],
                username: "dev+b@example.com",
                preferredProfileType: .appstore,
                isMatchInitialized: true,
                createdAt: .now,
                updatedAt: .now
            ),
        ]

        try store.saveProjects(projects)
        let loaded = try store.loadProjects()

        #expect(loaded.count == 2)
        #expect(loaded.map(\.displayName) == projects.map(\.displayName))
        #expect(loaded[0].teamID == projects[0].teamID)
        #expect(loaded[1].isMatchInitialized)
    }

    @Test
    func secretAccountKeyIsNamespacedPerProjectPath() {
        let first = SigningProjectSecretsStore.accountKey(
            for: .matchPassword,
            projectPath: "/Users/test/MyApp"
        )
        let second = SigningProjectSecretsStore.accountKey(
            for: .matchPassword,
            projectPath: "/Users/test/AnotherApp"
        )

        #expect(first != second)
    }

    @MainActor
    @Test
    func readActionMapsToReadonlyMatchRequest() async {
        let project = SigningProject(
            displayName: "AppA",
            localPath: "/tmp/workspace/AppA",
            teamID: "TEAM1",
            gitURL: "https://example.com/certs.git",
            gitBranch: "main",
            appIdentifiers: ["com.example.app"],
            username: "dev@example.com",
            preferredProfileType: .development,
            isMatchInitialized: true
        )

        let manager = CapturingSigningManager()
        let store = InMemorySigningProjectsStore(projects: [project])
        let secrets = InMemorySigningSecretsStore(
            values: [
                "\(SigningProjectSecret.matchPassword.rawValue):\(project.localPath ?? "")": "pw",
                "\(SigningProjectSecret.fastlaneSession.rawValue):\(project.localPath ?? "")": "session",
            ]
        )
        let viewModel = SigningViewModel(
            signingManager: manager,
            projectsStore: store,
            secretsStore: secrets
        )

        await viewModel.loadProjects()
        await viewModel.runAction(.read, projectID: project.id, profileType: .appstore)

        #expect(manager.lastRunMatchRequest?.readonly == true)
        #expect(manager.lastRunMatchRequest?.type == .appstore)
        #expect(manager.lastRunMatchRequest?.workingDirectoryPath == project.localPath)
        #expect(manager.lastRunMatchRequest?.matchPassword == "pw")
        #expect(manager.lastRunMatchRequest?.fastlaneSession == "session")
    }
}

private final class InMemorySigningProjectsStore: SigningProjectsStoring {
    var projects: [SigningProject]

    init(projects: [SigningProject]) {
        self.projects = projects
    }

    func loadProjects() throws -> [SigningProject] {
        projects
    }

    func saveProjects(_ projects: [SigningProject]) throws {
        self.projects = projects
    }
}

private final class InMemorySigningSecretsStore: SigningProjectSecretsStoring {
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

private final class CapturingSigningManager: SigningManaging {
    var lastRunMatchRequest: MatchRequest?
    var lastInitRequest: MatchInitRequest?
    var lastNukeRequest: MatchNukeRequest?

    func runMatch(_ request: MatchRequest) async throws -> MatchResult {
        lastRunMatchRequest = request
        return MatchResult(success: true, output: "ok")
    }

    func initializeMatch(_ request: MatchInitRequest) async throws -> MatchResult {
        lastInitRequest = request
        return MatchResult(success: true, output: "ok")
    }

    func nukeMatch(_ request: MatchNukeRequest) async throws -> MatchResult {
        lastNukeRequest = request
        return MatchResult(success: true, output: "ok")
    }
}
