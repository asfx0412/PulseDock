import Foundation

/// One Keychain item for all user-approved PulseDock credentials. The vault is
/// intentionally loaded only after a user action and is held only in memory for
/// the current app session.
struct CredentialVault: Codable, Equatable {
    static let legacyAccount = "credential-vault-v1"
    static let systemAuthenticatedAccount = "credential-vault-v2"
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
    enum UnlockOrigin: Equatable {
        case systemAuthentication
        case legacyPassword
    }

    enum UnlockResult: Equatable {
        case unlocked(CredentialVault, UnlockOrigin)
        case missing
        case interactionRequired
        case failed(OSStatus)
    }

    static func unlock(preferSystemAuthentication: Bool) async -> UnlockResult {
        guard preferSystemAuthentication else {
            return decode(SecretStore.readInteractive(CredentialVault.legacyAccount), origin: .legacyPassword)
        }
        // Direct Touch ID mode intentionally never falls back to v1. An old
        // ordinary Login Keychain item can only be read with its old password
        // ACL; touching it would violate the user's “no first password” choice.
        // Keep it intact for an optional future recovery flow, but create a
        // clean v2 vault after successful system authentication instead.
        switch decode(await SecretStore.readSystemAuthenticated(CredentialVault.systemAuthenticatedAccount), origin: .systemAuthentication) {
        case .missing:
            let empty = CredentialVault()
            // The Touch ID check above is the gate. The ad-hoc build cannot
            // create a Keychain `.userPresence` ACL (-34018), so v2 is kept in
            // the ordinary local keychain and every app read still enters via
            // that explicit gate.
            switch save(empty, systemAuthenticated: true) {
            case .saved: return .unlocked(empty, .systemAuthentication)
            case .interactionRequired: return .interactionRequired
            case let .failed(status): return .failed(status)
            case .removed: return .missing
            }
        case let result:
            return result
        }
    }

    private static func decode(_ result: SecretStore.ReadResult, origin: UnlockOrigin) -> UnlockResult {
        switch result {
        case let .value(raw):
            guard let data = raw.data(using: .utf8),
                  let vault = try? JSONDecoder().decode(CredentialVault.self, from: data),
                  vault.schemaVersion == 1 else { return .failed(errSecDecode) }
            return .unlocked(vault, origin)
        case .missing: return .missing
        case .interactionRequired: return .interactionRequired
        case let .failed(status): return .failed(status)
        }
    }

    static func save(_ vault: CredentialVault, systemAuthenticated: Bool) -> SecretStore.WriteResult {
        guard let data = try? JSONEncoder().encode(vault),
              let text = String(data: data, encoding: .utf8) else { return .failed(errSecParam) }
        return systemAuthenticated
            ? SecretStore.writeSystemAuthenticated(text, account: CredentialVault.systemAuthenticatedAccount)
            : SecretStore.writeInteractive(text, account: CredentialVault.legacyAccount)
    }

    /// Once the user has explicitly unlocked the vault, subsequent saves in the
    /// same app session must not summon another Keychain authorization sheet.
    static func saveAfterUnlock(_ vault: CredentialVault, systemAuthenticated: Bool) -> SecretStore.WriteResult {
        guard let data = try? JSONEncoder().encode(vault),
              let text = String(data: data, encoding: .utf8) else { return .failed(errSecParam) }
        // A protected item must retain macOS user-presence semantics. Saving
        // after it was unlocked is still an explicit user action in Settings.
        // Do not delete or inspect v1 here: a legacy Login Keychain ACL can
        // summon its password sheet even for a delete. Touch ID mode must be
        // completely isolated from the legacy item.
        if systemAuthenticated {
            return SecretStore.writeSystemAuthenticated(text, account: CredentialVault.systemAuthenticatedAccount)
        }
        return SecretStore.write(text, account: CredentialVault.legacyAccount)
    }

    static func remove() -> SecretStore.WriteResult {
        let v2 = SecretStore.removeInteractive(CredentialVault.systemAuthenticatedAccount)
        guard v2 == .removed else { return v2 }
        return SecretStore.removeInteractive(CredentialVault.legacyAccount)
    }
}
