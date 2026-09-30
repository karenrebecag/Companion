import Foundation

/// Wave 15c-1: the wait the old ear's `stop()` used to skip, kept by
/// `AnalyzerTranscriber` (15e-0) as the bound on the analyzer's own final.
/// A plain actor so the races run against a clock a test controls.
/// `signalFinal` resumes the wait early; the deadline resumes it with `nil`
/// when no final ever came, exactly like `Approvals`' own timer
/// (`Approvals.swift`).
package actor TranscriptFinalizer {
    private var continuation: CheckedContinuation<String?, Never>?
    private var deadline: Task<Void, Never>?
    /// A final signalled before anyone waits: the analyzer's finishing task
    /// can beat `awaitFinal` to the actor, and dropping it would cost the
    /// hold its whole final for a scheduling accident.
    private var early: String?
    private var resolved = false

    package init() {}

    /// Suspends until `signalFinal` or `timeout` — whichever comes first —
    /// and returns `nil` on the timeout side, so the caller falls back to
    /// whatever partial it already had.
    package func awaitFinal(timeout: TimeInterval) async -> String? {
        if let early {
            self.early = nil
            resolved = true
            return early
        }
        return await withCheckedContinuation { pending in
            continuation = pending
            deadline = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                } catch {
                    return
                }
                await self?.resolve(nil)
            }
        }
    }

    /// The recognizer's own final result: wins the race whenever it lands
    /// before the deadline.
    package func signalFinal(_ text: String) {
        guard continuation != nil else {
            if !resolved { early = text }
            return
        }
        resolve(text)
    }

    private func resolve(_ text: String?) {
        guard let continuation else { return }
        self.continuation = nil
        resolved = true
        deadline?.cancel()
        deadline = nil
        continuation.resume(returning: text)
    }
}
