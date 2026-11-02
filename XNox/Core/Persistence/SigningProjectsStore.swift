import Foundation

protocol SigningProjectsStoring {
    func loadProjects() throws -> [SigningProject]
    func saveProjects(_ projects: [SigningProject]) throws
}

enum SigningProjectsStoreError: LocalizedError {
    case unableToResolveApplicationSupport

    var errorDescription: String? {
        switch self {
        case .unableToResolveApplicationSupport:
            return "Unable to resolve Application Support directory for signing projects."
        }
    }
}

final class JSONSigningProjectsStore: SigningProjectsStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let fallback = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/XNox/signing-projects.json", isDirectory: false)
            self.fileURL = appSupport?
                .appendingPathComponent("XNox", isDirectory: true)
                .appendingPathComponent("signing-projects.json", isDirectory: false) ?? fallback
        }
    }

    func loadProjects() throws -> [SigningProject] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder.decode([SigningProject].self, from: data)
        } catch {
            guard let legacyProjects = try? decoder.decode([LegacySigningProject].self, from: data) else {
                throw error
            }
            return legacyProjects.map { legacy in
                let normalizedPath = legacy.path.trimmingCharacters(in: .whitespacesAndNewlines)
                return SigningProject(
                    displayName: legacy.displayName,
                    localPath: normalizedPath.isEmpty ? nil : normalizedPath,
                    teamID: legacy.config.teamID,
                    gitURL: legacy.config.gitURL,
                    gitBranch: legacy.config.gitBranch,
                    appIdentifiers: legacy.config.appIdentifiers,
                    username: legacy.config.username,
                    preferredProfileType: .development,
                    isMatchInitialized: legacy.isMatchInitialized,
                    createdAt: legacy.createdAt,
                    updatedAt: legacy.updatedAt
                )
            }
        }
    }

    func saveProjects(_ projects: [SigningProject]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(projects)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private struct LegacySigningProjectConfig: Codable {
    var teamID: String
    var gitURL: String
    var gitBranch: String
    var appIdentifiers: [String]
    var username: String
}

private struct LegacySigningProject: Codable {
    var path: String
    var displayName: String
    var config: LegacySigningProjectConfig
    var isMatchInitialized: Bool
    var createdAt: Date
    var updatedAt: Date
}
