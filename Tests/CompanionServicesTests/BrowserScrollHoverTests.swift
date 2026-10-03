import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// H-7 P5b: browser_scroll and browser_hover (Incredible's tab.scroll(dx, dy)
// and el.hover()). Neither changes what the page holds, so neither asks; both
// still need control of the tab, and an element they name must come from the
// tab's last read.

@Test func scrollAndHoverAreOfferedWithTheirArguments() {
    let rig = makeToolRig()
    for language in [AppLanguage.en, .es] {
        let specs = rig.runner.specs(language)
        guard let hover = specs.first(where: { $0.name == "browser_hover" }),
              let scroll = specs.first(where: { $0.name == "browser_scroll" })
        else { Issue.record("missing in \(language)"); continue }
        expectEq(hover.required, ["tab", "element"], "hover: an element of the last read")
        expectEq(scroll.required, ["tab"], "scroll: by an offset or to an element, neither required alone")
        expectEq(Set(scroll.properties.map(\.name)), ["tab", "dx", "dy", "element"], "scroll's arguments")
        for property in scroll.properties {
            expect(property.description != property.name, "\(property.name) \(language): described")
        }
    }
}

@Test func hoverNeverAsksAndGoesOutWithTheReadsGeneration() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    expect(rig.runner.approval(for: rig.call("browser_hover", arguments), said: "") == nil,
           "hovering over Eliminar deletes nothing: no sheet")
    let out = await rig.runner.execute(name: "browser_hover", argumentsJSON: arguments)
    expect(out.ok && out.output.hasPrefix("hovered over [2]"), "runs without a ticket: \(out.output)")
    guard case .hover(12, 3, 2)? = rig.channel.writes.first else {
        Issue.record("no hover sent: \(rig.channel.writes)"); return
    }
}

@Test func scrollByAnOffsetNeedsNoReadAndNoSheet() async {
    let rig = makeToolRig()
    let arguments = #"{"tab":12,"dy":600}"#
    expect(rig.runner.approval(for: rig.call("browser_scroll", arguments), said: "") == nil, "no sheet")
    let out = await rig.runner.execute(name: "browser_scroll", argumentsJSON: arguments)
    expect(out.ok && out.output.contains("read the tab again"), "scrolled: \(out.output)")
    guard case .scroll(12, 0, 600)? = rig.channel.writes.first else {
        Issue.record("no scroll sent: \(rig.channel.writes)"); return
    }
}

@Test func scrollToAnElementBringsTheReadsElementIntoView() async {
    let rig = makeToolRig()
    await rig.read()
    let out = await rig.runner.execute(name: "browser_scroll", argumentsJSON: #"{"tab":12,"element":5}"#)
    expect(out.ok, "scrolled to it: \(out.output)")
    guard case .scrollTo(12, 3, 5)? = rig.channel.writes.first else {
        Issue.record("no scroll to element sent: \(rig.channel.writes)"); return
    }
}

@Test func aScrollThatSaysNothingOrTooMuchIsRefused() async {
    let rig = makeToolRig()
    await rig.read()
    for arguments in [
        #"{"tab":12}"#,
        #"{"tab":12,"dx":0,"dy":0}"#,
        #"{"tab":12,"dy":200,"element":5}"#,
        #"{"tab":12,"dy":20001}"#,
        #"{"tab":12,"dx":-20001}"#,
        #"{"tab":12,"dy":"lots"}"#,
    ] {
        let out = await rig.runner.execute(name: "browser_scroll", argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "\(arguments): refused, \(out.output)")
    }
    expect(rig.channel.writes.isEmpty, "nothing scrolled")
}

@Test func anOffsetAtTheEdgesOfIntIsRefusedNotTrapped() async {
    let rig = makeToolRig()
    for arguments in [
        #"{"tab":12,"dy":-9223372036854775808}"#,
        #"{"tab":12,"dx":"-9223372036854775808"}"#,
        #"{"tab":12,"dy":9223372036854775807}"#,
    ] {
        let out = await rig.runner.execute(name: "browser_scroll", argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "\(arguments): refused, never a crash")
    }
    expect(rig.channel.writes.isEmpty, "nothing scrolled")
}

@Test func theScrollLimitIsReachedButNotPassed() async {
    let rig = makeToolRig()
    let out = await rig.runner.execute(
        name: "browser_scroll", argumentsJSON: #"{"tab":12,"dx":-\#(BrowserTool.scrollLimit),"dy":\#(BrowserTool.scrollLimit)}"#)
    expect(out.ok, "the limit itself is allowed: \(out.output)")
    expectEq(BrowserTool.scrollLimit, 20_000, "a few screens at most per call")
}

@Test func anElementFromNoReadIsStaleForBoth() async {
    let rig = makeToolRig()
    for (name, arguments) in [("browser_hover", #"{"tab":12,"element":1}"#), ("browser_scroll", #"{"tab":12,"element":1}"#)] {
        let out = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.staleId), "\(name): read first, \(out.output)")
    }
    await rig.read()
    let unknown = await rig.runner.execute(name: "browser_hover", argumentsJSON: #"{"tab":12,"element":99}"#)
    expect(!unknown.ok && unknown.output.contains(BridgeCode.staleId), "an id the read never gave")
    expect(rig.channel.writes.isEmpty, "nothing sent")
}

@Test func scrollAndHoverNeedControlOfTheTab() async {
    let rig = makeToolRig(owned: false)
    for (name, arguments) in [("browser_hover", #"{"tab":12,"element":1}"#), ("browser_scroll", #"{"tab":12,"dy":300}"#)] {
        let out = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.notControlled), "\(name): not this caller's tab")
    }
    expect(rig.channel.writes.isEmpty, "nothing sent")
}

@Test func anElementOnATabThatLeftItsOriginIsNotTouched() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.setTabs([BrowserTab(id: 12, title: "Phish", url: "https://evil.example/", active: true)])
    for (name, arguments) in [("browser_hover", #"{"tab":12,"element":1}"#), ("browser_scroll", #"{"tab":12,"element":1}"#)] {
        let out = await rig.runner.execute(name: name, argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.staleId), "\(name): another page now")
    }
    expect(rig.channel.writes.isEmpty, "nothing sent")
}

@Test func anElementTheExtensionCallsStaleIsForgotten() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.failWrites(with: ContractError(code: BridgeCode.staleId, message: "element is gone"))
    let out = await rig.runner.execute(name: "browser_hover", argumentsJSON: #"{"tab":12,"element":2}"#)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "the extension's stale reaches the model")
    let again = await rig.runner.execute(name: "browser_scroll", argumentsJSON: #"{"tab":12,"element":2}"#)
    expect(!again.ok && again.output.contains(BridgeCode.staleId), "the read was forgotten: read again first")
    expectEq(rig.channel.writes.count, 1, "the second call never reached the extension")
}

@Test func aScrollElementThatIsNotANumberIsRefused() async {
    let rig = makeToolRig()
    await rig.read()
    for arguments in [#"{"tab":12,"element":"five"}"#, #"{"tab":12,"element":1.5}"#] {
        let out = await rig.runner.execute(name: "browser_scroll", argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "\(arguments): refused")
    }
    expect(rig.channel.writes.isEmpty, "nothing sent")
}

@Test func scrollAndHoverAreBridgeWritesInBothScopes() {
    for name in ["browser_scroll", "browser_hover"] {
        expect(BridgePolicy.writeTools.contains(name), "\(name): counted against the write budget")
        expect(BridgeScope.bridgeTools.contains(name), "\(name): offered over the bridge")
    }
}
