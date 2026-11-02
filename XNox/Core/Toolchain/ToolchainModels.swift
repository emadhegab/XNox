import Foundation

enum DevTool: String, CaseIterable, Identifiable {
    case fastlane

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fastlane:
            return "fastlane"
        }
    }

    var minimumVersion: String {
        switch self {
        case .fastlane:
            return "2.232.0"
        }
    }

    var installCommand: String {
        switch self {
        case .fastlane:
            return "brew install fastlane"
        }
    }

    var updateCommand: String {
        switch self {
        case .fastlane:
            return "brew upgrade fastlane"
        }
    }

    var brewFormulaName: String {
        switch self {
        case .fastlane:
            return "fastlane"
        }
    }

    var brewInfoIdentifier: String {
        switch self {
        case .fastlane:
            return "fastlane"
        }
    }
}

enum ToolInstallMethod: String {
    case homebrew
    case bundler
    case gem
    case unknown
}

struct ToolStatus: Identifiable, Sendable {
    var id: DevTool { tool }
    let tool: DevTool
    let path: String?
    let version: String?
    let meetsMinimumVersion: Bool
    let latestAvailableVersion: String?
    let updateCommand: String?
    let isUpdateAvailable: Bool
    let installMethod: ToolInstallMethod
    let note: String?
}
