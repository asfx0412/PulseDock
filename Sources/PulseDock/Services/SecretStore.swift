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

    static func read(_ account: String) -> ReadResult {
        var query = nonInteractiveQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return .failed(errSecDecode)
            }
            return .value(value)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .interactionRequired
        default:
            return .failed(status)
        }
    }

    /// Used only after an explicit tap on “解锁凭据”. Keeping this separate from
    /// `read` makes it impossible for a background poll to summon a Keychain UI.
    static func readInteractive(_ account: String) -> ReadResult {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else { return .failed(errSecDecode) }
            return .value(value)
        case errSecItemNotFound: return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
        default: return .failed(status)
        }
    }

    /// Reads a v2 vault after an explicit user-initiated system authentication.
    /// Touch ID is requested first; password is used only when biometric
    /// authentication is unavailable, not enrolled, or locked out.
    static func readSystemAuthenticated(_ account: String) async -> ReadResult {
        let context = LAContext()
        do {
            try await authenticate(context: context, policy: .deviceOwnerAuthenticationWithBiometrics)
        } catch {
            guard shouldFallbackToPassword(error) else { return .interactionRequired }
            do { try await authenticate(context: context, policy: .deviceOwnerAuthentication) }
            catch { return .interactionRequired }
        }
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
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

    private static func shouldFallbackToPassword(_ error: Error) -> Bool {
        let code = (error as? LAError)?.code
        return code == .biometryNotAvailable || code == .biometryNotEnrolled || code == .biometryLockout
    }

    @discardableResult
    static func write(_ value: String, account: String) -> WriteResult {
        guard !value.isEmpty else { return remove(account) }

        let query = nonInteractiveQuery(account)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return .saved
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .interactionRequired
        case errSecItemNotFound:
            var item = nonInteractiveQuery(account)
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            switch addStatus {
            case errSecSuccess: return .saved
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
            default: return .failed(addStatus)
            }
        default:
            return .failed(updateStatus)
        }
    }

    /// Interactive write is only invoked by an explicit “保存全部变更” action.
    static func writeInteractive(_ value: String, account: String) -> WriteResult {
        guard !value.isEmpty else { return removeInteractive(account) }
        let query = baseQuery(account)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess: return .saved
        case errSecItemNotFound:
            var item = baseQuery(account)
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            switch addStatus {
            case errSecSuccess: return .saved
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
            default: return .failed(addStatus)
            }
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .interactionRequired
        default: return .failed(updateStatus)
        }
    }

    /// Writes the v2 item after the caller has already completed the explicit
    /// Touch ID gate in `readSystemAuthenticated`.
    ///
    /// `SecAccessControl(.userPresence)` creates a Data Protection Keychain
    /// item on macOS. That requires an application-identifier/keychain-access-
    /// group entitlement issued by an Apple signing team. PulseDock's local
    /// ad-hoc builds intentionally have no team entitlement, and Security
    /// rejects that add with errSecMissingEntitlement (-34018). Keep the
    /// biometric gate in `LAContext`, then store the v2 payload in the normal
    /// local Login Keychain. All PulseDock access paths require that gate and
    /// background paths remain non-interactive, so this avoids a password sheet
    /// without silently reading a secret in a background refresh.
    static func writeSystemAuthenticated(_ value: String, account: String) -> WriteResult {
        write(value, account: account)
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

    @discardableResult
    static func removeInteractive(_ account: String) -> WriteResult {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
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
        // LAContext alone is not sufficient for every legacy ACL. This flag is
        // the Security.framework-level guarantee that a background lookup fails
        // instead of adding another password sheet to the system queue.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        query[kSecUseAuthenticationContext as String] = nonInteractiveContext()
        return query
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}
