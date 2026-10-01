import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

private let flatKey = "old-key-of-32-chars-or-more-xxxxxx"

/// Review D6 (security MEDIUM-1): the flat key is only ever bound to the
/// endpoint this launch saw, so a same-uid rewrite of the defaults after
/// launch, or while the Keychain could not be read, cannot receive it.
@Test func aKeychainThatCannotBeReadAtLaunchStillPinsTheObservedEndpoint() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    bound.failReads = true
    let pin = AppsCredentials.launch(endpoint: "https://a.dev", legacy: flat, bound: bound)
    expectEq(pin, .observed("a.dev"), "launch: the host seen is kept even if the Keychain refused")
    bound.failReads = false

    expectEq(try AppsCredentials.key(host: "swapped.example", legacy: flat, bound: bound, pin: pin), nil,
             "launch: an endpoint rewritten afterwards does not get the flat key")
    expectEq(try flat.read(.companionApps), flatKey, "launch: and the key is not lost")
    expectEq(try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: pin), flatKey,
             "launch: the endpoint the launch saw still gets it")
}

@Test func withNoEndpointAtLaunchTheFlatKeyBindsToNoLaterOne() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    let pin = AppsCredentials.launch(endpoint: nil, legacy: flat, bound: bound)
    expectEq(pin, .unobserved, "launch: nothing was seen")
    expectEq(try AppsCredentials.key(host: "late.example", legacy: flat, bound: bound, pin: pin), nil,
             "launch: an endpoint that appears later is not bound to the flat key")
    expectEq(try flat.read(.companionApps), flatKey, "launch: the key stays put")
    expectEq(bound.count, 0, "launch: and nothing is written")
}

@Test func anEndpointThatIsNotHttpsIsNotObservedAtLaunch() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    let pin = AppsCredentials.launch(endpoint: "http://a.dev", legacy: flat, bound: bound)
    expectEq(pin, .unobserved, "launch: the same validation the runner uses")
    expectEq(bound.count, 0, "launch: nothing bound")
}

@Test func launchMovesTheFlatKeyToTheConfiguredEndpointHost() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    let pin = AppsCredentials.launch(endpoint: " https://A.dev/ ", legacy: flat, bound: bound)
    expectEq(pin, .observed("a.dev"), "launch: host normalized")
    expectEq(try bound.read(.appsKey, host: "a.dev"), flatKey, "launch: bound to the configured host")
    expectEq(try flat.read(.companionApps), nil, "launch: flat retired")
}

/// Review D6 (security LOW-3): a flat copy whose recorded origin has no bound
/// key is the only copy of that key; a bound hit for another host must not
/// retire it.
@Test func aBoundHitForAnotherHostDoesNotRetireTheOnlyCopyOfTheOriginsKey() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    try bound.write(.appsKeyOrigin, host: AppsCredentials.originSlot, value: "h1.dev")
    try bound.write(.appsKey, host: "h2.dev", value: "h2-key")
    expectEq(try AppsCredentials.key(host: "h2.dev", legacy: flat, bound: bound, pin: .observed("h2.dev")),
             "h2-key", "the bound key of the current host serves")
    expectEq(try flat.read(.companionApps), flatKey, "the flat copy of h1's key survives")
}

@Test func aBoundHitRetiresTheFlatCopyOnceItsOriginHasItsOwn() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    try bound.write(.appsKeyOrigin, host: AppsCredentials.originSlot, value: "h1.dev")
    try bound.write(.appsKey, host: "h1.dev", value: flatKey)
    try bound.write(.appsKey, host: "h2.dev", value: "h2-key")
    _ = try AppsCredentials.key(host: "h2.dev", legacy: flat, bound: bound, pin: .unobserved)
    expectEq(try flat.read(.companionApps), nil, "origin is safe: the leftover flat copy goes")
}

@Test func aBoundHitOnTheRecordedHostRetiresTheFlatCopy() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    try bound.write(.appsKeyOrigin, host: AppsCredentials.originSlot, value: "h1.dev")
    try bound.write(.appsKey, host: "h1.dev", value: flatKey)
    _ = try AppsCredentials.key(host: "h1.dev", legacy: flat, bound: bound, pin: .unobserved)
    expectEq(try flat.read(.companionApps), nil, "the recorded host has its bound copy: flat retired")
}

@Test func aBoundHitWithNoRecordedOriginRetiresTheFlatCopy() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    try bound.write(.appsKey, host: "h1.dev", value: "bound")
    _ = try AppsCredentials.key(host: "h1.dev", legacy: flat, bound: bound, pin: .unobserved)
    expectEq(try flat.read(.companionApps), nil, "no origin recorded: nothing to protect")
}

@Test func aFlatKeyIsStillMovedWhenTheBoundWriteFailsAtLaunch() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    bound.failWrites = true
    let pin = AppsCredentials.launch(endpoint: "https://a.dev", legacy: flat, bound: bound)
    expectEq(try flat.read(.companionApps), flatKey, "launch: a refused write keeps the flat key")
    bound.failWrites = false
    expectEq(try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: pin), flatKey,
             "launch: the retry serves and binds it")
    expectEq(try bound.read(.appsKey, host: "a.dev"), flatKey, "launch: now bound")
}

@Test func aRecordedOriginWithNoBoundKeyYetServesTheRecordedHostAndBinds() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    try bound.write(.appsKeyOrigin, host: AppsCredentials.originSlot, value: "a.dev")
    expectEq(try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: .unobserved), flatKey,
             "the recorded host is served without needing a pin")
    expectEq(try bound.read(.appsKey, host: "a.dev"), flatKey, "and bound on the way")
    expectEq(try AppsCredentials.key(host: "b.dev", legacy: flat, bound: bound, pin: .unobserved), nil,
             "another host gets nothing")
}

@Test func aThrowingBoundReadPropagatesAndTouchesNothing() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    bound.failReads = true
    #expect(throws: SecretStoreError.denied) {
        _ = try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: .observed("a.dev"))
    }
    expectEq(try flat.read(.companionApps), flatKey, "an unreadable Keychain deletes nothing")
}

/// Known limitation, pinned so a future fix flips it on purpose: the flat
/// key never recorded a host, so an endpoint swapped between the app update
/// and its first launch is indistinguishable from the user's own setting.
@Test func knownLimitationAnEndpointSwappedBeforeTheFirstLaunchReceivesTheFlatKey() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    AppsCredentials.migrateFlatKey(configuredHost: "swapped.example", legacy: flat, bound: bound)
    expectEq(try bound.read(.appsKey, host: "swapped.example"), flatKey,
             "HACK window: the first launch binds to whatever the endpoint says")
}

/// Review D6 (security MEDIUM): with no recorded origin the flat key may be
/// the only copy of the launch host's key, so a bound hit for another host
/// must not retire it.
@Test func anUnrecordedOriginKeepsTheFlatKeyWhenAnotherHostHasABoundKey() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    bound.failReads = true
    let pin = AppsCredentials.launch(endpoint: "https://a.dev", legacy: flat, bound: bound)
    bound.failReads = false
    try bound.write(.appsKey, host: "b.dev", value: "b-key-of-32-chars-or-more-xxxxxxx")

    expectEq(try AppsCredentials.key(host: "b.dev", legacy: flat, bound: bound, pin: pin),
             "b-key-of-32-chars-or-more-xxxxxxx", "the bound key is served")
    expectEq(try flat.read(.companionApps), flatKey, "the launch host's only copy survives")
}

@Test func anUnrecordedOriginRetiresTheFlatKeyForTheLaunchHost() throws {
    let flat = TestSecretStore([.companionApps: flatKey])
    let bound = TestHostSecretStore()
    bound.failReads = true
    let pin = AppsCredentials.launch(endpoint: "https://a.dev", legacy: flat, bound: bound)
    bound.failReads = false
    try bound.write(.appsKey, host: "a.dev", value: flatKey)

    _ = try AppsCredentials.key(host: "a.dev", legacy: flat, bound: bound, pin: pin)
    expectEq(try flat.read(.companionApps), nil, "the launch host has its own copy: flat retired")
}
