import Foundation
import Security

enum SecretKey: String, CaseIterable {
    case fastlaneSession
    case matchPassword
    case gitAccessToken
}

protocol SecretStoring {
    func save(_ value: String, for key: SecretKey) throws
    func read(_ key: SecretKey) throws -> String?
    func delete(_ key: SecretKey) throws
}

enum SecretStoreError: LocalizedError {
    case failed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .failed(status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
