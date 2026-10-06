import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// The target is the window, not the app in front. A call acts on the pid
// pinned by look AND the window pinned inside it; any other window of the
// same app, or any other app, makes the call refuse. The MCP shim's pid
// counts as one of the caller's own, so a terminal the shim launched is
// still on the same side of the door.

// The bridge sets `HandsCaller.$apps` from the shim's lineage; tests inject
// the terminal pid directly so the test process itself is not a caller and
// "voice, no callers" assertions still hold.
private let mcpCallers: Set<Int32> = [50]

@Test @MainActor func terminalInFrontAfterLookActsOnThePinnedPid() async {
    await testTerminalInFrontAfterLookActsOnThePinnedPid()
}

@Test @MainActor func voiceCallerDoesNotInheritThePin() async {
    await testVoiceCallerDoesNotInheritThePin()
}

@Test @MainActor func windowSwitchInTheSameAppIsTargetLost() async {
    await testWindowSwitchInTheSameAppIsTargetLost()
}

@Test @MainActor func thirdAppDuringMCPSessionRefusesBothTypeAndLook() async {
    await testThirdAppDuringMCPSessionRefusesBothTypeAndLook()
}

@Test @MainActor func afterOpenUrlReleaseWithTerminalInFrontIsTargetLost() async {
    await testAfterOpenUrlReleaseWithTerminalInFrontIsTargetLost()
}

@Test @MainActor func voiceTurnSameAppWindowSwitchIsTargetLost() async {
    await testVoiceTurnSameAppWindowSwitchIsTargetLost()
}

@Test @MainActor func aPinnedWindowThatClosedIsTargetLost() async {
    await testAPinnedWindowThatClosedIsTargetLost()
}

@Test @MainActor func approvalCarriesThePinnedPidAndExecutesOnIt() async {
    await testApprovalCarriesThePinnedPidAndExecutesOnIt()
}

@Test @MainActor func approvalWithTerminalInFrontAndNoCallersIsNil() async {
    await testApprovalWithTerminalInFrontAndNoCallersIsNil()
}

@Test @MainActor func callerLineageWalksTheParentChain() async {
    await testCallerLineageWalksTheParentChain()
}

@Test @MainActor func callerLineageRejectsNilAndUnknown() async {
    await testCallerLineageRejectsNilAndUnknown()
}

// New: callers in front, terminal pin-only (no look) is refused at the door
// (R1). Without look, a type_text must not be allowed to act on the
// terminal even though the shim considers the terminal a caller.
@Test @MainActor func sessionOpenPinIsTerminalRefusesTypeText() async {
    await testSessionOpenPinIsTerminalRefusesTypeText()
}

// New: callers in front, look during MCP must not silently latch onto
// whatever window the user switched to (R3).
@Test @MainActor func lookUnderCallersFollowsTheWindowCheck() async {
    await testLookUnderCallersFollowsTheWindowCheck()
}

// New: focus_window ok with the app in front, then type_text lands on the
// pid (R1, R4).
@Test @MainActor func focusWindowWithAppInFrontSwitchesBackAndTypeSucceeds() async {
    await testFocusWindowWithAppInFrontSwitchesBackAndTypeSucceeds()
}

// New: focus_window raise fails -> latch stays on the previous window (R4).
@Test @MainActor func focusWindowRaiseFailureKeepsThePreviousLatch() async {
    await testFocusWindowRaiseFailureKeepsThePreviousLatch()
}

@Test @MainActor func focusWindowWithCallerInFrontAndWindowSwitchedIsTargetLost() async {
    await testFocusWindowWithCallerInFrontAndWindowSwitchedIsTargetLost()
}

// New: a look that returns no window does not erase the latch (R4).
@Test @MainActor func lookWithoutAWindowKeepsTheExistingLatch() async {
    await testLookWithoutAWindowKeepsTheExistingLatch()
}

// New: between entry and act, a target() read on entry returns 9 and the
// second read returns 13 -> refused, nothing injected (R2).
@Test @MainActor func holdsAtActTimeRefusesWhenFrontMovedToAnotherPid() async {
    await testHoldsAtActTimeRefusesWhenFrontMovedToAnotherPid()
}

// New: same scenario but the second read is nil -> refused (R2).
@Test @MainActor func holdsAtActTimeRefusesWhenFrontDisappeared() async {
    await testHoldsAtActTimeRefusesWhenFrontDisappeared()
}

// New: the latched window changed between entry and act -> refused (R2).
@Test @MainActor func holdsAtActTimeRefusesWhenLatchedWindowChanged() async {
    await testHoldsAtActTimeRefusesWhenLatchedWindowChanged()
}

// New: a pid recycled to a different bundle after being pinned -> refused
// at the next caller-fronted call (R1).
@Test @MainActor func recycledPidToDifferentBundleRefusesTheCall() async {
    await testRecycledPidToDifferentBundleRefusesTheCall()
}

@Test @MainActor func lookRefusesWhenWindowChangesDuringWalk() async {
    await testLookRefusesWhenWindowChangesDuringWalk()
}

@Test @MainActor func callerFrontRefusesWhenStoredBundleBecameNil() async {
    await testCallerFrontRefusesWhenStoredBundleBecameNil()
}


// MARK: - helpers

// Test texts are plain words, so no JSON escaping is needed.
private func typing(_ text: String) -> ToolCallRef {
    ToolCallRef(id: "c1", name: "type_text", arguments: #"{"text":""# + text + #""}"#)
}

private let lookArgs = "{}"
private let lookName = "look"

private func makeScreen() -> FakeScreen { FakeScreen([]) }

/// A `frontWindow` lookup that hands back one of two named windows per pid:
/// tests advance it by switching what `next()` returns. Nil when the pid
/// has no window (the app just came up, the window was closed). `reads`
/// counts every `frontWindow(pid:)` invocation so a test that depends on
/// the order (look's before/after, the entry and act-time checks) can
/// assert the exact count, not just trust the comment. The book is the
/// single source of truth for what the front window is: every check that
/// compares a latched window to "the window in front now" reads it here.
private final class WindowBook: @unchecked Sendable {
    private let lock = NSLock()
    private var byPid: [Int32: [(Int, String)]] = [:]
    /// nil per pid = the app has no window right now.
    private var empty: Set<Int32> = []
    /// The book flips on its Nth read (1-based): useful for changing the
    /// latched window between the entry read and the read right before
    /// acting, so the second `holds(pid:)` check sees a different window.
    private var flipAfterRead: Int?
    private var flipMap: [Int32: [(Int, String)]] = [:]
    private var _reads = 0

    var reads: Int { lock.withLock { _reads } }

    /// Seeds `pid` with a window list and clears the `empty` flag for it
    /// (the previous `seed` left a stale `empty` entry behind on the
    /// `clear` call, so a `look` after re-seeding still got nil).
    func seed(pid: Int32, _ windows: [(Int, String)]) {
        lock.withLock {
            byPid[pid] = windows
            empty.remove(pid)
        }
    }
    func clear(pid: Int32) {
        lock.withLock { _ = empty.insert(pid); byPid.removeValue(forKey: pid) }
    }
    /// Always returns the FIRST element for the pid: tests don't rotate
    /// inside a pid (we already pin the same one), they switch between A
    /// and B by replacing the seed.
    func window(pid: Int32) -> HandsWindow? {
        lock.withLock {
            _reads += 1
            if empty.contains(pid) { return nil }
            if let flipAt = flipAfterRead, _reads > flipAt, let list = flipMap[pid] {
                return HandsWindow(NSString(string: list.first?.1 ?? ""))
            }
            guard let list = byPid[pid], let first = list.first else { return nil }
            return HandsWindow(NSString(string: first.1))
        }
    }
    /// Switch the value handed back for `pid` starting at the Nth read.
    func flipOnRead(_ read: Int, pid: Int32, _ windows: [(Int, String)]) {
        lock.withLock { flipAfterRead = read; flipMap[pid] = windows }
    }
}

private func makeHands(
    hands: FakeHands, screen: FakeScreen = makeScreen(),
    target: ScriptedTarget = ScriptedTarget([9]),
    frontBook: WindowBook? = nil,
    bundle: String = "com.apple.Notes"
) -> ScreenHands {
    ScreenHands(
        injector: hands, reader: hands, keys: hands, windows: hands,
        trusted: { true }, target: { target.next() },
        bundleID: { _ in bundle }, screen: screen,
        frontWindow: { pid in frontBook?.window(pid: pid) })
}

/// A bundled, MCP-flavored call setup: the shim sits behind pid 50, the
/// terminal is its child, the user is in Notes (pid 9). `beginTurn` pins
/// pid 9, `look` pins window A of pid 9.
private func mcprunner(
    target: ScriptedTarget, frontBook: WindowBook? = nil,
    workspace: FakeWorkspaceOpener = FakeWorkspaceOpener()
) -> (ParentToolRunner, FakeHands, WindowBook, FakeScreen) {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 9))
    let screen = FakeScreen([])
    let book = frontBook ?? WindowBook()
    let handsStruct = makeHands(hands: hands, screen: screen, target: target, frontBook: book)
    let runner = ParentToolRunner(
        workspace: workspace,
        hands: handsStruct)
    return (runner, hands, book, screen)
}

// MARK: - (a) terminal pid 50 comes to front after look on 9, callers {50}: type_text succeeds

@MainActor func testTerminalInFrontAfterLookActsOnThePinnedPid() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    // beginTurn reads 9 (in front when the user spoke), look reads 9 (the
    // user is still in Notes when look is called), then the user moves to
    // the terminal (50) before type_text. callers {50} is what the bridge
    // sets: the shim's own terminal is on the same side of the door.
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 50, 50]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look en 9: debe succeed \(look.output)")
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("hola").arguments)
    }
    expect(out.ok, "pin conservado por callers: el escrito cae en pid 9: \(out.output)")
    expectEq(hands.injected.map(\.pid), [9], "escrito: en el pid pineado, no en el terminal")
}

// MARK: - (b) same switch with no callers (voice): target_changed

@MainActor func testVoiceCallerDoesNotInheritThePin() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    // The user was in 9, switched to 50; voice has no caller lineage to
    // bridge the move. `look` and `type_text` both target_changed.
    let (runner, _, _, _) = mcprunner(target: ScriptedTarget([9, 50, 50, 50]), frontBook: book)
    runner.beginTurn()
    _ = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("hola").arguments)
    expect(out.output.hasPrefix("target_changed:"), "voz sin callers: target_changed: \(out.output)")
    expect(out.output.contains("front, then retry"), "M1: dice el siguiente paso: \(out.output)")
}

// MARK: - (c) window changes A -> B: target_lost, then look succeeds and type_text succeeds

@MainActor func testWindowSwitchInTheSameAppIsTargetLost() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, 9]), frontBook: book)
    runner.beginTurn()
    let firstLook = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(firstLook.ok, "primer look: succeed \(firstLook.output)")
    book.seed(pid: 9, [(0, "B")])
    let lost = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(lost.output.hasPrefix("target_lost:"), "ventana A -> B: target_lost: \(lost.output)")
    expect(lost.output.contains("call look again"), "el mensaje dice el siguiente paso: \(lost.output)")
    expect(hands.injected.isEmpty, "cambio de ventana: nada escrito")
    let secondLook = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(secondLook.ok, "segundo look: succeed \(secondLook.output)")
    let ok = await runner.execute(name: "type_text", argumentsJSON: typing("dos").arguments)
    expect(ok.ok, "tras mirar otra vez: escribe: \(ok.output)")
    expectEq(hands.injected.map(\.text), ["dos"], "escrito: en la nueva ventana")
}

// MARK: - (d) third app 13 in front during an MCP session (callers {50}): target_changed for type_text AND look

@MainActor func testThirdAppDuringMCPSessionRefusesBothTypeAndLook() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 13, [(0, "notify")])
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 13, 13, 13]), frontBook: book)
    runner.beginTurn()
    let firstLook = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(firstLook.ok, "primer look: succeed \(firstLook.output)")
    let typeBad = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(typeBad.output.hasPrefix("target_changed:"), "type_text con otra app: target_changed: \(typeBad.output)")
    // R3: look with a caller in front follows the same window check as
    // every other tool, so it refuses instead of silently re-pinning to
    // whatever window the user switched to.
    let lookBad = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: lookName, argumentsJSON: lookArgs)
    }
    expect(lookBad.output.hasPrefix("target_changed:"), "look con otra app: target_changed: \(lookBad.output)")
    expect(hands.injected.isEmpty, "tercera app: nada escrito")
}

// MARK: - (e) after an open_url release with the terminal in front: target_lost

@MainActor func testAfterOpenUrlReleaseWithTerminalInFrontIsTargetLost() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    // Pin pid 9 with a window, then an open_url releases the turn, then
    // the terminal sits in front. The shim (pid 50) is the caller lineage.
    let workspace = FakeWorkspaceOpener()
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 50]), frontBook: book, workspace: workspace)
    runner.beginTurn()
    let firstLook = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(firstLook.ok, "look: succeed \(firstLook.output)")
    _ = await runner.execute(name: "open_url", argumentsJSON: #"{"url":"https://example.com"}"#)
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(out.output.hasPrefix("target_lost:"), "open_url soltó y el terminal al frente: target_lost: \(out.output)")
    expect(hands.injected.isEmpty, "open_url soltó: nada escrito")
}

// MARK: - (f) same-app window switch in a voice turn: target_lost

@MainActor func testVoiceTurnSameAppWindowSwitchIsTargetLost() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, 9]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    book.seed(pid: 9, [(0, "B")])
    let lost = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(lost.output.hasPrefix("target_lost:"), "voz misma app ventana cambia: target_lost: \(lost.output)")
    expect(hands.injected.isEmpty, "voz misma app ventana cambia: nada escrito")
}

@MainActor func testAPinnedWindowThatClosedIsTargetLost() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, 9]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    book.clear(pid: 9)
    let lost = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(lost.output.hasPrefix("target_lost:"), "ventana cerrada: target_lost: \(lost.output)")
    expect(hands.injected.isEmpty, "ventana cerrada: nada escrito")
}

// MARK: - (g) approval with the terminal in front: ticket carries pid 9, execute succeeds

@MainActor func testApprovalCarriesThePinnedPidAndExecutesOnIt() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    // Read order on the target sensor:
    // 1: beginTurn, 2: look's resolveTarget, 3: approval's resolveTarget
    // (50, under callers {50}, so the caller-fronted branch kicks in and
    // resolves to the pin 9), 4: type_text's resolveTarget (50), 5:
    // type_text's moved check (50). The approval's read is the one that
    // proves the bridge-side wrapping delivers the terminal to the sheet.
    let scripted = ScriptedTarget([9, 9, 50, 50, 50, 50])
    let (runner, hands, _, _) = mcprunner(target: scripted, frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    // A typed URL forces the address path: the runner builds a ticket.
    let address = ToolCallRef(id: "u", name: "type_text",
                              arguments: #"{"text":"https://example.com"}"#)
    let request = await HandsCaller.$apps.withValue(mcpCallers) {
        runner.approval(for: address, said: "")
    }
    expect(request != nil, "direccion no dicha: pide hoja")
    guard let request else { return }
    // The approval itself ran under callers {50}: assert the runner's
    // target sensor was read at the right point (3 reads = beginTurn +
    // look + approval), so a future change that calls resolveTarget
    // without callers fails here, not at the ticket redeem.
    expectEq(scripted.reads, 3,
             "approval leyó el target con callers {50} al frente (50): \(scripted.reads)")
    // Grant it and run from the terminal's front: the redeem must succeed
    // because the ticket was bound to pid 9.
    runner.granted(request)
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: address.arguments)
    }
    expect(out.ok, "tras aprobar y ejecutar desde el terminal: ok: \(out.output)")
    expectEq(hands.injected.map(\.pid), [9], "ejecucion: en el pid pineado")
}

// Negative: a typed URL with the terminal in front and NO callers: the
// resolveTarget sees 50 without a caller, the pin is 9, so the front
// does not match the pin and the runner must not issue a sheet (it
// would be a sheet for the wrong app). The user said the URL out loud
// at the terminal, not the agent.
@MainActor func testApprovalWithTerminalInFrontAndNoCallersIsNil() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    // The first three reads (beginTurn, look's resolveTarget, approval's
    // resolveTarget) need the approval to see 50. With NO callers, the
    // caller-fronted branch is not taken: pin(for: 50) returns the
    // existing pin (9), which does not match the front (50), so the
    // resolution is .targetChanged and `handsApproval` returns nil.
    let scripted = ScriptedTarget([9, 9, 50, 50])
    let (runner, _, _, _) = mcprunner(target: scripted, frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    let address = ToolCallRef(id: "u", name: "type_text",
                              arguments: #"{"text":"https://example.com"}"#)
    let request = await runner.approval(for: address, said: "")
    expect(request == nil,
           "sin callers y terminal al frente: la hoja NO se pide (seria para la app equivocada): \(String(describing: request))")
    expectEq(scripted.reads, 3,
             "approval leyó el target exactamente una vez (entry, no act-time): \(scripted.reads)")
}

// MARK: - (h) lineage walks the parent chain; rejects nil/unknown

@MainActor func testCallerLineageWalksTheParentChain() async {
    let own = ProcessInfo.processInfo.processIdentifier
    let lineage = HandsCaller.lineage(of: own)
    expect(lineage.contains(own), "lineage: contiene el pid propio")
    expect(lineage.count > 1, "lineage: camina al menos un padre: \(lineage)")
}

@MainActor func testCallerLineageRejectsNilAndUnknown() async {
    expectEq(HandsCaller.lineage(of: nil), [], "nil: vacio")
    expectEq(HandsCaller.lineage(of: -1), [], "pid invalido: vacio")
    expectEq(HandsCaller.lineage(of: Int32.max), [], "pid que no existe: vacio")
}

// MARK: - (R1) session-open pin is the terminal: type_text is refused

@MainActor func testSessionOpenPinIsTerminalRefusesTypeText() async {
    let book = WindowBook()
    book.seed(pid: 50, [(0, "shell")])
    // beginTurn reads 50 (the terminal was in front when the session
    // opened). Without a look, type_text must not be allowed to act on
    // the terminal even though the shim considers it a caller.
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([50, 50, 50]), frontBook: book)
    runner.beginTurn()
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(out.output.hasPrefix("target_lost:"), "pin en terminal sin look: target_lost: \(out.output)")
    expect(hands.injected.isEmpty, "pin en terminal sin look: nada escrito")
}

// MARK: - (R3) callers in front: look follows the window check, no silent re-latch

@MainActor func testLookUnderCallersFollowsTheWindowCheck() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    // beginTurn reads 9 (Notes), look at 9 pins A. The user then moves
    // to the terminal (50) and switches to window B in pid 9. With
    // callers {50}, type_text reaches the window check and is refused
    // (A != B). The look, with a caller in front, gets the same check:
    // it must not silently re-latch onto B.
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 50, 50, 50, 50]), frontBook: book)
    runner.beginTurn()
    let firstLook = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(firstLook.ok, "look: succeed \(firstLook.output)")
    book.seed(pid: 9, [(1, "B")])
    let typeBad = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(typeBad.output.hasPrefix("target_lost:"),
           "type_text con caller al frente y ventana A->B: target_lost \(typeBad.output)")
    let lookBad = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: lookName, argumentsJSON: lookArgs)
    }
    expect(lookBad.output.hasPrefix("target_lost:"),
           "look con caller al frente y ventana cambiada: target_lost \(lookBad.output)")
    expect(hands.injected.isEmpty, "look rechazado: nada escrito")
}

// MARK: - focus_window ok with the app in front, then type_text lands on the pid (R1, R4)

@MainActor func testFocusWindowWithAppInFrontSwitchesBackAndTypeSucceeds() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    // look pins A in pid 9, the user switches to window B (same app),
    // then focus_window with the app in front and no callers: focus_window
    // is exempt from the entry window check when the front is not a
    // caller, so it raises B and type_text lands on pid 9.
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 9), windows: ["Notes — A", "Notes — B"])
    let screen = FakeScreen([])
    let scripted = ScriptedTarget([9, 9, 9, 9, 9, 9, 9, 9, 9])
    let handsStruct = ScreenHands(
        injector: hands, reader: hands, keys: hands, windows: hands,
        trusted: { true },
        target: { scripted.next() },
        bundleID: { _ in "com.apple.Notes" }, screen: screen,
        frontWindow: { pid in book.window(pid: pid) })
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener(), hands: handsStruct)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look pins A: succeed \(look.output)")
    book.seed(pid: 9, [(1, "B")])
    let typeBad = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(typeBad.output.hasPrefix("target_lost:"),
           "misma app, ventana cambio: target_lost \(typeBad.output)")
    // focus_window: app is in front, no callers; the exemption lets it
    // raise B even though the latched window was A.
    let focused = await runner.execute(name: "focus_window", argumentsJSON: #"{"title":"B"}"#)
    expect(focused.ok, "focus_window con app al frente: ok \(focused.output)")
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("dos").arguments)
    expect(out.ok, "type_text tras focus_window: ok \(out.output)")
    expectEq(hands.injected.map(\.pid), [9], "escrito: pid 9")
}

// MARK: - focus_window raise fails -> latch stays on the previous window (R4)

@MainActor func testFocusWindowRaiseFailureKeepsThePreviousLatch() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    // The book flips to B AFTER the type_text's entry window check so
    // the entry check still sees A (passes), and only the act-time
    // check inside `holds(pid:)` sees B (refuses). Read order on the
    // book: 1 + 2 = look's before/after (A, latch A), 3 = type_text's
    // entry window check (A, passes), 4 = type_text's act-time
    // (B, refuses). The flip on read 3 keeps read 3 as A and flips
    // read 4 to B.
    book.flipOnRead(3, pid: 9, [(0, "B")])
    let (runner, _, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, 9, 9, 9]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed (latch A) \(look.output)")
    let failed = await runner.execute(name: "focus_window", argumentsJSON: #"{"title":"ZZZ"}"#)
    expect(failed.output.hasPrefix("window_not_found"),
           "focus_window sin match: window_not_found \(failed.output)")
    // The latch was not rewritten by a failed raise: a window switch
    // to B is still refused (act-time, not entry, so the code is
    // target_changed), not a silent re-pin.
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(out.output.hasPrefix("target_changed:"),
           "latch sigue en A, B al frente: target_changed (act-time) \(out.output)")
}

// Negative: focus_window with the caller (terminal) in front and the
// user already on a different window of the same app is target_lost,
// not a silent re-pin. The exemption that lets focus_window skip the
// window check applies ONLY when the front is not a caller.
@MainActor func testFocusWindowWithCallerInFrontAndWindowSwitchedIsTargetLost() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    // The FakeHands needs the title "B" in its `windows` list, so the
    // raise succeeds; only the entry window check (B != A latched) is
    // expected to refuse. Reads: 1 beginTurn, 2 look resolveTarget, 3
    // look before/after frontWindow (both A, latch A), 4 focus_window
    // resolveTarget (50 under callers {50}, pin 9), 5 focus_window
    // entry window check (B != A latched, target_lost).
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 9), windows: ["B"])
    let screen = FakeScreen([])
    let scripted = ScriptedTarget([9, 9, 50, 50])
    let handsStruct = ScreenHands(
        injector: hands, reader: hands, keys: hands, windows: hands,
        trusted: { true }, target: { scripted.next() },
        bundleID: { _ in "com.apple.Notes" }, screen: screen,
        frontWindow: { pid in book.window(pid: pid) })
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener(), hands: handsStruct)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed (latch A) \(look.output)")
    book.seed(pid: 9, [(0, "B")])
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "focus_window", argumentsJSON: #"{"title":"B"}"#)
    }
    expect(out.output.hasPrefix("target_lost:"),
           "focus_window con caller al frente y ventana cambiada: target_lost \(out.output)")
}

// MARK: - a look that returns no window does not erase the latch (R4)

@MainActor func testLookWithoutAWindowKeepsTheExistingLatch() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, 9, 9, 9, 9, 9]), frontBook: book)
    runner.beginTurn()
    let firstLook = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(firstLook.ok, "primer look con ventana: succeed \(firstLook.output)")
    // Drop the window for pid 9; the second look has no window to latch
    // and must not erase the previous one. FakeScreen.walk always returns
    // a walk (the production adapter may not), so the look itself still
    // succeeds; the point is that the previous latch (A) survives.
    book.clear(pid: 9)
    let secondLook = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(secondLook.ok,
           "segundo look sin ventana: succeed (la app sigue siendo legible) \(secondLook.output)")
    // Re-seed A so the type_text's entry window check sees the same
    // window the look latched, then flip to B only after the entry read
    // (5) so the act-time check inside `holds(pid:)` (read 6) sees B.
    // Read order on the book: 1, 2 = look 1's before/after (A, latch A);
    // 3, 4 = look 2's before/after (nil, nil; latch stays A); 5 =
    // type_text entry window check (A, passes); 6 = type_text act-time
    // (B, refuses, target_changed).
    book.seed(pid: 9, [(0, "A")])
    book.flipOnRead(5, pid: 9, [(0, "B")])
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(out.output.hasPrefix("target_changed:"),
           "el latch sobrevivio: A->B es target_changed (act-time) \(out.output)")
    expect(hands.injected.isEmpty, "nada escrito")
}

// MARK: - holds at act time: front moved to a different pid between entry and act (R2)

@MainActor func testHoldsAtActTimeRefusesWhenFrontMovedToAnotherPid() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 13, [(0, "notify")])
    // The scripted target feeds four reads: beginTurn, look's resolveTarget,
    // type_text's resolveTarget (entry), type_text's moved check (act-time).
    // The act-time read returns 13 (the user moved). No callers: voice-like.
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, 13, 13]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(!out.ok, "act: rechazado")
    expect(out.output.hasPrefix("target_changed:"),
           "act: target_changed (el entry con 9 pasa, el act-time con 13 falla) \(out.output)")
    expect(hands.injected.isEmpty, "act: nada escrito")
}

@MainActor func testHoldsAtActTimeRefusesWhenFrontDisappeared() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    // The act-time target() read inside `holds` returns nil (the user
    // closed the app, or the front sensor momentarily has no value). The
    // runner must refuse at act time, with the same code the pid-change
    // case returns: both are `holds(pid:)` rejecting the front.
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, nil]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(!out.ok, "front nil al actuar: rechazado")
    expect(out.output.hasPrefix("target_changed:"),
           "front nil al actuar: target_changed \(out.output)")
    expect(hands.injected.isEmpty, "front nil al actuar: nada escrito")
}

@MainActor func testHoldsAtActTimeRefusesWhenLatchedWindowChanged() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    // Read order on the book: 1 + 2 = look's before/after frontWindow
    // (both A, so the look latches A), 3 = type_text's entry window
    // check in runHands (A, passes), 4 = type_text's act-time
    // frontWindow inside `holds(pid:)` (B, the act-time race).
    // The flip happens AFTER the entry read so the entry check passes
    // and only the act-time check sees B: the call must surface the
    // act-time code, not the entry one.
    book.flipOnRead(3, pid: 9, [(0, "B")])
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 9, 9]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed (antes/despues ven A) \(look.output)")
    expectEq(book.reads, 2, "look leyo el front window 2 veces (antes + despues)")
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    expect(out.output.hasPrefix("target_changed:"),
           "ventana latched cambio entre entry y act: target_changed (act-time, no entry) \(out.output)")
    expect(hands.injected.isEmpty, "ventana latched cambio: nada escrito")
    expectEq(book.reads, 4, "type_text leyó entry (1) + act-time (1) = 4 lecturas totales")
}

// MARK: - recycled pid: the bundle id of the pinned pid changed -> refused (R1)

@MainActor func testRecycledPidToDifferentBundleRefusesTheCall() async {
    // Two windows for pid 9 (so look seeds A), then a switch to a
    // different bundle under the same pid: the runner stores the bundle
    // when the pin is taken and refuses if the bundle is different later.
    // We simulate the bundle change by handing the runner a closure that
    // returns "com.apple.Notes" the first time and a different bundle
    // afterwards.
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    let counter = BundleCounter()
    counter.setBundles("com.apple.Notes", "com.apple.TextEdit")
    let scripted = ScriptedTarget([9, 9, 50, 50])
    let bundle: @Sendable (Int32) -> String? = { _ in counter.next() }
    let handsStruct = ScreenHands(
        injector: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        reader: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        keys: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        windows: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        trusted: { true },
        target: { scripted.next() },
        bundleID: bundle, screen: FakeScreen([]),
        frontWindow: { pid in book.window(pid: pid) })
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener(), hands: handsStruct)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    // The runner recorded the bundle that the pinned pid resolved to at
    // the time of the look. Asserting it here means a future change that
    // drops the record (or never sets it) fails this test, not just
    // the call below.
    let stored = handsStruct.turn.pinnedBundle
    expect(stored == "com.apple.Notes",
           "look guardo el bundle del pin: \(stored ?? "nil")")
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(out.output.hasPrefix("target_lost:"),
           "pid reciclado a otro bundle: target_lost \(out.output)")
}

// S3: the front window changed between look's before-read and after-read.
// The numbered elements may belong to a different window, so look refuses
// and does NOT latch. A subsequent type_text under the same callers must
// still see no pin: nothing was recorded.
@MainActor func testLookRefusesWhenWindowChangesDuringWalk() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    // The book flips after the first read: look's before frontWindow
    // (read 1) returns A, look's after frontWindow (read 2) returns B.
    // The walk in between does not read the book, so the flip is a
    // window change "during the walk" from the runner's perspective.
    book.flipOnRead(1, pid: 9, [(0, "B")])
    let (runner, hands, _, _) = mcprunner(
        target: ScriptedTarget([9, 9, 50, 50]), frontBook: book)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(!look.ok, "look con ventana cambiada: falla")
    expect(look.output.hasPrefix("target_lost:"),
           "look con ventana cambiada: target_lost (no latch) \(look.output)")
    // The look refused, so no pin or window was recorded: a type_text
    // under callers {50} cannot find a pin to act on.
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(out.output.hasPrefix("target_lost:"),
           "sin latch: el type_text no tiene a quien actuar \(out.output)")
    expect(hands.injected.isEmpty, "look rechazo, type_text rechazo: nada escrito")
    expectEq(book.reads, 2, "look leyo 2 veces: before + after")
}

// S1 (bundle): the pinned pid is alive when the pin was taken, then
// disappears (the closure now returns nil). The caller-fronted branch
// must refuse: a pid that can no longer resolve to a bundle is a
// stranger now, even if the pin was for the same number.
@MainActor func testCallerFrontRefusesWhenStoredBundleBecameNil() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    // The bundle closure records "com.apple.Notes" for the first read
    // (look's `recordBundle`) and nil for every read after that, so
    // when the caller-fronted type_text calls `bundleID(pinned)` it
    // gets nil and `stored != nowBundle` is true. Read order on the
    // scripted target: 1 beginTurn, 2 look resolveTarget, 3 type_text
    // entry resolveTarget (50 under callers {50}, the caller-fronted
    // branch sees the stored bundle is gone and refuses).
    let counter = BundleCounter()
    counter.setBundles("com.apple.Notes", nil)
    let scripted = ScriptedTarget([9, 9, 50, 50])
    let bundle: @Sendable (Int32) -> String? = { _ in counter.next() }
    let handsStruct = ScreenHands(
        injector: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        reader: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        keys: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        windows: FakeHands(field: FocusedField(app: "Notes", pid: 9)),
        trusted: { true },
        target: { scripted.next() },
        bundleID: bundle, screen: FakeScreen([]),
        frontWindow: { pid in book.window(pid: pid) })
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener(), hands: handsStruct)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    expectEq(handsStruct.turn.pinnedBundle, "com.apple.Notes",
             "look guardo el bundle del pin")
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(out.output.hasPrefix("target_lost:"),
           "bundle del pin ahora nil: target_lost \(out.output)")
}

// S1 (focus_window records the bundle): when focus_window successfully
// re-pins the window, it must also record the bundle the same way look
// does, so a recycled pid that shows up right after focus_window is
// still refused by the caller-fronted branch. The bundle the closure
// returns flips between look and focus_window: the test asserts the
// stored bundle is the one recorded by focus_window, not by look.
@MainActor func testFocusWindowRecordsTheBundleOnLatch() async {
    let book = WindowBook()
    book.seed(pid: 9, [(0, "A")])
    book.seed(pid: 50, [(0, "shell")])
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 9), windows: ["B"])
    // Reads: look, focus_window, then the caller-fronted type_text. The
    // same app keeps its bundle through look and focus_window; a different
    // bundle on the same pid afterwards is a recycled pid and must refuse.
    let counter = BundleCounter()
    counter.setBundles(Array(repeating: "com.apple.Notes", count: 20))
    let scripted = ScriptedTarget([9, 9, 9, 9, 9, 50, 50])
    let bundle: @Sendable (Int32) -> String? = { _ in counter.next() }
    let handsStruct = ScreenHands(
        injector: hands, reader: hands, keys: hands, windows: hands,
        trusted: { true },
        target: { scripted.next() },
        bundleID: bundle, screen: FakeScreen([]),
        frontWindow: { pid in book.window(pid: pid) })
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener(), hands: handsStruct)
    runner.beginTurn()
    let look = await runner.execute(name: lookName, argumentsJSON: lookArgs)
    expect(look.ok, "look: succeed \(look.output)")
    expectEq(handsStruct.turn.pinnedBundle, "com.apple.Notes",
             "look guardo el bundle del pin")
    let focused = await runner.execute(name: "focus_window", argumentsJSON: #"{"title":"B"}"#)
    expect(focused.ok, "focus_window con app al frente: ok \(focused.output)")
    expectEq(handsStruct.turn.pinnedBundle, "com.apple.Notes",
             "focus_window sobre la misma app conserva su bundle")
    counter.setBundles(Array(repeating: "com.apple.Safari", count: 40))
    // A subsequent caller-fronted call sees the focus_window-recorded
    // bundle; if the now-bundle is different (Safari), the callerFrontHolds
    // refuses at the entry.
    let out = await HandsCaller.$apps.withValue(mcpCallers) {
        await runner.execute(name: "type_text", argumentsJSON: typing("uno").arguments)
    }
    expect(out.output.hasPrefix("target_lost:"),
           "focus_window registro el bundle; ahora nil/distinto: target_lost \(out.output)")
}

private final class BundleCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String?] = ["com.apple.Notes", "com.apple.TextEdit"]
    private var reads = 0

    /// Sets the bundle the closure returns per read; nil means "the queue
    /// is empty" (the closure returns nil for that read, simulating a
    /// pid that no longer resolves to a bundle).
    func setBundles(_ values: String?...) {
        lock.withLock { queue = values }
    }

    func setBundles(_ values: [String?]) {
        lock.withLock { queue = values }
    }

    func next() -> String? {
        lock.lock()
        let n = reads
        reads += 1
        let bundle: String? = n < queue.count ? queue[n] : nil
        lock.unlock()
        return bundle
    }
}

@Test @MainActor func focusWindowRecordsTheBundleOnLatch() async {
    await testFocusWindowRecordsTheBundleOnLatch()
}
