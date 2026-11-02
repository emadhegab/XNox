import Foundation

enum SigningSetupStep: Int, CaseIterable, Identifiable {
    case displayName
    case localPath
    case teamID
    case gitURL
    case gitBranch
    case appIdentifiers
    case username
    case profileType
    case confirm

    var id: Int { rawValue }

    var prompt: String {
        switch self {
        case .displayName:
            return "Enter a display name for this signing project."
        case .localPath:
            return "Optionally enter a local path where signing commands should run."
        case .teamID:
            return "Enter the Apple Developer Team ID."
        case .gitURL:
            return "Enter the Git repository URL used by fastlane match."
        case .gitBranch:
            return "Enter the branch used for match storage."
        case .appIdentifiers:
            return "Enter app bundle identifiers (comma separated)."
        case .username:
            return "Enter the Apple ID username used by fastlane."
        case .profileType:
            return "Choose the default profile type for this project."
        case .confirm:
            return "Review and save this project setup."
        }
    }

    var description: String {
        switch self {
        case .displayName:
            return "Shown in the signing dashboard cards."
        case .localPath:
            return "Leave empty to run from the current working directory."
        case .teamID:
            return "Passed as the `team_id` value in match commands."
        case .gitURL:
            return "This repo stores certificates and provisioning profiles."
        case .gitBranch:
            return "Usually `main` unless your match repo uses another branch."
        case .appIdentifiers:
            return "Examples: com.example.app, com.example.app.watchkitapp."
        case .username:
            return "Used for fastlane match authentication context."
        case .profileType:
            return "Used as the default selection in project action sheets."
        case .confirm:
            return "Click Save Project to persist this configuration locally."
        }
    }

    var placeholder: String {
        switch self {
        case .displayName:
            return "Acme iOS"
        case .localPath:
            return "/Users/you/work/acme-ios"
        case .teamID:
            return "ABC123XYZ9"
        case .gitURL:
            return "git@github.com:org/certificates.git"
        case .gitBranch:
            return "main"
        case .appIdentifiers:
            return "com.example.app, com.example.app.widget"
        case .username:
            return "dev@example.com"
        case .profileType, .confirm:
            return ""
        }
    }

    var actionTitle: String {
        nextStep == nil ? "Save Project" : "Continue"
    }

    var nextStep: SigningSetupStep? {
        SigningSetupStep(rawValue: rawValue + 1)
    }

    var previousStep: SigningSetupStep? {
        SigningSetupStep(rawValue: rawValue - 1)
    }
}

struct SigningProject: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var displayName: String
    var localPath: String?
    var teamID: String
    var gitURL: String
    var gitBranch: String
    var appIdentifiers: [String]
    var username: String
    var preferredProfileType: MatchProfileType
    var isMatchInitialized: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        localPath: String?,
        teamID: String,
        gitURL: String,
        gitBranch: String,
        appIdentifiers: [String],
        username: String,
        preferredProfileType: MatchProfileType,
        isMatchInitialized: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.localPath = localPath
        self.teamID = teamID
        self.gitURL = gitURL
        self.gitBranch = gitBranch
        self.appIdentifiers = appIdentifiers
        self.username = username
        self.preferredProfileType = preferredProfileType
        self.isMatchInitialized = isMatchInitialized
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SigningProjectSetupDraft: Hashable, Sendable {
    var displayName = ""
    var localPath = ""
    var teamID = ""
    var gitURL = ""
    var gitBranch = "main"
    var appIdentifiers = ""
    var username = ""
    var preferredProfileType: MatchProfileType = .development

    var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLocalPath: String? {
        let trimmed = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedTeamID: String {
        teamID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGitURL: String {
        gitURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGitBranch: String {
        let trimmed = gitBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "main" : trimmed
    }

    var normalizedAppIdentifiers: [String] {
        appIdentifiers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SigningProjectActionKind: String, CaseIterable, Hashable, Sendable {
    case initializeMatch
    case create
    case read
    case nuke

    var title: String {
        switch self {
        case .initializeMatch:
            return "Init Match"
        case .create:
            return "Create"
        case .read:
            return "Read"
        case .nuke:
            return "Nuke"
        }
    }

    var requiresSecretsPrompt: Bool {
        switch self {
        case .initializeMatch:
            return false
        case .create, .read, .nuke:
            return true
        }
    }
}

enum SigningProjectSecret: String, CaseIterable {
    case matchPassword
    case fastlaneSession
}

struct SigningActionSecrets: Hashable, Sendable {
    var matchPassword = ""
    var fastlaneSession = ""

    var normalizedMatchPassword: String? {
        let trimmed = matchPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedFastlaneSession: String? {
        let trimmed = fastlaneSession.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct MatchfileScannedValues: Sendable {
    var gitURL: String?
    var gitBranch: String?
    var appIdentifiers: [String]?
    var teamID: String?
    var username: String?
    var profileType: MatchProfileType?
}

enum MatchfileScanner {
    static func load(fromProjectPath projectPath: String) -> MatchfileScannedValues? {
        let matchfileURL = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("fastlane", isDirectory: true)
            .appendingPathComponent("Matchfile", isDirectory: false)

        guard FileManager.default.fileExists(atPath: matchfileURL.path),
              let contents = try? String(contentsOf: matchfileURL, encoding: .utf8) else {
            return nil
        }

        return parse(contents)
    }

    static func parse(_ contents: String) -> MatchfileScannedValues {
        var values = MatchfileScannedValues()

        values.gitURL = firstMatch(contents, pattern: #"(?m)^\s*git_url\(\s*["']([^"']+)["']\s*\)"#)
        values.gitBranch = firstMatch(contents, pattern: #"(?m)^\s*git_branch\(\s*["']([^"']+)["']\s*\)"#)
        values.teamID = firstMatch(contents, pattern: #"(?m)^\s*team_id\(\s*["']([^"']+)["']\s*\)"#)
        values.username = firstMatch(contents, pattern: #"(?m)^\s*username\(\s*["']([^"']+)["']\s*\)"#)

        if let typeRaw = firstMatch(contents, pattern: #"(?m)^\s*type\(\s*["']([^"']+)["']\s*\)"#)?
            .lowercased() {
            values.profileType = MatchProfileType(rawValue: typeRaw)
        }

        if let arrayPayload = firstMatch(contents, pattern: #"(?m)^\s*app_identifier\(\s*\[([^\]]+)\]\s*\)"#) {
            let identifiers = allMatches(arrayPayload, pattern: #"["']([^"']+)["']"#)
            if !identifiers.isEmpty {
                values.appIdentifiers = identifiers
            }
        } else if let single = firstMatch(contents, pattern: #"(?m)^\s*app_identifier\(\s*["']([^"']+)["']\s*\)"#) {
            values.appIdentifiers = [single]
        }

        return values
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func allMatches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
