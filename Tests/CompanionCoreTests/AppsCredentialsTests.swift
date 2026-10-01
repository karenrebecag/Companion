import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

/// 20c D6 (M5, spec R3): the companion-apps key used to sit under one flat
/// name, whatever endpoint it was later sent to. It is now bound to the
/// endpoint's host, and a key already stored is moved, never lost.
@Test func appsCredentialsMigrationAndBinding() throws {
    let flat = TestSecretStore([.companionApps: "old-key-of-32-chars-or-more-xxxxxx"])
    let bound = TestHostSecretStore()

    expectEq(try AppsCredentials.key(host: "x.vercel.app", legacy: flat, bound: bound, pin: .observed("x.vercel.app")),
             "old-key-of-32-chars-or-more-xxxxxx", "migra: la clave vieja sigue sirviendo")
    expectEq(try bound.read(.appsKey, host: "x.vercel.app"), "old-key-of-32-chars-or-more-xxxxxx",
             "migra: queda ligada al host")
    expectEq(try flat.read(.companionApps), nil, "migra: la copia plana se borra")

    expectEq(try AppsCredentials.key(host: "x.vercel.app", legacy: flat, bound: bound, pin: .observed("x.vercel.app")),
             "old-key-of-32-chars-or-more-xxxxxx", "migra: la segunda lectura sale de la ligada")
    expectEq(try AppsCredentials.key(host: "evil.example", legacy: flat, bound: bound, pin: .observed("legit.dev")), nil,
             "ligada: la clave del host A no sale para el host B")
}

@Test func appsCredentialsNeverLoseAWorkingKey() throws {
    let flat = TestSecretStore([.companionApps: "old-key"])
    let bound = TestHostSecretStore()
    bound.failWrites = true
    expectEq(try AppsCredentials.key(host: "x.dev", legacy: flat, bound: bound, pin: .observed("x.dev")), "old-key",
             "migra: si el llavero no deja escribir, la clave sigue sirviendo")
    expectEq(try flat.read(.companionApps), "old-key", "migra: y la vieja no se borra hasta poder moverla")

    bound.failWrites = false
    bound.failReads = true
    #expect(throws: SecretStoreError.denied) {
        _ = try AppsCredentials.key(host: "x.dev", legacy: flat, bound: bound, pin: .observed("x.dev"))
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

private let longKey = "old-key-of-32-chars-or-more-xxxxxx"

/// Review D6 (security MEDIUM): a same-uid process can repoint the endpoint
/// in UserDefaults. The flat key must not follow it to a host it was never
/// configured for, and must not linger once it has been bound.
@Test func eagerMigrationBindsTheFlatKeyToTheConfiguredHostOnly() throws {
    let flat = TestSecretStore([.companionApps: longKey])
    let bound = TestHostSecretStore()
    AppsCredentials.migrateFlatKey(configuredHost: "a.dev", legacy: flat, bound: bound)
    expectEq(try bound.read(.appsKey, host: "a.dev"), longKey, "eager: la clave queda ligada al host configurado")
    expectEq(try flat.read(.companionApps), nil, "eager: la plana se retira al arrancar")
    expectEq(try AppsCredentials.key(host: "evil.example", legacy: flat, bound: bound, pin: .observed("legit.dev")), nil,
             "eager: un endpoint cambiado despues no recibe la clave")
}

@Test func anUnboundEndpointChangeYieldsNoKeyWhileTheFlatCopyLingers() throws {
    let flat = TestSecretStore([.companionApps: longKey])
    flat.failDeletes = true
    let bound = TestHostSecretStore()
    AppsCredentials.migrateFlatKey(configuredHost: "a.dev", legacy: flat, bound: bound)
    expectEq(try flat.read(.companionApps), longKey, "la plana sigue ahi porque el borrado fallo")
    expectEq(try AppsCredentials.key(host: "evil.example", legacy: flat, bound: bound, pin: .observed("legit.dev")), nil,
             "aun con la plana viva, otro host no recibe la clave")
    expectEq(try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: .observed("a.dev")), longKey,
             "y el host configurado sigue sirviendose")
}

@Test func aFailedFlatDeleteIsRetriedOnEveryReadUntilItSucceeds() throws {
    let flat = TestSecretStore([.companionApps: longKey])
    flat.failDeletes = true
    let bound = TestHostSecretStore()
    expectEq(try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: .observed("a.dev")), longKey,
             "la clave sirve aunque el borrado falle")
    expectEq(try flat.read(.companionApps), longKey, "la plana sigue mientras el llavero rechaza borrar")
    expectEq(try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: .observed("a.dev")), longKey, "segunda lectura: igual")
    flat.failDeletes = false
    expectEq(try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: .observed("a.dev")), longKey, "sigue sirviendo")
    expectEq(try flat.read(.companionApps), nil, "el borrado se reintento y la copia plana desaparecio")
}

@Test func eagerMigrationNeedsAConfiguredHostAndHonorsTheRecordedOne() throws {
    let flat = TestSecretStore([.companionApps: longKey])
    let bound = TestHostSecretStore()
    AppsCredentials.migrateFlatKey(configuredHost: nil, legacy: flat, bound: bound)
    expectEq(try flat.read(.companionApps), longKey, "sin endpoint no hay a que ligarla: no se toca")
    expectEq(bound.count, 0, "y nada se escribe")

    // A first attempt recorded the host but could not write the key; the
    // endpoint is then swapped before the next launch.
    let flat2 = TestSecretStore([.companionApps: longKey])
    let bound2 = TestHostSecretStore()
    try bound2.write(.appsKeyOrigin, host: AppsCredentials.originSlot, value: "a.dev")
    AppsCredentials.migrateFlatKey(configuredHost: "evil.example", legacy: flat2, bound: bound2)
    expectEq(try bound2.read(.appsKey, host: "a.dev"), longKey, "se liga al host que quedo registrado")
    expectEq(try bound2.read(.appsKey, host: "evil.example"), nil, "no al que aparecio despues")
}

@Test func aSaveWhoseFlatDeleteFailsStillLeavesAUsableKey() throws {
    let flat = TestSecretStore([.companionApps: "stale-key"])
    flat.failDeletes = true
    let bound = TestHostSecretStore()
    try bound.write(.appsKey, host: "old.dev", value: "old-host-key")

    try AppsCredentials.save("new-key", host: "new.dev", previousHost: "old.dev", legacy: flat, bound: bound)
    expectEq(try bound.read(.appsKey, host: "new.dev"), "new-key", "save: la clave nueva quedo ligada")
    expectEq(try bound.read(.appsKey, host: "old.dev"), nil, "save: la del host anterior se retira al final")
    expectEq(try AppsCredentials.key(host: "evil.example", legacy: flat, bound: bound, pin: .observed("legit.dev")), nil,
             "save: la plana que no se pudo borrar no sirve a un host nuevo")
}

@Test func aSaveThatCannotRetireThePreviousHostKeepsTheNewKey() throws {
    let flat = TestSecretStore()
    let bound = TestHostSecretStore()
    try bound.write(.appsKey, host: "old.dev", value: "old-host-key")
    bound.failDeletes = true
    try AppsCredentials.save("new-key", host: "new.dev", previousHost: "old.dev", legacy: flat, bound: bound)
    expectEq(try bound.read(.appsKey, host: "new.dev"), "new-key", "save: no reporta fallo total")
}
