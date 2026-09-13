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
        precondition(CredentialVault.systemAuthenticatedAccount == "credential-vault-v2")
        let vault = CredentialVault(values: ["one": "1"])
        precondition(vault["one"] == "1")
        print("PulseDock 6.4.0 unified credential vault policy passed")
    }
}
