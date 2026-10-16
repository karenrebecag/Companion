import CompanionCore
import CompanionServices
import Foundation

/// The "siempre permitir" rules the person kept. Read on every step, so a
/// revoke in Ajustes applies to the next sheet without a restart.
package enum AlwaysAllowPreference {
    nonisolated private static let key = "companion.alwaysAllow"

    nonisolated package static var list: AlwaysAllowList {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return AlwaysAllowList() }
            do {
                return try JSONDecoder().decode(AlwaysAllowList.self, from: data)
            } catch {
                // Unreadable rules grant nothing: the sheets come back, which is the safe side.
                Log.app("always allow: stored rules unreadable (\(error.localizedDescription))")
                return AlwaysAllowList()
            }
        }
        set {
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(newValue), forKey: key)
            } catch {
                Log.app("always allow: rules not saved (\(error.localizedDescription))")
            }
        }
    }
}
