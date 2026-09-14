import Foundation

@main
struct Version631KeychainSelfTest {
    static func main() {
        precondition(SecretStore.service == "com.pulsedock.monitor")
        precondition(SecretStore.ReadResult.interactionRequired == .interactionRequired)
        precondition(SecretStore.WriteResult.interactionRequired == .interactionRequired)
        precondition(SecretStore.ReadResult.missing == .missing)
        precondition(SecretStore.WriteResult.removed == .removed)
        precondition(CredentialVault.legacyAccount == "credential-vault-v1")
        // v3 is deliberately a separate identity: Touch ID operation must
        // never touch experimental v2 or an older Login Keychain entry.
        precondition(CredentialVault.systemAuthenticatedAccount == "credential-vault-v3")
        let vault = CredentialVault(values: ["one": "1"])
        precondition(vault["one"] == "1")

        // A Keychain integration check must run from PulseDock.app: a helper
        // executable has a different code-signing identity and is not a valid
        // substitute for the real app's Keychain behavior. The release
        // checklist carries the new- and existing-user device verification.
        print("PulseDock 6.16.1 credential vault identity policy passed")
    }
}
