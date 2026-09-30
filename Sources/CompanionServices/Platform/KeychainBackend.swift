import Foundation
import Security

/// Seam over the four `SecItem*` calls `KeychainSecretStore` needs. Tests
/// swap in an in-memory fake so the whole read/write/delete/migrate flow is
/// exercised without ever touching the real login keychain (no password
/// dialogs in CI, no state that outlives a test run).
protocol KeychainOperations: Sendable {
    func copyItemData(query: [String: Any]) -> (status: OSStatus, data: Data?)
    func addItem(attributes: [String: Any]) -> OSStatus
    func updateItem(query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus
    func deleteItem(query: [String: Any]) -> OSStatus
}

/// The real thing: a thin, untested-by-design pass-through to Security. Kept
/// this small on purpose — nothing here is worth a fake of its own.
struct LiveKeychainOperations: KeychainOperations {
    func copyItemData(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func addItem(attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func updateItem(query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
    }

    func deleteItem(query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
