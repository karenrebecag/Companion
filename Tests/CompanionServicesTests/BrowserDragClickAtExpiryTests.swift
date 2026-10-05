import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// H-7 P7: what makes a yes for browser_drag or browser_click_at stop holding:
// the page moving under it (same origin included), the read ageing past
// BrowserTool.readFreshness, another read, or arguments that are not the ones
// the user saw.

/// Asks the gate and grants, failing loudly when the gate had nothing to ask:
/// a silent skip would let the test pass on a yes that was never given.
func grantApproval(_ rig: BrowserToolRig, _ name: String, _ arguments: String) {
    let request = rig.runner.approval(for: rig.call(name, arguments), said: "")
    expect(request != nil, "\(name) \(arguments): the gate asks")
    if let request { rig.runner.granted(request) }
}

/// Only the P7 presses: a navigation is also a write, but not the one under test.
private func pressCount(_ rig: BrowserToolRig) -> Int {
    rig.channel.writes.filter {
        switch $0 {
        case .dragTo, .dragBy, .clickAt: return true
        default: return false
        }
    }.count
}

private let clickAtCall = ("browser_click_at", #"{"tab":12,"x":40,"y":60}"#)
private let dragToCall = ("browser_drag", #"{"tab":12,"element":1,"to":2}"#)
private let dragByCall = ("browser_drag", #"{"tab":12,"element":1,"dx":30,"dy":0}"#)
private let everyAction = [clickAtCall, dragToCall, dragByCall]

private func tab(at url: String) -> [BrowserTab] {
    [BrowserTab(id: 12, title: "CRM", url: url, active: false)]
}

// MARK: - same-origin navigation

@Test func aYesDoesNotSurviveANavigationToAnotherPathOfTheSameOrigin() async {
    for (name, arguments) in everyAction {
        let rig = makeClockRig(TestClock())
        await rig.read()
        grantApproval(rig, name, arguments)
        rig.channel.setTabs(tab(at: crm + "/settings"))
        let out = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.staleId), "\(name) \(arguments): another page now: \(out.output)")
        expectEq(pressCount(rig), 0, "\(name) \(arguments): pressed on a page nobody read")
        let unread = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!unread.ok && unread.output.contains(BridgeCode.staleId), "\(name) \(arguments): the read was forgotten: \(unread.output)")
        await rig.read()
        let again = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!again.ok && again.output.contains("approval_required"), "\(name) \(arguments): the old yes is gone: \(again.output)")
        expectEq(pressCount(rig), 0, "\(name) \(arguments): still nothing pressed")
    }
}

@Test func aFragmentOnlyChangeIsStillThePageThatWasRead() async {
    for (name, arguments) in everyAction {
        let rig = makeClockRig(TestClock())
        await rig.read()
        grantApproval(rig, name, arguments)
        rig.channel.setTabs(tab(at: crm + "/a#details"))
        let out = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(out.ok, "\(name) \(arguments): an anchor jump is not a new page: \(out.output)")
        expectEq(pressCount(rig), 1, "\(name) \(arguments): pressed once")
    }
}

@Test func aQueryChangeIsAnotherPage() async {
    for (name, arguments) in everyAction {
        let rig = makeClockRig(TestClock())
        await rig.read()
        grantApproval(rig, name, arguments)
        rig.channel.setTabs(tab(at: crm + "/a?step=2"))
        let out = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.staleId), "\(name): \(out.output)")
        expectEq(pressCount(rig), 0, "\(name): nothing pressed")
    }
}

@Test func aTabTheListingCannotShowIsNotThePageThatWasRead() async {
    for (name, arguments) in everyAction {
        let missing = makeClockRig(TestClock())
        await missing.read()
        grantApproval(missing, name, arguments)
        missing.channel.setTabs([])
        let gone = await missing.runner.execute(name: name, argumentsJSON: arguments)
        expect(!gone.ok && gone.output.contains(BridgeCode.staleId), "\(name): no such tab, \(gone.output)")
        expectEq(pressCount(missing), 0, "\(name): nothing pressed")

        let blank = makeClockRig(TestClock())
        await blank.read()
        grantApproval(blank, name, arguments)
        blank.channel.setTabs(tab(at: ""))
        let unknown = await blank.runner.execute(name: name, argumentsJSON: arguments)
        expect(!unknown.ok && unknown.output.contains(BridgeCode.staleId), "\(name): no address, \(unknown.output)")
        expectEq(pressCount(blank), 0, "\(name): nothing pressed")
    }
}

@Test func aNavigationThroughTheRunnerExpiresTheYes() async {
    for (name, arguments) in everyAction {
        let rig = makeClockRig(TestClock())
        await rig.read()
        grantApproval(rig, name, arguments)
        let moved = await rig.run("browser_navigate", #"{"tab":12,"url":"\#(crm)/b"}"#, approve: true)
        expect(moved.ok, "navigated: \(moved.output)")
        let out = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.staleId), "\(name): the page it was read from is gone: \(out.output)")
        expectEq(pressCount(rig), 0, "\(name): nothing pressed")
    }
}

// MARK: - the yes is for these arguments

@Test func aClickAtYesIsForThatPointOnly() async {
    for moved in [#"{"tab":12,"x":41,"y":60}"#, #"{"tab":12,"x":40,"y":61}"#] {
        let rig = makeClockRig(TestClock())
        await rig.read()
        grantApproval(rig, clickAtCall.0, clickAtCall.1)
        let out = await rig.runner.execute(name: "browser_click_at", argumentsJSON: moved)
        expect(!out.ok && out.output.contains("approval_required"), "\(moved): not the point that was approved: \(out.output)")
        expectEq(pressCount(rig), 0, "\(moved): nothing pressed")
    }
}

@Test func anOffsetDragYesIsForThatOffsetAndThatElementOnly() async {
    let approved = #"{"tab":12,"element":1,"dx":120,"dy":-30}"#
    for changed in [#"{"tab":12,"element":1,"dx":121,"dy":-30}"#, #"{"tab":12,"element":1,"dx":120,"dy":-29}"#,
                    #"{"tab":12,"element":2,"dx":120,"dy":-30}"#] {
        let rig = makeClockRig(TestClock())
        await rig.read()
        grantApproval(rig, "browser_drag", approved)
        let out = await rig.runner.execute(name: "browser_drag", argumentsJSON: changed)
        expect(!out.ok && out.output.contains("approval_required"), "\(changed): not what was approved: \(out.output)")
        expectEq(pressCount(rig), 0, "\(changed): nothing pressed")
    }
}

@Test func anElementDragYesIsForThatPairOnly() async {
    for changed in [#"{"tab":12,"element":1,"to":7}"#, #"{"tab":12,"element":2,"to":1}"#] {
        let rig = makeClockRig(TestClock())
        await rig.read()
        grantApproval(rig, "browser_drag", dragToCall.1)
        // Both ends would be fine on their own for 1 -> 7, so a pass here would be the yes leaking, not the gate.
        let out = await rig.runner.execute(name: "browser_drag", argumentsJSON: changed)
        expect(!out.ok && out.output.contains("approval_required"), "\(changed): not the pair approved: \(out.output)")
        expectEq(pressCount(rig), 0, "\(changed): nothing pressed")
    }
}

@Test func aDragYesIsSpentOnce() async {
    for (name, arguments) in [dragToCall, dragByCall] {
        let rig = makeClockRig(TestClock())
        await rig.read()
        let first = await rig.run(name, arguments, approve: true)
        expect(first.ok, "\(arguments): approved: \(first.output)")
        let second = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!second.ok && second.output.contains("approval_required"), "\(arguments): one yes, one drag: \(second.output)")
        expectEq(pressCount(rig), 1, "\(arguments): dragged once")
    }
}

// MARK: - one 60 s window, from the read

@Test func theWindowIsCheckedAtExecuteAndApprovalDoesNotRestartIt() async {
    for (name, arguments) in everyAction {
        let edge = TestClock()
        let rig = makeClockRig(edge)
        await rig.read()
        grantApproval(rig, name, arguments)
        edge.advance(60)
        let atEdge = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(atEdge.ok, "\(name) \(arguments): 60 s after the read still acts: \(atEdge.output)")
        expectEq(pressCount(rig), 1, "\(name) \(arguments): pressed once")

        let past = TestClock()
        let late = makeClockRig(past)
        await late.read()
        grantApproval(late, name, arguments)
        past.advance(61)
        let beyond = await late.runner.execute(name: name, argumentsJSON: arguments)
        expect(!beyond.ok && beyond.output.contains(BridgeCode.staleId), "\(name) \(arguments): 61 s: \(beyond.output)")
        expectEq(pressCount(late), 0, "\(name) \(arguments): nothing pressed")

        let restarted = TestClock()
        let slow = makeClockRig(restarted)
        await slow.read()
        restarted.advance(40)
        grantApproval(slow, name, arguments)
        restarted.advance(21)
        let lateYes = await slow.runner.execute(name: name, argumentsJSON: arguments)
        expect(!lateYes.ok && lateYes.output.contains(BridgeCode.staleId),
               "\(name) \(arguments): a yes at 40 s does not buy another minute: \(lateYes.output)")
        expectEq(pressCount(slow), 0, "\(name) \(arguments): nothing pressed")
    }
}

@Test func anOffsetDragYesDiesWithAnotherRead() async {
    let rig = makeClockRig(TestClock())
    await rig.read()
    grantApproval(rig, dragByCall.0, dragByCall.1)
    rig.channel.setPage(crmPage(generation: 4))
    await rig.read()
    let out = await rig.runner.execute(name: dragByCall.0, argumentsJSON: dragByCall.1)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "another read of the page: \(out.output)")
    expectEq(pressCount(rig), 0, "nothing dragged")
    let again = await rig.runner.execute(name: dragByCall.0, argumentsJSON: dragByCall.1)
    expect(!again.ok && again.output.contains("approval_required"), "the old yes is gone: \(again.output)")
    expectEq(pressCount(rig), 0, "still nothing dragged")
}

// MARK: - arguments

@Test func dragArgumentsOutsideTheContractAreRefused() async {
    let rig = makeClockRig(TestClock())
    await rig.read()
    for arguments in [
        #"{"tab":12,"element":1,"dx":10.5,"dy":0}"#,
        #"{"tab":12,"element":1,"dx":"ten","dy":0}"#,
        #"{"tab":12,"element":1,"to":null}"#,
        #"{"tab":12,"element":1,"dx":null,"dy":5}"#,
        #"{"tab":12,"element":1,"dx":5,"dy":null}"#,
        #"{"tab":12,"to":2}"#,
        #"{"tab":12,"dx":5,"dy":5}"#,
        #"{"element":1,"to":2}"#,
        #"{"tab":"x","element":1,"to":2}"#,
    ] {
        let out = await rig.run("browser_drag", arguments, approve: true)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "\(arguments): refused, \(out.output)")
    }
    expectEq(pressCount(rig), 0, "nothing dragged")
}

// intArgument reads whole numbers from strings on purpose (models quote numbers); a drag follows it.
@Test func aDragOffsetGivenAsAWholeNumberStringIsReadAsThatNumber() async {
    let rig = makeClockRig(TestClock())
    await rig.read()
    let out = await rig.run("browser_drag", #"{"tab":12,"element":1,"dx":"10","dy":0}"#, approve: true)
    expect(out.ok, "a quoted whole number: \(out.output)")
    guard case .dragBy(12, 3, 1, 10, 0)? = rig.channel.writes.first else {
        Issue.record("no drag by sent: \(rig.channel.writes)"); return
    }
}
