import CompanionCore
import Foundation
import Testing

// Wave 18b. The lease is Incredible's ownership.js as a pure value: who may
// use which tab, judged only from the caller, the owner and the clock.

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func lease(_ tab: Int = 5, owner: String = "chat", at: Date = t0) -> BrowserLease {
    var lease = BrowserLease()
    lease.acquire(tab: tab, caller: owner, now: at)
    return lease
}

@Test func aTabNobodyOwnsIsNotControlledUnlessTheCallerIsTakingIt() {
    let empty = BrowserLease()
    expectEq(empty.authorize(tab: 5, caller: "chat", now: t0, allowTake: false), .notControlled, "sin dueno: no controlada")
    expectEq(empty.authorize(tab: 5, caller: "chat", now: t0, allowTake: true), nil, "tomarla si se puede")
}

@Test func theOwnerMayUseItsTab() {
    expectEq(lease().authorize(tab: 5, caller: "chat", now: t0, allowTake: false), nil, "el dueno usa su pestana")
    expectEq(lease().authorize(tab: 6, caller: "chat", now: t0, allowTake: false), .notControlled, "otra pestana no")
}

@Test func anotherActiveOwnerMakesTheTabBusyEvenForATake() {
    let soon = t0.addingTimeInterval(BrowserLease.takeoverAfter - 1)
    expectEq(lease().authorize(tab: 5, caller: "bridge", now: soon, allowTake: false), .busy, "activo: ocupada")
    expectEq(lease().authorize(tab: 5, caller: "bridge", now: soon, allowTake: true), .busy, "tomar tampoco antes de 120 s")
}

@Test func anOwnerIdleForTwoMinutesCanBeTakenOverButNotUsedThrough() {
    let idle = t0.addingTimeInterval(BrowserLease.takeoverAfter)
    expectEq(lease().authorize(tab: 5, caller: "bridge", now: idle, allowTake: true), nil, "120 s quieta: tomable")
    expectEq(lease().authorize(tab: 5, caller: "bridge", now: idle, allowTake: false), .busy,
             "sin tomar, sigue siendo del otro")
}

@Test func touchingRestartsTheIdleClock() {
    var held = lease()
    held.touch(tab: 5, caller: "chat", now: t0.addingTimeInterval(100))
    expectEq(held.authorize(tab: 5, caller: "bridge", now: t0.addingTimeInterval(200), allowTake: true), .busy,
             "actuo hace 100 s")
    held.touch(tab: 5, caller: "bridge", now: t0.addingTimeInterval(300))
    expectEq(held.owner(of: 5, now: t0), "chat", "quien no es dueno no puede tocarla")
}

@Test func acquiringMovesTheOwner() {
    var held = lease()
    held.acquire(tab: 5, caller: "bridge", now: t0.addingTimeInterval(200))
    expectEq(held.owner(of: 5, now: t0), "bridge", "el nuevo dueno")
}

@Test func idleForTenMinutesReleasesAndReportsTheTabs() {
    var held = lease()
    held.acquire(tab: 9, caller: "bridge", now: t0.addingTimeInterval(500))
    let expired = held.expire(now: t0.addingTimeInterval(BrowserLease.idleRelease))
    expectEq(expired, [5], "solo la de 600 s")
    expectEq(held.owner(of: 5, now: t0), nil, "suelta")
    expectEq(held.owner(of: 9, now: t0), "bridge", "la reciente sigue")
    expectEq(held.authorize(tab: 5, caller: "chat", now: t0.addingTimeInterval(601), allowTake: false), .notControlled,
             "ya no es suya")
}

@Test func anExpiredEntryIsNotAnOwnerEvenBeforeTheSweep() {
    let late = t0.addingTimeInterval(BrowserLease.idleRelease + 1)
    expectEq(lease().authorize(tab: 5, caller: "chat", now: late, allowTake: false), .notControlled,
             "10 min sin uso: ni el dueno la conserva")
    expectEq(lease().authorize(tab: 5, caller: "bridge", now: late, allowTake: true), nil, "y otro la toma sin espera")
}

@Test func atExactlyTenMinutesTheOwnerIsGoneAndAnotherMayTake() {
    let edge = t0.addingTimeInterval(BrowserLease.idleRelease)
    expectEq(lease().owner(of: 5, now: edge), nil, "600 s: sin dueno")
    expectEq(lease().authorize(tab: 5, caller: "chat", now: edge, allowTake: false), .notControlled, "ni el dueno la usa")
    expectEq(lease().authorize(tab: 5, caller: "bridge", now: edge, allowTake: true), nil, "otro la toma")
    let before = t0.addingTimeInterval(BrowserLease.idleRelease - 1)
    expectEq(lease().owner(of: 5, now: before), "chat", "599 s: sigue siendo suya")
}

@Test func releaseAndReleaseAllClearOwnership() {
    var held = lease()
    held.acquire(tab: 6, caller: "bridge", now: t0)
    held.release(tab: 5)
    expectEq(held.owner(of: 5, now: t0), nil, "release suelta una")
    expectEq(held.owner(of: 6, now: t0), "bridge", "y solo esa")
    held.releaseAll()
    expectEq(held.owner(of: 6, now: t0), nil, "releaseAll suelta todo")
}

// MARK: - spawned tabs

private let opener = "https://crm.example/a"

private func child(
    _ id: Int = 20, opener: Int? = 5, created: Date? = t0.addingTimeInterval(4), url: String = "https://crm.example/new"
) -> BrowserTab {
    BrowserTab(id: id, title: "", url: url, active: false, controlled: false, opener: opener, createdAt: created)
}

@Test func aTabBornFromAnOwnedPageShortlyAfterItActedBelongsToItsOwner() {
    expectEq(lease().spawnOwner(of: child(), openerURL: opener, now: t0.addingTimeInterval(5)), "chat", "hija en 4 s: del dueno del opener")
}

@Test func aTabBornTooLateOrWithoutAnOpenerIsNotSpawned() {
    let held = lease()
    expectEq(held.spawnOwner(of: child(created: t0.addingTimeInterval(11)), openerURL: opener, now: t0.addingTimeInterval(12)), nil, "11 s: no")
    expectEq(held.spawnOwner(of: child(created: t0.addingTimeInterval(10)), openerURL: opener, now: t0.addingTimeInterval(12)), "chat",
             "10 s: en el borde, si")
    expectEq(held.spawnOwner(of: child(created: t0.addingTimeInterval(-1)), openerURL: opener, now: t0.addingTimeInterval(12)), nil,
             "nacio antes de que actuara")
    expectEq(held.spawnOwner(of: child(opener: nil), openerURL: opener, now: t0), nil, "sin opener")
    expectEq(held.spawnOwner(of: child(created: nil), openerURL: opener, now: t0), nil, "sin createdAt")
    expectEq(held.spawnOwner(of: child(opener: 99), openerURL: opener, now: t0), nil, "opener que nadie controla")
}

@Test func aNewTabPageIsNeverSpawned() {
    let held = lease()
    for url in ["chrome://newtab/", "chrome://newtab", "chrome://new-tab-page/", "chrome://settings", "about:newtab", ""] {
        expectEq(held.spawnOwner(of: child(url: url), openerURL: opener, now: t0.addingTimeInterval(5)), nil, "\(url): nunca")
    }
}

@Test func aChildOfAnotherOriginIsNeverSpawned() {
    let held = lease()
    for url in ["https://evil.example/x", "http://crm.example/new", "https://crm.example:8443/new"] {
        expectEq(held.spawnOwner(of: child(url: url), openerURL: opener, now: t0.addingTimeInterval(5)), nil, "\(url): otro origen")
    }
    expectEq(held.spawnOwner(of: child(), openerURL: "", now: t0.addingTimeInterval(5)), nil, "sin url del opener: cerrado")
}

@Test func releasingByOwnerReturnsOnlyThatOwnersTabs() {
    var held = lease()
    held.acquire(tab: 6, caller: "bridge", now: t0)
    held.acquire(tab: 7, caller: "bridge", now: t0)
    expectEq(held.releaseAll(owner: "bridge"), [6, 7], "las del puente")
    expectEq(held.owner(of: 5, now: t0), "chat", "la del chat sigue")
    expectEq(held.owner(of: 6, now: t0), nil, "suelta")
}

@Test func pruningKeepsOnlyTabsStillListed() {
    var held = lease()
    held.acquire(tab: 6, caller: "bridge", now: t0)
    held.prune(keeping: [6], asOf: held.sequence)
    expectEq(held.owner(of: 5, now: t0), nil, "ya no existe")
    expectEq(held.owner(of: 6, now: t0), "bridge", "sigue")
}

@Test func anExpiredOwnerIsNotReportedByOwnerOf() {
    expectEq(lease().owner(of: 5, now: t0.addingTimeInterval(BrowserLease.idleRelease + 1)), nil, "expirada: sin dueno")
}

@Test func aTabAlreadyOwnedIsNotReassignedBySpawning() {
    var held = lease()
    held.acquire(tab: 20, caller: "bridge", now: t0)
    expectEq(held.spawnOwner(of: child(), openerURL: opener, now: t0.addingTimeInterval(5)), nil, "ya tiene dueno")
}

// MARK: - copy

@Test func theDenialsCarryIncredibleStyleGuidance() {
    for language in [AppLanguage.en, .es] {
        let lost = BrowserCopy.leaseDenial(.notControlled, tab: 7, language)
        expect(lost.contains("browser_take") && lost.contains("browser_open"), "\(language): dice como reclamarla")
        expect(lost.contains("7"), "\(language): nombra la pestana")
        let busy = BrowserCopy.leaseDenial(.busy, tab: 7, language)
        expect(busy.contains("browser_open"), "\(language): ocupada: abre una nueva")
        expect(busy != lost, "\(language): son mensajes distintos")
    }
    expect(BrowserCopy.leaseDenial(.notControlled, tab: 7, .es).contains("tómala"), "es: 'tómala con browser_take'")
}
