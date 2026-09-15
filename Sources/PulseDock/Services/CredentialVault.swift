import Foundation

/// One Keychain item for all user-approved PulseDock credentials. The vault is
/// intentionally loaded only after a user action and is held only in memory for
/// the current app session.
struct CredentialVault: Codable, Equatable {
    /// The only supported vault identity. Historical v1/v2/v3 Keychain data is
    /// deliberately outside this implementation and is never accessed.
    static let systemAuthenticatedAccount = "credential-vault-v4"
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

    static func unlock() async -> UnlockResult {
        // The Touch ID flow has one identity and one policy. It never reads,
        // migrates, deletes, or falls back to the historical v1/v2/v3 items.
        // A first unlock also never writes an empty Keychain record: creation
        // happens only after the user explicitly saves real credentials.
        switch decode(await SecretStore.readSystemAuthenticated(CredentialVault.systemAuthenticatedAccount)) {
        case .missing: return .missing
        case let result:
            return result
        }
    }

    private static func decode(_ result: SecretStore.ReadResult) -> UnlockResult {
        switch result {
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

    /// Once the user has explicitly unlocked the vault, subsequent saves in the
    /// same app session must not summon another Keychain authorization sheet.
    static func saveAfterUnlock(_ vault: CredentialVault) -> SecretStore.WriteResult {
        guard let data = try? JSONEncoder().encode(vault),
              let text = String(data: data, encoding: .utf8) else { return .failed(errSecParam) }
        return SecretStore.writeSystemAuthenticated(text, account: CredentialVault.systemAuthenticatedAccount)
    }

    static func remove() -> SecretStore.WriteResult {
        SecretStore.remove(CredentialVault.systemAuthenticatedAccount)
    }
}
