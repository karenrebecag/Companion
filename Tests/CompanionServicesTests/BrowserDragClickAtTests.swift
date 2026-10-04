import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// H-7 P7: browser_drag and browser_click_at (Incredible's el.drag_to(target),
// el.drag_by(dx, dy) and tab.click_at(x, y)). A coordinate has no label to
// judge, so click_at always asks; a drag is judged on both ends. As in
// Incredible, the read that click_at's point and drag's target come from goes
// stale after 60 s, on navigation or on another read.

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

private func makeClockRig(_ clock: TestClock, owned: Bool = true) -> BrowserToolRig {
    let presence = BrowserPresence()
    presence.set(.comet)
    let page = crmPage()
    let channel = FakeBrowserChannel(pages: [page], tabs: [BrowserTab(id: 12, title: "CRM", url: page.url, active: false)])
    let leases = BrowserLeases(epoch: presence.epoch)
    if owned { leases.acquire(tab: 12, caller: "chat") }
    let runner = BrowserToolRunner(
        channel: channel, presence: presence, leases: leases, caller: "chat", now: { clock.now })
    return BrowserToolRig(runner: runner, channel: channel, presence: presence)
}

// MARK: - specs

@Test func dragAndClickAtAreOfferedWithTheirArguments() {
    let rig = makeToolRig()
    for language in [AppLanguage.en, .es] {
        let specs = rig.runner.specs(language)
        guard let drag = specs.first(where: { $0.name == "browser_drag" }),
              let clickAt = specs.first(where: { $0.name == "browser_click_at" })
        else { Issue.record("missing in \(language)"); continue }
        expectEq(drag.required, ["tab", "element"], "drag: a source from the last read")
        expectEq(Set(drag.properties.map(\.name)), ["tab", "element", "to", "dx", "dy"], "drag: to a target or by an offset")
        expectEq(clickAt.required, ["tab", "x", "y"], "click_at: a point")
        for property in drag.properties + clickAt.properties {
            expect(property.description != property.name, "\(property.name) \(language): described")
        }
    }
}

// MARK: - click_at

@Test func clickAtAlwaysAsksAndADenialSendsNothing() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    let arguments = #"{"tab":12,"x":40,"y":60}"#
    let request = rig.runner.approval(for: rig.call("browser_click_at", arguments), said: "pulsa ahí")
    expectEq(request?.summary, "click at (40, 60) in \(crm)", "a point has no label to judge: always a sheet")
    let out = await rig.runner.execute(name: "browser_click_at", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "denied: no click")
    expect(rig.channel.writes.isEmpty, "the extension hears nothing")
}

@Test func anApprovedClickAtGoesOutWithTheReadsGeneration() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    let out = await rig.run("browser_click_at", #"{"tab":12,"x":40,"y":60}"#, approve: true)
    expect(out.ok && out.output.hasPrefix("clicked at (40, 60)"), "runs: \(out.output)")
    guard case .clickAt(12, 3, 40, 60)? = rig.channel.writes.first else {
        Issue.record("no click at sent: \(rig.channel.writes)"); return
    }
}

@Test func clickAtWithoutAFreshReadIsStale() async {
    let clock = TestClock()
    let unread = makeClockRig(clock)
    expect(unread.runner.approval(for: unread.call("browser_click_at", #"{"tab":12,"x":40,"y":60}"#), said: "") == nil,
           "no read: nothing to ask about")
    let none = await unread.runner.execute(name: "browser_click_at", argumentsJSON: #"{"tab":12,"x":40,"y":60}"#)
    expect(!none.ok && none.output.contains(BridgeCode.staleId), "no read: stale")

    let rig = makeClockRig(clock)
    await rig.read()
    clock.advance(59)
    expect(rig.runner.approval(for: rig.call("browser_click_at", #"{"tab":12,"x":40,"y":60}"#), said: "") != nil,
           "59 s: still fresh")
    clock.advance(2)
    let old = await rig.run("browser_click_at", #"{"tab":12,"x":40,"y":60}"#, approve: true)
    expect(!old.ok && old.output.contains(BridgeCode.staleId), "61 s: the screen it was read from is gone")
    expect(rig.channel.writes.isEmpty, "never clicked")
}

@Test func anApprovedClickAtThatWentStaleIsNotClicked() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    let arguments = #"{"tab":12,"x":40,"y":60}"#
    if let request = rig.runner.approval(for: rig.call("browser_click_at", arguments), said: "") { rig.runner.granted(request) }
    clock.advance(61)
    let out = await rig.runner.execute(name: "browser_click_at", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "the yes was for the screen as it was a minute ago")
    expect(rig.channel.writes.isEmpty, "never clicked")
}

@Test func aClickAtPointMustBeWholeNonNegativePixels() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    for arguments in [#"{"tab":12,"x":-1,"y":60}"#, #"{"tab":12,"x":40}"#, #"{"tab":12,"x":40.5,"y":60}"#,
                      #"{"tab":12,"x":40,"y":20001}"#, #"{"tab":12,"x":-9223372036854775808,"y":0}"#,
                      #"{"tab":12,"x":9223372036854775807,"y":0}"#] {
        let out = await rig.run("browser_click_at", arguments, approve: true)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "\(arguments): refused, \(out.output)")
    }
    expect(rig.channel.writes.isEmpty, "never clicked")
}

// MARK: - drag

@Test func aDragBetweenHarmlessElementsActsWithoutASheet() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    let arguments = #"{"tab":12,"element":1,"to":7}"#
    expect(rig.runner.approval(for: rig.call("browser_drag", arguments), said: "") == nil, "Guardar onto Ayuda: no sheet")
    let out = await rig.runner.execute(name: "browser_drag", argumentsJSON: arguments)
    expect(out.ok && out.output.hasPrefix("dragged [1] to [7]"), "runs: \(out.output)")
    guard case .dragTo(12, 3, 1, 7)? = rig.channel.writes.first else {
        Issue.record("no drag sent: \(rig.channel.writes)"); return
    }
}

@Test func aDragAsksWhenEitherEndWould() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    let onto = rig.runner.approval(for: rig.call("browser_drag", #"{"tab":12,"element":1,"to":2}"#), said: "")
    expectEq(onto?.summary, "drag Guardar to Eliminar in \(crm)", "dropping onto a destructive target asks")
    expect(rig.runner.approval(for: rig.call("browser_drag", #"{"tab":12,"element":2,"to":1}"#), said: "") != nil,
           "dragging a destructive control asks")
    expect(rig.runner.approval(for: rig.call("browser_drag", #"{"tab":12,"element":1,"to":3}"#), said: "") != nil,
           "a link to another origin as the target asks")
    expect(rig.runner.approval(for: rig.call("browser_drag", #"{"tab":12,"element":6,"to":1}"#), said: "") != nil,
           "a foreign frame as the source asks")
    let denied = await rig.runner.execute(name: "browser_drag", argumentsJSON: #"{"tab":12,"element":1,"to":2}"#)
    expect(!denied.ok && denied.output.contains("approval_required"), "no ticket, no drag")
    expect(rig.channel.writes.isEmpty, "nothing dragged")
}

// An offset names no element at the drop end, so nothing there can be judged: like a bare point, it asks.
@Test func aDragByAnOffsetAlwaysAsks() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    let arguments = #"{"tab":12,"element":1,"dx":120,"dy":-30}"#
    let request = rig.runner.approval(for: rig.call("browser_drag", arguments), said: "")
    expectEq(request?.summary, "drag Guardar by (120, -30) in \(crm)", "even a harmless source asks: the drop end is unknown")
    let denied = await rig.runner.execute(name: "browser_drag", argumentsJSON: arguments)
    expect(!denied.ok && denied.output.contains("approval_required"), "no yes, no drag: \(denied.output)")
    expect(rig.channel.writes.isEmpty, "nothing dragged")
    let out = await rig.run("browser_drag", arguments, approve: true)
    expect(out.ok && out.output.hasPrefix("dragged [1] by (120, -30)"), "approved: \(out.output)")
    guard case .dragBy(12, 3, 1, 120, -30)? = rig.channel.writes.first else {
        Issue.record("no drag by sent: \(rig.channel.writes)"); return
    }
}

@Test func aDragByAnOffsetNeedsNoFreshRead() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    clock.advance(120)
    let out = await rig.run("browser_drag", #"{"tab":12,"element":1,"dx":0,"dy":200}"#, approve: true)
    expect(out.ok, "only the source is named, and it is checked by id and origin: \(out.output)")
}

@Test func aDragTargetFromAStaleReadIsNotDropped() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    clock.advance(61)
    let out = await rig.run("browser_drag", #"{"tab":12,"element":1,"to":7}"#, approve: true)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "the target was measured a minute ago")
    expect(rig.channel.writes.isEmpty, "nothing dragged")
}

@Test func aDragTicketFollowsNeitherLabelNorAnotherRead() async {
    // The control: an unchanged page spends the yes, so each refusal below is the change's doing.
    let unchanged = makeClockRig(TestClock())
    await unchanged.read()
    let out = await unchanged.run("browser_drag", #"{"tab":12,"element":1,"to":2}"#, approve: true)
    expect(out.ok, "same page: the yes is spent: \(out.output)")

    let relabels: [(String, (inout BrowserPage) -> Void)] = [
        ("target", { $0.elements[1].label = "Enviar pago" }),
        ("source", { $0.elements[0].label = "Borrar todo" }),
    ]
    for (end, change) in relabels {
        let rig = makeClockRig(TestClock())
        await rig.read()
        let arguments = #"{"tab":12,"element":1,"to":2}"#
        if let request = rig.runner.approval(for: rig.call("browser_drag", arguments), said: "") { rig.runner.granted(request) }
        var swapped = crmPage(generation: 3)
        change(&swapped)
        rig.channel.setPage(swapped)
        await rig.read()
        let after = await rig.runner.execute(name: "browser_drag", argumentsJSON: arguments)
        expect(!after.ok && after.output.contains("approval_required"), "\(end) relabelled: \(after.output)")
        expect(rig.channel.writes.isEmpty, "\(end): nothing dragged")
    }

    let rig = makeClockRig(TestClock())
    await rig.read()
    let arguments = #"{"tab":12,"element":1,"to":2}"#
    if let request = rig.runner.approval(for: rig.call("browser_drag", arguments), said: "") { rig.runner.granted(request) }
    rig.channel.setPage(crmPage(generation: 4))
    await rig.read()
    let reread = await rig.runner.execute(name: "browser_drag", argumentsJSON: arguments)
    expect(!reread.ok && reread.output.contains("approval_required"), "same labels, another read: \(reread.output)")
    expect(rig.channel.writes.isEmpty, "nothing dragged")
}

@Test func aGrantedDragThatWentStaleIsNotDropped() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    let arguments = #"{"tab":12,"element":1,"to":2}"#
    if let request = rig.runner.approval(for: rig.call("browser_drag", arguments), said: "") { rig.runner.granted(request) }
    clock.advance(61)
    let out = await rig.runner.execute(name: "browser_drag", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "the yes was for a screen a minute old: \(out.output)")
    expect(rig.channel.writes.isEmpty, "nothing dragged")
}

@Test func theReadIsFreshForExactlySixtySeconds() async {
    for (name, arguments) in [("browser_drag", #"{"tab":12,"element":1,"to":2}"#),
                              ("browser_click_at", #"{"tab":12,"x":40,"y":60}"#)] {
        let clock = TestClock()
        let rig = makeClockRig(clock)
        await rig.read()
        clock.advance(60)
        expect(rig.runner.approval(for: rig.call(name, arguments), said: "") != nil, "\(name) at 60 s: still fresh")
        clock.advance(1)
        expect(rig.runner.approval(for: rig.call(name, arguments), said: "") == nil, "\(name) at 61 s: nothing to ask about")
    }
}

@Test func aClickAtTicketIsSpentOnceAndBoundToItsRead() async {
    let arguments = #"{"tab":12,"x":40,"y":60}"#
    let once = makeClockRig(TestClock())
    await once.read()
    let first = await once.run("browser_click_at", arguments, approve: true)
    expect(first.ok, "approved: \(first.output)")
    let second = await once.runner.execute(name: "browser_click_at", argumentsJSON: arguments)
    expect(!second.ok && second.output.contains("approval_required"), "one yes, one click: \(second.output)")
    expectEq(once.channel.writes.count, 1, "clicked once")

    let reread = makeClockRig(TestClock())
    await reread.read()
    if let request = reread.runner.approval(for: reread.call("browser_click_at", arguments), said: "") {
        reread.runner.granted(request)
    }
    reread.channel.setPage(crmPage(generation: 4))
    await reread.read()
    let afterRead = await reread.runner.execute(name: "browser_click_at", argumentsJSON: arguments)
    expect(!afterRead.ok && afterRead.output.contains("approval_required"), "another read: \(afterRead.output)")
    expect(reread.channel.writes.isEmpty, "never clicked")

    let moved = makeClockRig(TestClock())
    await moved.read()
    if let request = moved.runner.approval(for: moved.call("browser_click_at", arguments), said: "") {
        moved.runner.granted(request)
    }
    moved.channel.setTabs([BrowserTab(id: 12, title: "Phish", url: "https://evil.example/", active: true)])
    let afterMove = await moved.runner.execute(name: "browser_click_at", argumentsJSON: arguments)
    expect(!afterMove.ok && afterMove.output.contains(BridgeCode.staleId), "another site now: \(afterMove.output)")
    expect(moved.channel.writes.isEmpty, "never clicked")
}

@Test func aStaleAnswerFromTheExtensionForgetsTheRead() async {
    let rig = makeClockRig(TestClock())
    await rig.read()
    rig.channel.failWrites(with: ContractError(code: BridgeCode.staleId, message: "gone"))
    _ = await rig.run("browser_drag", #"{"tab":12,"element":1,"to":7}"#, approve: true)
    let next = await rig.runner.execute(name: "browser_click_at", argumentsJSON: #"{"tab":12,"x":40,"y":60}"#)
    expect(!next.ok && next.output.contains(BridgeCode.staleId), "the page the read described is gone: \(next.output)")
}

@Test func aDragFromAnElementTheReadNeverGaveAsksNothing() async {
    let rig = makeClockRig(TestClock())
    await rig.read()
    expect(rig.runner.approval(for: rig.call("browser_drag", #"{"tab":12,"element":99,"to":1}"#), said: "") == nil, "unknown source")
    expect(rig.runner.approval(for: rig.call("browser_drag", #"{"tab":12,"element":1,"to":99}"#), said: "") == nil, "unknown target")
    let out = await rig.run("browser_drag", #"{"tab":12,"element":99,"to":1}"#, approve: true)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "read first: \(out.output)")
}

// The click gate never refuses today, but a drag must not soften a refusal from either end if it ever does.
@Test func theStricterEndDecidesADrag() {
    let refuse = HandsVerdict.refuse("no")
    let cases: [(HandsVerdict, HandsVerdict, HandsVerdict)] = [
        (.act, .act, .act), (.act, .ask, .ask), (.ask, .act, .ask), (.ask, .ask, .ask),
        (refuse, .act, refuse), (.act, refuse, refuse), (refuse, .ask, refuse), (.ask, refuse, refuse),
    ]
    for (first, second, want) in cases {
        expectEq(BrowserToolRunner.stricter(first, second), want, "\(first) with \(second)")
    }
}

@Test func theLimitsThemselvesAreAccepted() async {
    let rig = makeClockRig(TestClock())
    await rig.read()
    for (name, arguments) in [("browser_click_at", #"{"tab":12,"x":20000,"y":0}"#),
                              ("browser_drag", #"{"tab":12,"element":1,"dx":-20000,"dy":20000}"#),
                              ("browser_drag", #"{"tab":12,"element":1,"dx":50}"#)] {
        let out = await rig.run(name, arguments, approve: true)
        expect(out.ok, "\(arguments): within the limits, \(out.output)")
    }
}

@Test func aDragThatSaysTooLittleOrTooMuchIsRefused() async {
    let clock = TestClock()
    let rig = makeClockRig(clock)
    await rig.read()
    for arguments in [
        #"{"tab":12,"element":1}"#,
        #"{"tab":12,"element":1,"dx":0,"dy":0}"#,
        #"{"tab":12,"element":1,"to":7,"dx":10,"dy":0}"#,
        #"{"tab":12,"element":1,"to":1}"#,
        #"{"tab":12,"element":1,"dx":20001,"dy":0}"#,
        #"{"tab":12,"element":1,"dx":-9223372036854775808,"dy":0}"#,
        #"{"tab":12,"element":1,"to":"seven"}"#,
        #"{"tab":12,"element":1,"dx":0,"dy":-20001}"#,
        #"{"tab":12,"element":1,"dx":0,"dy":9223372036854775807}"#,
    ] {
        let out = await rig.run("browser_drag", arguments, approve: true)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "\(arguments): refused, \(out.output)")
    }
    expect(rig.channel.writes.isEmpty, "nothing dragged")
}

@Test func dragAndClickAtNeedControlOfTheTab() async {
    let clock = TestClock()
    let rig = makeClockRig(clock, owned: false)
    for (name, arguments) in [("browser_drag", #"{"tab":12,"element":1,"to":7}"#),
                              ("browser_click_at", #"{"tab":12,"x":40,"y":60}"#)] {
        let out = await rig.run(name, arguments, approve: true)
        expect(!out.ok && out.output.contains(BridgeCode.notControlled), "\(name): not this caller's tab")
    }
    expect(rig.channel.writes.isEmpty, "nothing sent")
}

@Test func dragAndClickAtAreBridgeWritesInBothScopes() {
    for name in ["browser_drag", "browser_click_at"] {
        expect(BridgePolicy.writeTools.contains(name), "\(name): a write for the bridge's budget")
        expect(BridgeScope.bridgeTools.contains(name), "\(name): offered over the bridge")
    }
}
