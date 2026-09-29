import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

/// 20c D6 (M5): a secret saved for one host must never be readable as
/// another host's, and it lives in the same single Keychain item as the rest
/// (one password dialog per launch, not one per host).
@Test @MainActor func hostSecretStoreRoundTripAndBinding() throws {
    let fake = FakeKeychainOperations()
    let store = KeychainSecretStore(backend: fake)

    try store.write(.mcpToken, host: "a.example.dev", value: "tok-a")
    expectEq(try store.read(.mcpToken, host: "a.example.dev"), "tok-a", "host: el valor vuelve por su host")
    expectEq(try store.read(.mcpToken, host: "b.example.dev"), nil, "host: el token de A no se lee como de B")
    expectEq(try store.read(.appsKey, host: "a.example.dev"), nil, "host: otra clase, otro secreto")
    expectEq(try store.read(.mcpToken, host: "A.Example.DEV"), "tok-a", "host: sin distinguir mayusculas")

    try store.write(.mcpToken, host: "b.example.dev", value: "tok-b")
    expectEq(try store.read(.mcpToken, host: "a.example.dev"), "tok-a", "host: escribir B no pisa A")
    expectEq(fake.storedItemCount, 1, "host: todo cabe en el item unico del llavero")

    let fresh = KeychainSecretStore(backend: fake)
    expectEq(try fresh.read(.mcpToken, host: "b.example.dev"), "tok-b", "host: sobrevive a un proceso nuevo")

    try store.delete(.mcpToken, host: "a.example.dev")
    expectEq(try store.read(.mcpToken, host: "a.example.dev"), nil, "host: borrar quita solo ese host")
    expectEq(try store.read(.mcpToken, host: "b.example.dev"), "tok-b", "host: el otro sigue")
}

@Test @MainActor func hostSecretStoreLeavesFlatKeysAlone() throws {
    let store = KeychainSecretStore(backend: FakeKeychainOperations())
    try store.write(.openAI, value: "sk-live")
    try store.write(.appsKey, host: "x.dev", value: "k")
    expectEq(try store.read(.openAI), "sk-live", "host: la clave plana no se toca")
    try store.delete(.appsKey, host: "x.dev")
    expectEq(try store.read(.openAI), "sk-live", "host: borrar por host no borra la plana")
}

@Test @MainActor func hostSecretStoreRefusesABadHostOrValue() {
    let store = KeychainSecretStore(backend: FakeKeychainOperations())
    for bad in ["", "   ", "a b", "a@b"] {
        #expect(throws: SecretStoreError.invalidHost, "host malo: \(bad)") {
            try store.write(.mcpToken, host: bad, value: "t")
        }
        #expect(throws: SecretStoreError.invalidHost, "host malo (lectura): \(bad)") {
            _ = try store.read(.mcpToken, host: bad)
        }
    }
    #expect(throws: SecretStoreError.emptyValue) {
        try store.write(.mcpToken, host: "a.dev", value: "  ")
    }
}
