import Foundation

/// One Keychain item for all user-approved PulseDock credentials. The vault is
/// intentionally loaded only after a user action and is held only in memory for
/// the current app session.
struct CredentialVault: Codable, Equatable {
    static let account = "credential-vault-v1"
    var schemaVersion = 1
    var values: [String: String] = [:]

    subscript(_ key: String) -> String {
        get { values[key] ?? "" }
        set {
            if newValue.isEmpty { values.removeValue(forKey: key) }
            else { values[key] = newValue }
        }
    }
}

enum CredentialVaultService {
    enum UnlockResult: Equatable {
        case unlocked(CredentialVault)
        case missing
        case interactionRequired
        case failed(OSStatus)
    }

    static func unlock() -> UnlockResult {
        switch SecretStore.readInteractive(CredentialVault.account) {
        case let .value(raw):
            guard let data = raw.data(using: .utf8),
                  let vault = try? JSONDecoder().decode(CredentialVault.self, from: data),
                  vault.schemaVersion == 1 else { return .failed(errSecDecode) }
            return .unlocked(vault)
        case .missing: return .missing
        case .interactionRequired: return .interactionRequired
        case let .failed(status): return .failed(status)
        }
    }

    static func save(_ vault: CredentialVault) -> SecretStore.WriteResult {
        guard let data = try? JSONEncoder().encode(vault),
              let text = String(data: data, encoding: .utf8) else { return .failed(errSecParam) }
        return SecretStore.writeInteractive(text, account: CredentialVault.account)
    }

    /// Once the user has explicitly unlocked the vault, subsequent saves in the
    /// same app session must not summon another Keychain authorization sheet.
    static func saveAfterUnlock(_ vault: CredentialVault) -> SecretStore.WriteResult {
        guard let data = try? JSONEncoder().encode(vault),
              let text = String(data: data, encoding: .utf8) else { return .failed(errSecParam) }
        return SecretStore.write(text, account: CredentialVault.account)
    }

    static func remove() -> SecretStore.WriteResult {
        SecretStore.removeInteractive(CredentialVault.account)
    }
}
