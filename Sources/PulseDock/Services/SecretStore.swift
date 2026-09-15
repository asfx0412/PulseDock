import Foundation
import LocalAuthentication
import Security

/// Small, non-interactive Keychain wrapper.
///
/// PulseDock is currently distributed with an ad-hoc signature. macOS can therefore
/// decide that an item written by an older build belongs to a different application
/// identity and show an authorization dialog. Background monitors must never summon
/// that dialog, so every operation explicitly disables authentication UI. A denied or
/// legacy item is surfaced to Settings as `interactionRequired` and can be repaired by
/// deleting the old item in Keychain Access and saving it again.
enum SecretStore {
    static let service = "com.pulsedock.monitor"

    enum ReadResult: Equatable {
        case value(String)
        case missing
        case interactionRequired
        case failed(OSStatus)
    }

    enum WriteResult: Equatable {
        case saved
        case removed
        case interactionRequired
        case failed(OSStatus)
    }

    /// Reads a v4 vault after an explicit user-initiated system authentication.
    /// This is a strict Touch ID path. It never falls back to a macOS password:
    /// users who choose this mode requested a biometric-only vault unlock.
    static func readSystemAuthenticated(_ account: String) async -> ReadResult {
        let context = LAContext()
        do {
            try await authenticate(context: context, policy: .deviceOwnerAuthenticationWithBiometrics)
        } catch {
            return .interactionRequired
        }
        // Do not give Keychain a second chance to display its own login
        // password sheet after Touch ID has completed. v4 is a fresh ordinary
        // local Keychain item; the explicit LAContext gate authorizes access.
        // A Keychain mismatch becomes a recoverable error, never an
        // unexpected password prompt.
        var query = nonInteractiveQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return .failed(errSecDecode) }
            return .value(value)
        case errSecItemNotFound: return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
        default: return .failed(status)
        }
    }

    private static func authenticate(context: LAContext, policy: LAPolicy) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: "解锁 PulseDock 凭据保险库") { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? LAError(.authenticationFailed)) }
            }
        }
    }

    /// Writes the v4 item after the caller has already completed the explicit
    /// Touch ID gate in `readSystemAuthenticated`.
    ///
    /// Data-protection `.userPresence` requires an entitlement that ad-hoc
    /// releases do not have. Legacy `SecAccess` ACLs also cannot be added to
    /// the modern Data Protection Keychain on current macOS. v4 therefore
    /// uses a fresh ordinary local item, with Touch ID enforced by the explicit
    /// `LAContext` gate before this method, and every Keychain operation UI-free.
    static func writeSystemAuthenticated(_ value: String, account: String) -> WriteResult {
        // Keep the non-interactive rule visible at this boundary as well as in
        // this method: no future refactor may route a Touch ID save through an
        // interactive Keychain API.
        guard !value.isEmpty else { return remove(account) }
        var item = nonInteractiveQuery(account)
        item[kSecValueData as String] = Data(value.utf8)
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess: return .saved
        case errSecDuplicateItem:
            let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
            let updateStatus = SecItemUpdate(nonInteractiveQuery(account) as CFDictionary, attributes as CFDictionary)
            switch updateStatus {
            case errSecSuccess: return .saved
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
            default: return .failed(updateStatus)
            }
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
        default: return .failed(addStatus)
        }
    }

    @discardableResult
    static func remove(_ account: String) -> WriteResult {
        let query = nonInteractiveQuery(account)
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound: return .removed
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
        default: return .failed(status)
        }
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func nonInteractiveQuery(_ account: String) -> [String: Any] {
        var query = baseQuery(account)
        // This is the Security.framework-level guarantee that a background
        // lookup fails instead of adding another password sheet to the system
        // queue. Do not attach LAContext: generic-password entries reject it
        // with errSecParam; Touch ID is evaluated before the v4 read.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return query
    }
}
