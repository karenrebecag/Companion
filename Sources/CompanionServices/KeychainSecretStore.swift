import CompanionCore
import Foundation
import Security

/// Keys in the login keychain — the file-based one, which is what `SecItem`
/// targets on macOS unless asked otherwise.
///
/// HACK: this is the legacy keychain, and it is a deliberate choice, not an
/// oversight. The modern data-protection keychain would end the password
/// dialogs for good (its access is bound to the app's identity rather than to
/// an ACL that a re-signing invalidates), but reaching it needs
/// `kSecUseDataProtectionKeychain` together with an `application-identifier`
/// entitlement, and that needs a Team ID this project does not have yet.
/// Upgrade trigger: the day the Apple Developer account exists, move to the
/// data-protection keychain and delete this note.
///
/// What was removed, and why it mattered: this used to set
/// `kSecAttrAccessible` and `kSecAttrSynchronizable: false` under a comment
/// promising "survive lock, never leave this Mac". Apple documents
/// `kSecAttrAccessible` as irrelevant to the file-based keychain, so the
/// attribute did nothing and the promise was not the code's to make. The
/// no-sync half happens to hold — the file keychain does not sync — but by
/// accident, not by that flag. A security comment that overstates is worse
/// than none: it stops the next person from checking.
public struct KeychainSecretStore: SecretStore, Sendable {
    public static let service = "Companion"

    public init() {}

    public func read(_ key: SecretKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try Self.check(status)
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw SecretStoreError.unexpected(Int(status))
        }
        return value
    }

    public func write(_ key: SecretKey, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SecretStoreError.emptyValue }
        let data = Data(trimmed.utf8)

        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(
            query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        if updated != errSecItemNotFound {
            try Self.check(updated)
            return
        }

        var add = query
        add[kSecValueData as String] = data
        try Self.check(SecItemAdd(add as CFDictionary, nil))
    }

    public func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        if status == errSecItemNotFound { return }
        try Self.check(status)
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw SecretStoreError.denied
        case errSecNotAvailable:
            throw SecretStoreError.notAvailable
        default:
            throw SecretStoreError.unexpected(Int(status))
        }
    }
}
