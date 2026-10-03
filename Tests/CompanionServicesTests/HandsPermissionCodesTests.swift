import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// A refusal at the moment of acting names its permission or state and the
// next step, so the agent asks the user instead of retrying blind.

private final class LockFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Locks the moment it is asked to type, as a screen saver would mid-action.
private final class LockingHands: TextInjecting, @unchecked Sendable {
    let flag: LockFlag
    init(flag: LockFlag) { self.flag = flag }
    func inject(_ text: String, into field: FocusedField) async -> InjectionResult {
        flag.set()
        return .injected(text.count, via: .ax)
    }
}

private func runner(
    _ hands: FakeHands, injector: (any TextInjecting)? = nil, keys: (any KeyPressing)? = nil,
    target: ScriptedTarget = ScriptedTarget([7]), trusted: Bool = true, selfInFront: Bool = false,
    screenRecording: ScreenRecordingStatus = .verified, locked: @escaping @Sendable () -> Bool = { false },
    screen: FakeScreen? = nil, see: (@Sendable (SeeRequest) async -> ScreenBrief?)? = nil,
    workspace: FakeWorkspaceOpener = FakeWorkspaceOpener()
) -> ParentToolRunner {
    ParentToolRunner(
        workspace: workspace,
        hands: ScreenHands(
            injector: injector ?? hands, reader: hands, keys: keys ?? hands, windows: hands,
            trusted: { trusted }, target: { target.next() }, bundleID: { _ in "com.apple.Notes" },
            selfInFront: { selfInFront }, screen: screen, see: see,
            screenRecording: { screenRecording }, locked: locked))
}

private let window = [ScanNode(role: "AXButton", subrole: "", label: "Guardar", value: nil, secure: false)]

/// Presses, then locks, as a screen saver landing mid-action would.
private final class LockingKeys: KeyPressing, @unchecked Sendable {
    let flag: LockFlag
    init(flag: LockFlag) { self.flag = flag }
    func press(_ key: NamedKey, pid: Int32) -> Bool {
        flag.set()
        return true
    }
    func press(chord: KeyChord, pid: Int32) -> Bool { press(.return, pid: pid) }
}

@Test @MainActor func testALockedMacRefusesBeforeActing() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let out = await runner(hands, locked: { true })
        .execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.output.hasPrefix("\(BridgeCode.screenLocked):"), "locked: screen_locked: \(out.output)")
    expect(out.output.contains("unlock it, then call look"), "names the next step: \(out.output)")
    expect(hands.injected.isEmpty, "locked: nothing typed")
}

@Test @MainActor func testALockDuringTheActionReportsAnUnknownOutcome() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let flag = LockFlag()
    let out = await runner(hands, injector: LockingHands(flag: flag), locked: { flag.isSet })
        .execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(!out.ok, "locked mid-action: not reported as done")
    expect(out.output.hasPrefix("\(BridgeCode.screenLocked):"), "screen_locked: \(out.output)")
    expect(out.output.contains("outcome is unknown"), "says the outcome is unknown: \(out.output)")
}

@Test @MainActor func testSeeWithoutScreenRecordingNamesThePermission() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let asked = LockFlag()
    let out = await runner(hands, screenRecording: .notGranted, see: { _ in
        asked.set()
        return nil
    }).execute(name: "see", argumentsJSON: "{}")
    expect(out.output.hasPrefix("\(BridgeCode.screenRecordingRequired):"), "see: \(out.output)")
    expect(out.output.contains("Privacy & Security > Screen & System Audio Recording"),
           "names where the switch is: \(out.output)")
    expect(!asked.isSet, "no capture is attempted without the permission")
}

@Test @MainActor func testAWindowThatDidNotStayInFrontIsForegroundUnavailable() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), windows: ["Groceries"])
    // In front when the call starts and when it raises; another app has it right after.
    let out = await runner(hands, target: ScriptedTarget([7, 7, 9]))
        .execute(name: "focus_window", argumentsJSON: #"{"title":"Groceries"}"#)
    expect(out.output.hasPrefix("\(BridgeCode.foregroundUnavailable):"), "focus_window: \(out.output)")
    expect(out.output.contains("call look before retrying"), "names the next step: \(out.output)")
}

@Test @MainActor func testHandsWithoutAccessibilityNameThePath() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let out = await runner(hands, trusted: false).runHands(
        .typeText, ToolCallRef(id: "", name: "type_text", arguments: #"{"text":"x"}"#), ["text": "x"])
    expect(out.output.hasPrefix("\(BridgeCode.needsAccessibility):"), "untrusted: \(out.output)")
    expect(out.output.contains("Privacy & Security > Accessibility"), "names the path: \(out.output)")
}

@Test @MainActor func everyHandsAndSightToolRefusesWhileLocked() async {
    let calls: [(String, String)] = [
        ("look", "{}"), ("click", #"{"id":1}"#), ("scroll", #"{"direction":"down"}"#),
        ("menu", #"{"path":["File","Save"]}"#), ("see", "{}"), ("read_focused", "{}"),
        ("press_key", #"{"key":"return"}"#), ("focus_window", #"{"title":"Groceries"}"#),
        ("type_text", #"{"text":"x"}"#),
    ]
    for (name, arguments) in calls {
        let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), windows: ["Groceries"])
        let screen = FakeScreen(window)
        let asked = LockFlag()
        let out = await runner(hands, locked: { true }, screen: screen, see: { _ in
            asked.set()
            return ScreenBrief(summary: "x")
        }).execute(name: name, argumentsJSON: arguments)
        expect(out.output.hasPrefix("\(BridgeCode.screenLocked):"), "\(name) locked: \(out.output)")
        expect(hands.injected.isEmpty && hands.pressed.isEmpty && hands.raised.isEmpty, "\(name): no hands used")
        expect(screen.clicks.isEmpty && screen.scrolls.isEmpty && screen.menus.isEmpty && screen.generation == 0,
               "\(name): the screen was not touched")
        expect(!asked.isSet, "\(name): no capture")
    }
}

@Test @MainActor func aLockedMacWinsOverAMissingPermission() async {
    let out = await runner(FakeHands(), trusted: false, locked: { true }).runHands(
        .typeText, ToolCallRef(id: "", name: "type_text", arguments: #"{"text":"x"}"#), ["text": "x"])
    expect(out.output.hasPrefix("\(BridgeCode.screenLocked):"), "locked and untrusted: \(out.output)")
}

@Test @MainActor func aClickCaughtByALockReportsAnUnknownOutcome() async {
    let screen = FakeScreen(window)
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let runner = runner(hands, locked: { !screen.clicks.isEmpty }, screen: screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let out = await runner.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(!out.ok, "click caught by the lock: not reported as done")
    expect(out.output.contains("outcome is unknown"), "click: unknown outcome: \(out.output)")
}

@Test @MainActor func aKeyPressCaughtByALockReportsAnUnknownOutcome() async {
    let flag = LockFlag()
    let out = await runner(FakeHands(field: FocusedField(app: "Notes", pid: 7)), keys: LockingKeys(flag: flag),
                           locked: { flag.isSet })
        .execute(name: "press_key", argumentsJSON: #"{"key":"return"}"#)
    expect(out.output.hasPrefix("\(BridgeCode.screenLocked):") && out.output.contains("outcome is unknown"),
           "press_key: \(out.output)")
    expectEq(out.target, "return", "the target it was acting on is kept")
}

@Test @MainActor func aReadThatEndsLockedIsStillARead() async {
    let screen = FakeScreen(window)
    // The walk is the read; locked from the moment it ran.
    let out = await runner(FakeHands(field: FocusedField(app: "Notes", pid: 7)),
                           locked: { screen.generation > 0 }, screen: screen)
        .execute(name: "look", argumentsJSON: "{}")
    expect(out.ok, "look that ends locked: still the window it read: \(out.output)")
}

@Test @MainActor func aCaptureThatRanIntoTheLockIsDropped() async {
    let captured = LockFlag()
    let out = await runner(FakeHands(field: FocusedField(app: "Notes", pid: 7)), locked: { captured.isSet },
                           see: { _ in
        captured.set()
        return ScreenBrief(summary: "the lock screen")
    }).execute(name: "see", argumentsJSON: "{}")
    expect(out.output.hasPrefix("\(BridgeCode.screenLocked):"), "see that ran into the lock: \(out.output)")
    expect(!out.output.contains("the lock screen"), "its pixels never reach the model")
}

@Test @MainActor func seeWithScreenRecordingStillCaptures() async {
    let asked = LockFlag()
    let out = await runner(FakeHands(field: FocusedField(app: "Notes", pid: 7)), see: { _ in
        asked.set()
        return ScreenBrief(summary: "a window")
    }).execute(name: "see", argumentsJSON: "{}")
    expect(asked.isSet && out.ok, "granted: the capture runs: \(out.output)")
}

@Test @MainActor func companionInFrontIsSelfInFrontAndAccessibilityComesFirst() async {
    let call = ToolCallRef(id: "", name: "type_text", arguments: #"{"text":"x"}"#)
    let front = await runner(FakeHands(), selfInFront: true).runHands(.typeText, call, ["text": "x"])
    expect(front.output.hasPrefix("\(BridgeCode.selfInFront):"), "in front: \(front.output)")
    expect(front.output == "\(BridgeCode.selfInFront): \(BridgeMessages.selfInFront)", "one shared text")
    let both = await runner(FakeHands(), trusted: false, selfInFront: true).runHands(.typeText, call, ["text": "x"])
    expect(both.output.hasPrefix("\(BridgeCode.needsAccessibility):"), "untrusted and in front: \(both.output)")
}

@Test @MainActor func noHandsWiredIsNotAvailable() async {
    let out = await ParentToolRunner(workspace: FakeWorkspaceOpener()).runHands(
        .typeText, ToolCallRef(id: "", name: "type_text", arguments: #"{"text":"x"}"#), ["text": "x"])
    expect(out.output.hasPrefix("\(BridgeCode.notAvailable):"), "no hands: \(out.output)")
}

@Test @MainActor func aWindowThatStaysInFrontIsRaised() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), windows: ["Groceries"])
    let raised = await runner(hands, target: ScriptedTarget([7, 7, 7]))
        .execute(name: "focus_window", argumentsJSON: #"{"title":"Groceries"}"#)
    expect(raised.ok && raised.output == "raised Groceries", "stays in front: \(raised.output)")
    let missing = await runner(hands, target: ScriptedTarget([7, 7, 9]))
        .execute(name: "focus_window", argumentsJSON: #"{"title":"Taxes"}"#)
    expect(missing.output.hasPrefix("window_not_found:"), "no such window comes first: \(missing.output)")
}

@Test @MainActor func opensRefuseWhileLocked() async {
    for (name, arguments) in [("open_app", #"{"name":"Safari"}"#), ("open_url", #"{"url":"https://example.com"}"#)] {
        let workspace = FakeWorkspaceOpener()
        let out = await runner(FakeHands(), locked: { true }, workspace: workspace)
            .execute(name: name, argumentsJSON: arguments)
        expect(out.output.hasPrefix("\(BridgeCode.screenLocked):"), "\(name) locked: \(out.output)")
        expect(workspace.openedApps.isEmpty && workspace.openedURLs.isEmpty, "\(name): nothing opened")
    }
}

// Gap 1: the switch can read on while captures fail. Only a missing grant
// refuses up front; a capture that came back empty without a verified grant
// is the permission, not a vague no_capture.
@Test @MainActor func seeWithTheGrantUnverifiedStillTriesTheCapture() async {
    let asked = LockFlag()
    let out = await runner(FakeHands(field: FocusedField(app: "Notes", pid: 7)),
                           screenRecording: .grantedUnverified, see: { _ in
        asked.set()
        return ScreenBrief(summary: "a window")
    }).execute(name: "see", argumentsJSON: "{}")
    expect(asked.isSet && out.ok, "unverified: the capture is what verifies it: \(out.output)")
}

@Test @MainActor func anEmptyCaptureWithoutAVerifiedGrantNamesThePermission() async {
    for status in [ScreenRecordingStatus.grantedUnverified, .stale] {
        let asked = LockFlag()
        let out = await runner(FakeHands(field: FocusedField(app: "Notes", pid: 7)),
                               screenRecording: status, see: { _ in
            asked.set()
            return nil
        }).execute(name: "see", argumentsJSON: "{}")
        expect(asked.isSet, "\(status): the capture was tried before naming the permission")
        expect(out.output == "\(BridgeCode.screenRecordingRequired): \(BridgeMessages.screenRecordingRequired)",
               "\(status): \(out.output)")
    }
}

/// Answers each status in turn, as the gate moves while the capture runs.
private final class StatusScript: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [ScreenRecordingStatus]
    init(_ queue: [ScreenRecordingStatus]) { self.queue = queue }
    func next() -> ScreenRecordingStatus { lock.withLock { queue.count > 1 ? queue.removeFirst() : queue[0] } }
}

@Test @MainActor func anEmptyCaptureIsJudgedByTheStatusAfterIt() async {
    let call = { (statuses: [ScreenRecordingStatus]) async -> String in
        let script = StatusScript(statuses)
        let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
        return await ParentToolRunner(
            workspace: FakeWorkspaceOpener(),
            hands: ScreenHands(
                injector: hands, reader: hands, keys: hands, windows: hands,
                trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.Notes" },
                see: { _ in nil }, screenRecording: { script.next() }))
            .execute(name: "see", argumentsJSON: "{}").output
    }
    let verifiedDuring = await call([.grantedUnverified, .verified])
    expect(verifiedDuring.hasPrefix("no_capture:"), "verified by the capture's own probe: \(verifiedDuring)")
    let lostDuring = await call([.verified, .stale])
    expect(lostDuring.hasPrefix("\(BridgeCode.screenRecordingRequired):"), "lost during the capture: \(lostDuring)")
}

@Test @MainActor func anEmptyCaptureWithAVerifiedGrantIsNoCapture() async {
    let out = await runner(FakeHands(field: FocusedField(app: "Notes", pid: 7)), see: { _ in nil })
        .execute(name: "see", argumentsJSON: "{}")
    expect(out.output.hasPrefix("no_capture:"), "verified: not the permission: \(out.output)")
    expect(!out.output.contains("Screen Recording"), "does not blame the permission: \(out.output)")
}

@Test @MainActor func theAppsHandsReadTheGate() async {
    let checker = FakeScreenRecording(granted: true, captures: false)
    let gate = ScreenRecordingGate(checker: checker)
    let hands = ScreenHands(
        ax: AXTextInjector(selfBundleID: "com.karen.companion", trust: { true })!,
        screen: AXScreen(selfBundleID: "com.karen.companion", trust: { true }),
        target: { 7 }, gate: gate)
    expectEq(hands.screenRecording(), .grantedUnverified, "hands: the gate's state, not the preflight")
    _ = await gate.verify()
    expectEq(hands.screenRecording(), .grantedUnverified, "a failed probe stays unverified")
    checker.captures = true
    _ = await gate.verify()
    expectEq(hands.screenRecording(), .verified, "hands: follow the gate")
    // A capture refused by the preflight never reaches the gate, so a revoke
    // must read through it or see would blame vision for good.
    checker.granted = false
    expectEq(hands.screenRecording(), .notGranted, "hands: a revoke the gate has not probed yet")
    expectEq(checker.requests, 0, "reading the gate never asks")
}
