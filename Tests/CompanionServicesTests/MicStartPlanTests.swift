import CompanionServices
import CompanionTestKit
import Testing

// Live crash 2026-09-23: MicCapture.startOnce() installed a tap without
// checking whether one was already live, and a second install on top of a
// running engine raised an uncatchable ObjC exception (SIGABRT). The rule
// behind the guard is pure — tested here without a real AVAudioEngine.

@Test @MainActor func micStartPlanTests() {
    testMicStartPlanRunningWithTapIsANoOp()
    testMicStartPlanStartsWhenStopped()
    testMicStartPlanStartsWhenRunningWithoutATap()
}

@MainActor func testMicStartPlanRunningWithTapIsANoOp() {
    expectEq(MicStartPlan.decide(running: true, tapInstalled: true), .alreadyRunning,
             "start plan: already running with a tap ⇒ no-op")
}

@MainActor func testMicStartPlanStartsWhenStopped() {
    expectEq(MicStartPlan.decide(running: false, tapInstalled: false), .start,
             "start plan: stopped ⇒ starts")
}

@MainActor func testMicStartPlanStartsWhenRunningWithoutATap() {
    // Defensive corner: this should never happen in practice (tearDownEngine
    // keeps the two flags in lockstep), but a running engine with no tap has
    // nothing to no-op on — it still starts rather than going silently dead.
    expectEq(MicStartPlan.decide(running: true, tapInstalled: false), .start,
             "start plan: running without a tap ⇒ starts anyway")
}
