import CompanionTestKit
import Foundation
import LocalAuthentication
import Testing

@testable import CompanionCore
@testable import CompanionServices

@Test func cancelCodesMapToRefused() {
    let codes: [LAError.Code] = [.userCancel, .systemCancel, .appCancel, .authenticationFailed, .userFallback]
    for code in codes {
        expectEq(LocalAuthOwnerCheck.check(for: code), .refused, "\(code.rawValue)")
    }
}

@Test func unavailableCodesMapToUnavailable() {
    let codes: [LAError.Code] = [.passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled, .notInteractive]
    for code in codes {
        expectEq(LocalAuthOwnerCheck.check(for: code), .unavailable, "\(code.rawValue)")
    }
}

@Test func everyKnownCodeMapsToNonConfirmed() {
    for raw in -10_000 ... 10_000 {
        guard let code = LAError.Code(rawValue: raw) else { continue }
        expect(LocalAuthOwnerCheck.check(for: code) != .confirmed, "\(raw) nunca confirma")
    }
}

private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var invalidations = 0
    private var parked: CheckedContinuation<Bool, Error>?

    var count: Int { lock.withLock { invalidations } }

    /// A dialog that stays up until `invalidate`, like the system's. One
    /// closed before it was shown fails at once instead of parking.
    func dialog() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let closed = lock.withLock { () -> Bool in
                if invalidations > 0 { return true }
                parked = continuation
                return false
            }
            if closed { continuation.resume(throwing: LAError(.appCancel)) }
        }
    }

    func invalidate() {
        let waiting = lock.withLock { () -> CheckedContinuation<Bool, Error>? in
            invalidations += 1
            defer { parked = nil }
            return parked
        }
        waiting?.resume(throwing: LAError(.appCancel))
    }
}

@Test func anAnsweredDialogReturnsItsResultWithoutInvalidating() async {
    let probe = Probe()
    let check = await LocalAuthOwnerCheck.race(
        limit: { try await Task.sleep(for: .seconds(3600)) },
        evaluate: { true }, invalidate: { probe.invalidate() })
    expectEq(check, .confirmed, "el sistema confirmo")
    expectEq(probe.count, 0, "no se cierra un dialogo ya contestado")
}

@Test func anUnattendedDialogIsInvalidatedAndRefused() async {
    let probe = Probe()
    let check = await LocalAuthOwnerCheck.race(
        limit: {}, evaluate: { try await probe.dialog() }, invalidate: { probe.invalidate() })
    expectEq(check, .refused, "sin atender no es un si")
    expectEq(probe.count, 1, "el dialogo se cierra")
}

@Test func cancellingTheCallerInvalidatesTheDialog() async {
    let probe = Probe()
    let task = Task {
        await LocalAuthOwnerCheck.race(
            limit: { try await Task.sleep(for: .seconds(3600)) },
            evaluate: { try await probe.dialog() }, invalidate: { probe.invalidate() })
    }
    task.cancel()
    expectEq(await task.value, .refused, "cancelar no confirma")
    expect(probe.count >= 1, "invalidate al cancelar")
}

@Test func anUnexpectedErrorIsUnavailableNotRefused() async {
    struct Boom: Error {}
    let check = await LocalAuthOwnerCheck.race(
        limit: { try await Task.sleep(for: .seconds(3600)) },
        evaluate: { throw Boom() }, invalidate: {})
    expectEq(check, .unavailable, "un fallo ajeno no cuenta como no del dueño")
}

@Test func aYesThatArrivesAfterTheCallerCancelledIsRefused() async {
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        return await LocalAuthOwnerCheck.race(
            limit: { try await Task.sleep(for: .seconds(3600)) },
            evaluate: { true }, invalidate: {})
    }
    task.cancel()
    expectEq(await task.value, .refused, "cancelada no confirma")
}
