import CryptoKit
import Foundation
import Security

protocol SigningProjectSecretsStoring {
    func save(_ value: String, for secret: SigningProjectSecret, projectPath: String) throws
    func read(_ secret: SigningProjectSecret, projectPath: String) throws -> String?
    func delete(_ secret: SigningProjectSecret, projectPath: String) throws
}

final class SigningProjectSecretsStore: SigningProjectSecretsStoring {
    private let service: String

    init(service: String = "app.hegab.XNox.signing") {
        self.service = service
    }

    func save(_ value: String, for secret: SigningProjectSecret, projectPath: String) throws {
        try delete(secret, projectPath: projectPath)

        let data = Data(value.utf8)
        let account = Self.accountKey(for: secret, projectPath: projectPath)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.failed(status: status)
        }
    }

    func read(_ secret: SigningProjectSecret, projectPath: String) throws -> String? {
        let account = Self.accountKey(for: secret, projectPath: projectPath)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecretStoreError.failed(status: status)
        }

        guard let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(_ secret: SigningProjectSecret, projectPath: String) throws {
        let account = Self.accountKey(for: secret, projectPath: projectPath)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.failed(status: status)
        }
    }

    static func accountKey(for secret: SigningProjectSecret, projectPath: String) -> String {
        let normalized = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(secret.rawValue).\(hex)"
    }
}
