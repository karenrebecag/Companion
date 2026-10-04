import CompanionTestKit
import Foundation
import Testing

/// A throwaway defaults domain: the spoken-language reads must never touch
/// `UserDefaults.standard`, which a developer's own Settings would leak into.
func withSpokenSuite(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "spokenLanguage.\(UUID().uuidString)"
    guard let suite = UserDefaults(suiteName: name) else {
        expect(false, "suite: UserDefaults no creó el dominio")
        return
    }
    defer { suite.removePersistentDomain(forName: name) }
    try body(suite)
}

@MainActor
func withSpokenSuiteAsync(_ body: (UserDefaults) async throws -> Void) async rethrows {
    let name = "spokenLanguage.\(UUID().uuidString)"
    guard let suite = UserDefaults(suiteName: name) else {
        expect(false, "suite: UserDefaults no creó el dominio")
        return
    }
    defer { suite.removePersistentDomain(forName: name) }
    try await body(suite)
}
