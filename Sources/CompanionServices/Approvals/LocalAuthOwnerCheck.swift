import CompanionCore
import Foundation
import LocalAuthentication

/// `LAContext` is not Sendable and `invalidate()` has to run from whichever
/// task cancels, so every touch goes through one lock.
private final class ContextBox: @unchecked Sendable {
    private let lock = NSLock()
    private let context: LAContext

    init(_ context: LAContext) { self.context = context }

    func invalidate() { lock.withLock { context.invalidate() } }

    func evaluate(reason: String) async throws -> Bool {
        let context = lock.withLock { self.context }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

/// Touch ID with the account password as the alternative. A new `LAContext`
/// per call, so an earlier success can never answer a later request.
package struct LocalAuthOwnerCheck: OwnerVerifying {
    /// Returns when the dialog has been left alone long enough. Injected: the
    /// default waits on the clock, tests return at once.
    package typealias Limit = @Sendable () async throws -> Void

    private let unattendedLimit: Limit

    package init(unattendedLimit: @escaping Limit = {
        try await Task.sleep(for: .seconds(ApprovalTiming.autoDeny))
    }) {
        self.unattendedLimit = unattendedLimit
    }

    package func canVerify() async -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    package func verify(reason: String) async -> OwnerCheck {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            Log.app("owner check: unavailable (LAError \(error?.code ?? 0))")
            return .unavailable
        }
        let box = ContextBox(context)
        return await Self.race(
            limit: unattendedLimit,
            evaluate: { try await box.evaluate(reason: reason) },
            invalidate: { box.invalidate() }
        )
    }

    /// Cancelling, or leaving the dialog unattended past the limit, closes it
    /// and counts as a refusal: an open Touch ID prompt must not hold a
    /// caller for ever, and silence is not consent.
    static func race(
        limit: @escaping Limit,
        evaluate: @escaping @Sendable () async throws -> Bool,
        invalidate: @escaping @Sendable () -> Void
    ) async -> OwnerCheck {
        enum Finish: Sendable { case answered(OwnerCheck), unattended }
        let result = await withTaskCancellationHandler {
            await withTaskGroup(of: Finish?.self) { group in
                group.addTask { .answered(await answer(evaluate)) }
                // A limit that throws (cancelled sleep) did not elapse.
                group.addTask {
                    do { try await limit() } catch { return nil }
                    return .unattended
                }
                for await finish in group {
                    guard let finish else { continue }
                    group.cancelAll()
                    switch finish {
                    case .answered(let check):
                        return check
                    case .unattended:
                        invalidate()
                        return .refused
                    }
                }
                return .refused
            }
        } onCancel: {
            invalidate()
        }
        // A yes that lands after the caller gave up is not for this call.
        return result == .confirmed && Task.isCancelled ? .refused : result
    }

    private static func answer(_ evaluate: @Sendable () async throws -> Bool) async -> OwnerCheck {
        do {
            return try await evaluate() ? .confirmed : .refused
        } catch let error as LAError {
            Log.app("owner check: LAError \(error.code.rawValue)")
            return check(for: error.code)
        } catch {
            Log.app("owner check: unexpected error \(type(of: error))")
            return .unavailable
        }
    }

    /// Anything not known to be the owner saying no is "cannot ask": a new
    /// code from a later SDK must not read as a refusal that counts against
    /// the person, and can never read as a yes.
    static func check(for code: LAError.Code) -> OwnerCheck {
        switch code {
        case .userCancel, .systemCancel, .appCancel, .authenticationFailed, .userFallback:
            return .refused
        default:
            return .unavailable
        }
    }
}
