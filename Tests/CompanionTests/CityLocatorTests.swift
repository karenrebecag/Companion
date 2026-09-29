import CompanionCore
@testable import CompanionServices
import CoreLocation
import Foundation
import Testing

// Wave 16h-3 QA: the CoreLocation locator with both sides of the system
// played by fakes and the clock in the test's hand, so a deadline is a fact
// of the test and not of timing.

@MainActor
private final class FakeManager: LocationManaging {
    var authorizationStatus: CLAuthorizationStatus
    var onAuthorizationChange: (@MainActor @Sendable (CLAuthorizationStatus) -> Void)?
    var onLocation: (@MainActor @Sendable (CLLocation?) -> Void)?
    private(set) var permissionRequests = 0
    private(set) var locationRequests = 0

    init(_ status: CLAuthorizationStatus) { authorizationStatus = status }

    func requestPermission() { permissionRequests += 1 }
    func requestLocation() { locationRequests += 1 }

    func grant() {
        authorizationStatus = .authorizedAlways
        onAuthorizationChange?(.authorizedAlways)
    }

    func deliver(_ location: CLLocation?) { onLocation?(location) }
}

/// A sleep that only ends when the test fires that duration.
private final class ManualSleep: @unchecked Sendable {
    private struct Sleeper {
        let id: Int
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var sleepers: [Sleeper] = []
    private var counter = 0

    var pending: [Duration] { lock.withLock { sleepers.map(\.duration) } }

    func sleep(_ duration: Duration) async throws {
        let id = lock.withLock { () -> Int in
            counter += 1
            return counter
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                lock.withLock { sleepers.append(Sleeper(id: id, duration: duration, continuation: continuation)) }
            }
        } onCancel: {
            let gone = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            gone?.continuation.resume(throwing: CancellationError())
        }
    }

    func fire(_ duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            let due = sleepers.filter { $0.duration == duration }
            sleepers.removeAll { $0.duration == duration }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

/// A geocoder that answers only when released, and ignores cancellation the
/// way a stuck network call would.
private final class GatedGeocode: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<UserLocation?, Never>] = []
    private var asked = 0
    var calls: Int { lock.withLock { asked } }

    func geocode(_ location: CLLocation) async -> UserLocation? {
        await withCheckedContinuation { continuation in
            lock.withLock {
                asked += 1
                waiting.append(continuation)
            }
        }
    }

    func release(_ answer: UserLocation?) {
        let all = lock.withLock { () -> [CheckedContinuation<UserLocation?, Never>] in
            defer { waiting = [] }
            return waiting
        }
        for continuation in all { continuation.resume(returning: answer) }
    }
}

private let somewhere = CLLocation(latitude: 18.9186, longitude: -99.2342)
private let cuernavaca = UserLocation(city: "Cuernavaca", country: "México")
private let madrid = UserLocation(city: "Madrid", country: "España")

@MainActor
private func locator(
    _ status: CLAuthorizationStatus, clock: ManualSleep = ManualSleep(), geocode: GatedGeocode = GatedGeocode()
) -> (CoreLocationCityLocator, FakeManager, ManualSleep, GatedGeocode) {
    let manager = FakeManager(status)
    let made = CoreLocationCityLocator(
        manager: manager, sleep: { try await clock.sleep($0) }, geocode: { await geocode.geocode($0) })
    return (made, manager, clock, geocode)
}

// MARK: - No permission

@Test(.timeLimit(.minutes(1))) @MainActor func testADeniedOrRestrictedLocationIsNilWithoutAskingOrHanging() async {
    for status in [CLAuthorizationStatus.denied, .restricted] {
        for prompting in [false, true] {
            let (made, manager, _, _) = locator(status)
            expect(await made.current(prompting: prompting) == nil, "permiso (\(status.rawValue), pedir=\(prompting)): nil")
            expectEq(manager.locationRequests, 0, "permiso (\(status.rawValue)): jamás se pide una posición")
            expectEq(manager.permissionRequests, 0, "permiso (\(status.rawValue)): ni se vuelve a abrir el diálogo")
        }
    }
}

@Test(.timeLimit(.minutes(1))) @MainActor func testAnUndecidedLocationNeverOpensTheDialogUnlessAsked() async {
    let (made, manager, _, _) = locator(.notDetermined)
    expect(await made.current(prompting: false) == nil, "sin decidir y sin pedir: nil")
    expectEq(manager.permissionRequests, 0, "sin decidir y sin pedir: no aparece el diálogo")
    expectEq(manager.locationRequests, 0, "sin decidir y sin pedir: tampoco se pide posición")
}

@Test(.timeLimit(.minutes(1))) @MainActor func testADialogNobodyAnswersEndsAtThePermissionDeadline() async {
    let (made, manager, clock, _) = locator(.notDetermined)
    async let result = made.current(prompting: true)
    await pumpUntil("diálogo: pidió el permiso y armó su plazo") {
        manager.permissionRequests == 1 && clock.pending.contains(CoreLocationCityLocator.permissionWait)
    }
    clock.fire(CoreLocationCityLocator.permissionWait)
    expect(await result == nil, "diálogo sin respuesta: nil al vencer el plazo")
    expectEq(manager.locationRequests, 0, "diálogo sin respuesta: no se pidió posición sin permiso")
}

@Test(.timeLimit(.minutes(1))) @MainActor func testAGrantMadeInTheDialogLeadsToAFixAndACity() async {
    let (made, manager, clock, geocode) = locator(.notDetermined)
    async let result = made.current(prompting: true)
    await pumpUntil("permiso: diálogo abierto") { manager.permissionRequests == 1 }
    manager.grant()
    await pumpUntil("permiso: concedido, pide una posición") { manager.locationRequests == 1 }
    manager.deliver(somewhere)
    await pumpUntil("permiso: nombra la ciudad") { geocode.calls == 1 }
    geocode.release(cuernavaca)
    expectEq(await result, cuernavaca, "permiso concedido: la ciudad")
    expect(!clock.pending.contains(CoreLocationCityLocator.permissionWait), "permiso: su plazo se cancela al responder")
}

@Test(.timeLimit(.minutes(1))) @MainActor func testADenialInTheDialogEndsAtOnceAndCancelsThePermissionDeadline() async {
    let (made, manager, clock, _) = locator(.notDetermined)
    async let result = made.current(prompting: true)
    await pumpUntil("negado: diálogo abierto con su plazo") {
        manager.permissionRequests == 1 && clock.pending.contains(CoreLocationCityLocator.permissionWait)
    }
    manager.authorizationStatus = .denied
    manager.onAuthorizationChange?(.denied)
    expect(await result == nil, "negado en el diálogo: nil sin esperar al plazo")
    expectEq(manager.locationRequests, 0, "negado en el diálogo: jamás se pide una posición")
    await pumpUntil("negado en el diálogo: el plazo de permiso se canceló") {
        !clock.pending.contains(CoreLocationCityLocator.permissionWait)
    }
}

@Test(.timeLimit(.minutes(1))) @MainActor func testASecondAskerWhileTheDialogIsOpenEndsTheFirstAndTheSecondStaysAlive() async {
    let (made, manager, clock, geocode) = locator(.notDetermined)
    async let first = made.current(prompting: true)
    await pumpUntil("dos: la primera abrió el diálogo") { manager.permissionRequests == 1 }
    async let second = made.current(prompting: true)
    await pumpUntil("dos: la segunda pide el suyo") { manager.permissionRequests == 2 }
    expect(await first == nil, "dos: la primera termina con nil, no se queda colgada")
    await pumpUntil("dos: solo queda el plazo de la segunda") {
        clock.pending.filter { $0 == CoreLocationCityLocator.permissionWait }.count == 1
    }
    manager.grant()
    await pumpUntil("dos: la segunda sigue viva y pide su posición") { manager.locationRequests == 1 }
    manager.deliver(somewhere)
    await pumpUntil("dos: y nombra la ciudad") { geocode.calls == 1 }
    geocode.release(cuernavaca)
    expectEq(await second, cuernavaca, "dos: la segunda recibe la respuesta")
}

// MARK: - The deadlines

@Test(.timeLimit(.minutes(1))) @MainActor func testAManagerThatNeverAnswersEndsAtTheFixDeadline() async {
    let (made, manager, clock, _) = locator(.authorizedAlways)
    async let result = made.current(prompting: false)
    await pumpUntil("posición: pedida y con plazo") {
        manager.locationRequests == 1 && clock.pending.contains(CoreLocationCityLocator.fixWait)
    }
    clock.fire(CoreLocationCityLocator.fixWait)
    expect(await result == nil, "posición sin respuesta: nil al vencer el plazo")
}

@Test(.timeLimit(.minutes(1))) @MainActor func testAFailedFixIsNilAtOnce() async {
    let (made, manager, _, _) = locator(.authorizedAlways)
    async let result = made.current(prompting: false)
    await pumpUntil("posición: pedida") { manager.locationRequests == 1 }
    manager.deliver(nil)
    expect(await result == nil, "posición fallida: nil sin esperar al plazo")
}

@Test(.timeLimit(.minutes(1))) @MainActor func testAGeocodeThatNeverAnswersEndsAtItsDeadlineAndIsNotCached() async {
    let (made, manager, clock, geocode) = locator(.authorizedAlways)
    let cached = CachedCityLocator(made)
    async let first = cached.current(prompting: false)
    await pumpUntil("geocode: posición pedida") { manager.locationRequests == 1 }
    manager.deliver(somewhere)
    await pumpUntil("geocode: consulta y plazo armados") {
        geocode.calls == 1 && clock.pending.contains(CoreLocationCityLocator.geocodeWait)
    }
    clock.fire(CoreLocationCityLocator.geocodeWait)
    expect(await first == nil, "geocode colgado: nil al vencer, aunque no obedezca la cancelación")
    async let second = cached.current(prompting: false)
    await pumpUntil("geocode: el fallo no se cacheó, se vuelve a preguntar") { manager.locationRequests == 2 }
    manager.deliver(somewhere)
    await pumpUntil("geocode: segunda consulta") { geocode.calls == 2 }
    geocode.release(cuernavaca)
    expectEq(await second, cuernavaca, "geocode: la segunda vez sí responde")
}

@Test(.timeLimit(.minutes(1))) @MainActor func testAGeocodeThatAnswersFirstReleasesItsDeadlineTimer() async {
    let (made, manager, clock, geocode) = locator(.authorizedAlways)
    async let result = made.current(prompting: false)
    await pumpUntil("plazo liberado: posición pedida") { manager.locationRequests == 1 }
    manager.deliver(somewhere)
    await pumpUntil("plazo liberado: geocode con plazo") {
        geocode.calls == 1 && clock.pending.contains(CoreLocationCityLocator.geocodeWait)
    }
    geocode.release(cuernavaca)
    expectEq(await result, cuernavaca, "plazo liberado: responde la ciudad")
    await pumpUntil("plazo liberado: el temporizador del plazo se canceló, no queda dormido") {
        !clock.pending.contains(CoreLocationCityLocator.geocodeWait)
    }
}

// MARK: - Late answers

@Test(.timeLimit(.minutes(1))) @MainActor func testALateGeocodeAnswerNeverLeaksIntoTheNextLookup() async {
    let (made, manager, clock, geocode) = locator(.authorizedAlways)
    let cached = CachedCityLocator(made)
    async let first = cached.current(prompting: true)
    await pumpUntil("tardía: posición pedida") { manager.locationRequests == 1 }
    manager.deliver(somewhere)
    await pumpUntil("tardía: geocode con plazo") {
        geocode.calls == 1 && clock.pending.contains(CoreLocationCityLocator.geocodeWait)
    }
    clock.fire(CoreLocationCityLocator.geocodeWait)
    expect(await first == nil, "tardía: la primera venció")
    geocode.release(cuernavaca)
    async let second = cached.current(prompting: true)
    await pumpUntil("tardía: la segunda pide su propia posición") { manager.locationRequests == 2 }
    manager.deliver(somewhere)
    await pumpUntil("tardía: la segunda nombra la suya") { geocode.calls == 2 }
    geocode.release(madrid)
    expectEq(await second, madrid, "tardía: la respuesta vieja no contesta a la lookup nueva")
}

@Test(.timeLimit(.minutes(1))) @MainActor func testALateFixWithNobodyWaitingIsDroppedAndTheNextLookupWaitsForItsOwn() async {
    let (made, manager, clock, geocode) = locator(.authorizedAlways)
    async let first = made.current(prompting: false)
    await pumpUntil("fix tardío: primera pide") {
        manager.locationRequests == 1 && clock.pending.contains(CoreLocationCityLocator.fixWait)
    }
    clock.fire(CoreLocationCityLocator.fixWait)
    expect(await first == nil, "fix tardío: la primera venció")
    manager.deliver(somewhere)
    expectEq(geocode.calls, 0, "fix tardío: sin nadie esperando, no se nombra nada")
    async let second = made.current(prompting: false)
    await pumpUntil("fix tardío: la segunda pide su propia posición") { manager.locationRequests == 2 }
    expectEq(geocode.calls, 0, "fix tardío: la vieja no la contesta")
    manager.deliver(somewhere)
    await pumpUntil("fix tardío: con la suya nombra") { geocode.calls == 1 }
    geocode.release(cuernavaca)
    expectEq(await second, cuernavaca, "fix tardío: la segunda responde con su propia posición")
}

// MARK: - Privacy

@Test(.timeLimit(.minutes(1))) @MainActor func testTheLocatorLogsNeverCarryTheCityNorTheCoordinates() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("locator-\(UUID().uuidString).log")
    defer { do { try FileManager.default.removeItem(at: file) } catch {} }
    await Log.capturing(to: file) {
        let (ok, manager, _, geocode) = locator(.authorizedAlways)
        async let named = ok.current(prompting: false)
        await pumpUntil("log: posición pedida") { manager.locationRequests == 1 }
        manager.deliver(somewhere)
        await pumpUntil("log: geocode") { geocode.calls == 1 }
        geocode.release(cuernavaca)
        _ = await named

        let (failing, failingManager, clock, failingGeocode) = locator(.authorizedAlways)
        async let unnamed = failing.current(prompting: false)
        await pumpUntil("log: posición pedida (fallida)") { failingManager.locationRequests == 1 }
        failingManager.deliver(somewhere)
        await pumpUntil("log: geocode colgado") {
            failingGeocode.calls == 1 && clock.pending.contains(CoreLocationCityLocator.geocodeWait)
        }
        clock.fire(CoreLocationCityLocator.geocodeWait)
        _ = await unnamed
    }
    let log = try String(contentsOf: file, encoding: .utf8)
    expect(log.contains("location:"), "log: el locator sí deja constancia de que buscó")
    for secret in ["Cuernavaca", "México", "18.9", "99.2", "18,9", "-99"] {
        expect(!log.contains(secret), "log: «\(secret)» no aparece jamás en el log del locator")
    }
}
