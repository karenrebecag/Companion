import CompanionServices
import Foundation
import Testing

// Wave 15c-1 (TDD rows 1-2). The old ear's `stop()` used to snapshot the
// partial and cancel without ever waiting for the recognizer's own final —
// this is the wait itself, which `AnalyzerTranscriber` keeps (15e-0),
// isolated so it runs against a clock a test controls.

@Test @MainActor func transcriptFinalizerTests() async {
    await testFinalArrivingBeforeTheDeadlineWins()
    await testNoFinalReturnsNilAtTheDeadline()
    await testASecondSignalAfterResolutionIsIgnored()
    await testAFinalSignalledBeforeTheWaitStillWins()
}

/// Row 1: a final arriving well inside a 300 ms wait wins over the timeout.
/// Sequential on purpose (start the wait, yield once, signal directly) —
/// two independently scheduled sleeps racing each other is what made this
/// flaky under a loaded test run; `ApprovalsTests.swift` uses the same
/// start-then-resolve shape for `Approvals`' own wait.
@MainActor func testFinalArrivingBeforeTheDeadlineWins() async {
    let finalizer = TranscriptFinalizer()
    let task = Task { await finalizer.awaitFinal(timeout: 0.3) }
    try? await Task.sleep(nanoseconds: 20_000_000) // let awaitFinal start waiting
    await finalizer.signalFinal("el final de verdad")
    let text = await task.value
    expectEq(text, "el final de verdad", "final a tiempo: gana sobre el timeout")
}

/// Row 2: nothing arrives — at the deadline the wait resolves `nil`, the
/// caller's cue to fall back to whatever partial it already had.
@MainActor func testNoFinalReturnsNilAtTheDeadline() async {
    let finalizer = TranscriptFinalizer()
    let start = ContinuousClock.now
    let text = await finalizer.awaitFinal(timeout: 0.05)
    let elapsed = ContinuousClock.now - start
    expect(text == nil, "sin final: nil, no un texto inventado")
    expect(elapsed >= .milliseconds(45), "sin final: esperó el tope, no adivinó antes")
}

/// A signal after the wait already resolved must not crash or resume a
/// continuation twice.
@MainActor func testASecondSignalAfterResolutionIsIgnored() async {
    let finalizer = TranscriptFinalizer()
    let text = await finalizer.awaitFinal(timeout: 0.02)
    expect(text == nil, "post-resolución: el timeout ya resolvió")
    await finalizer.signalFinal("tarde")
    expect(true, "post-resolución: una señal tardía no truena")
}

/// 15e-0: the analyzer's final is signalled from its own task, which can
/// land before `awaitFinal` has registered — it must win, not be dropped.
@MainActor func testAFinalSignalledBeforeTheWaitStillWins() async {
    let finalizer = TranscriptFinalizer()
    await finalizer.signalFinal("llegó antes")
    let text = await finalizer.awaitFinal(timeout: 0.3)
    expectEq(text, "llegó antes", "señal temprana: gana sobre el timeout")
}
