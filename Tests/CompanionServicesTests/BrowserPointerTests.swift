import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// H-7 P5a: browser_double_click and browser_right_click (Incredible's
// el.double_click() and el.right_click()). They press the same element a
// click would, so they pass the same gates: what a click on that element
// would ask, these ask too.

@Test func theTwoPointerToolsAreOfferedWithATabAndAnElement() {
    let rig = makeToolRig()
    for name in ["browser_double_click", "browser_right_click"] {
        for language in [AppLanguage.en, .es] {
            guard let spec = rig.runner.specs(language).first(where: { $0.name == name }) else {
                Issue.record("\(name) missing in \(language)"); continue
            }
            expectEq(spec.required, ["tab", "element"], "\(name): tab and element, like a click")
            expect(!spec.description.isEmpty, "\(name) \(language): described")
        }
    }
    expect(BrowserTool.doubleClick.isWrite && BrowserTool.rightClick.isWrite, "both write to the page")
}

@Test func aDoubleClickOnEliminarNotSaidAsksAndADenialSendsNothing() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    let request = rig.runner.approval(for: rig.call("browser_double_click", arguments), said: "guarda el registro")
    expect(request != nil, "a destructive label asks, as a click on it would")
    expectEq(request?.summary, "double-click Eliminar in \(crm)", "the sheet names the gesture")
    let out = await rig.runner.execute(name: "browser_double_click", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "no ticket, no press")
    expect(rig.channel.writes.isEmpty, "the extension hears nothing")
}

@Test func anApprovedDoubleClickGoesOutWithTheReadsGeneration() async {
    let rig = makeToolRig()
    await rig.read()
    let out = await rig.run("browser_double_click", #"{"tab":12,"element":2}"#, approve: true)
    expect(out.ok, "approved: it runs")
    expect(out.output.hasPrefix("double-clicked [2]"), "says what it did: \(out.output)")
    guard case .doubleClick(let tab, let generation, let element)? = rig.channel.writes.first else {
        Issue.record("no double click sent"); return
    }
    expectEq([tab, generation, element], [12, 3, 2], "tab, generation and element of the read")
    expectEq(rig.channel.sent.last?.timeout, .seconds(15), "the click's timeout")
}

@Test func aHarmlessRightClickActsWithoutASheet() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":1}"#
    expect(rig.runner.approval(for: rig.call("browser_right_click", arguments), said: "") == nil, "Guardar: no sheet")
    let out = await rig.runner.execute(name: "browser_right_click", argumentsJSON: arguments)
    expect(out.ok && out.output.hasPrefix("right-clicked [1]"), "runs: \(out.output)")
    guard case .rightClick(12, 3, 1)? = rig.channel.writes.first else {
        Issue.record("no right click sent"); return
    }
}

@Test func aRightClickAsksWhereAClickWould() async {
    let rig = makeToolRig()
    await rig.read()
    let request = rig.runner.approval(for: rig.call("browser_right_click", #"{"tab":12,"element":2}"#), said: "")
    expectEq(request?.summary, "right-click Eliminar in \(crm)", "a destructive label asks")
    expect(rig.runner.approval(for: rig.call("browser_right_click", #"{"tab":12,"element":3}"#), said: "") != nil,
           "a link to another origin asks")
    expect(rig.runner.approval(for: rig.call("browser_double_click", #"{"tab":12,"element":6}"#), said: "") != nil,
           "a frame of another origin asks")
}

@Test func aClicksApprovalDoesNotCoverADoubleClick() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    if let request = rig.runner.approval(for: rig.call("browser_click", arguments), said: "") { rig.runner.granted(request) }
    let out = await rig.runner.execute(name: "browser_double_click", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "the yes was for one click, not two")
    expect(rig.channel.writes.isEmpty, "nothing pressed")
}

@Test func aRightClicksApprovalDoesNotCoverADoubleClick() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    if let request = rig.runner.approval(for: rig.call("browser_right_click", arguments), said: "") {
        rig.runner.granted(request)
    }
    let out = await rig.runner.execute(name: "browser_double_click", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "each gesture is approved on its own")
    expect(rig.channel.writes.isEmpty, "nothing pressed")
}

@Test func aPointerToolNeedsControlOfTheTab() async {
    let rig = makeToolRig(owned: false)
    for name in ["browser_double_click", "browser_right_click"] {
        let out = await rig.run(name, #"{"tab":12,"element":1}"#, approve: true)
        expect(!out.ok && out.output.contains(BridgeCode.notControlled), "\(name): not this caller's tab")
    }
    expect(rig.channel.writes.isEmpty, "nothing pressed")
}

@Test func aPointerToolOnAnUnreadElementIsStale() async {
    let rig = makeToolRig()
    let out = await rig.run("browser_right_click", #"{"tab":12,"element":1}"#, approve: true)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "no read yet: read first")
    expect(rig.channel.writes.isEmpty, "nothing pressed")
}

@Test func thePointerToolsAreBridgeWritesInBothScopes() {
    for name in ["browser_double_click", "browser_right_click"] {
        expect(BridgePolicy.writeTools.contains(name), "\(name): a write for the bridge's budget")
        expect(BridgeScope.bridgeTools.contains(name), "\(name): offered over the bridge")
    }
}
