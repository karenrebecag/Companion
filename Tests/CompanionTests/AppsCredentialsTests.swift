import CompanionCore
import Foundation
import Testing

/// 20c D6 (M5, spec R3): the companion-apps key used to sit under one flat
/// name, whatever endpoint it was later sent to. It is now bound to the
/// endpoint's host, and a key already stored is moved, never lost.
@Test func appsCredentialsMigrationAndBinding() throws {
    let flat = TestSecretStore([.companionApps: "old-key-of-32-chars-or-more-xxxxxx"])
    let bound = TestHostSecretStore()

    expectEq(try AppsCredentials.key(host: "x.vercel.app", legacy: flat, bound: bound),
             "old-key-of-32-chars-or-more-xxxxxx", "migra: la clave vieja sigue sirviendo")
    expectEq(try bound.read(.appsKey, host: "x.vercel.app"), "old-key-of-32-chars-or-more-xxxxxx",
             "migra: queda ligada al host")
    expectEq(try flat.read(.companionApps), nil, "migra: la copia plana se borra")

    expectEq(try AppsCredentials.key(host: "x.vercel.app", legacy: flat, bound: bound),
             "old-key-of-32-chars-or-more-xxxxxx", "migra: la segunda lectura sale de la ligada")
    expectEq(try AppsCredentials.key(host: "evil.example", legacy: flat, bound: bound), nil,
             "ligada: la clave del host A no sale para el host B")
}

@Test func appsCredentialsNeverLoseAWorkingKey() throws {
    let flat = TestSecretStore([.companionApps: "old-key"])
    let bound = TestHostSecretStore()
    bound.failWrites = true
    expectEq(try AppsCredentials.key(host: "x.dev", legacy: flat, bound: bound), "old-key",
             "migra: si el llavero no deja escribir, la clave sigue sirviendo")
    expectEq(try flat.read(.companionApps), "old-key", "migra: y la vieja no se borra hasta poder moverla")

    bound.failWrites = false
    bound.failReads = true
    #expect(throws: SecretStoreError.denied) {
        _ = try AppsCredentials.key(host: "x.dev", legacy: flat, bound: bound)
    }
    expectEq(try flat.read(.companionApps), "old-key", "migra: un llavero que no responde no borra nada")
}

@Test func appsCredentialsSaveBindsToTheHostAndRetiresTheOld() throws {
    let flat = TestSecretStore([.companionApps: "stale"])
    let bound = TestHostSecretStore()
    try bound.write(.appsKey, host: "old.dev", value: "old-host-key")

    try AppsCredentials.save("new-key", host: "new.dev", previousHost: "old.dev", legacy: flat, bound: bound)
    expectEq(try bound.read(.appsKey, host: "new.dev"), "new-key", "save: ligada al host nuevo")
    expectEq(try bound.read(.appsKey, host: "old.dev"), nil, "save: el host anterior ya no guarda clave")
    expectEq(try flat.read(.companionApps), nil, "save: la plana se retira")

    bound.failWrites = true
    #expect(throws: SecretStoreError.denied) {
        try AppsCredentials.save("k", host: "z.dev", previousHost: nil, legacy: flat, bound: bound)
    }
}
