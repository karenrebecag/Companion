import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// The runner writes the model's text itself; the extension's `after` only adds a fixed sentence to it.

private let menuOpened = BrowserAfter(navigated: false, urlChanged: false, opened: .menu, changed: true, fieldChars: nil)

@Test func aClickThatOpenedAMenuSaysSo() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.answerWrites(after: menuOpened)
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#, approve: true)
    expect(out.ok && out.output.contains("clicked [1]"), "the host's own words stay: \(out.output)")
    expect(out.output.contains("a menu opened"), "and what happened is added: \(out.output)")
}

@Test func aClickWithNoAfterReadsExactlyAsBefore() async {
    let rig = makeToolRig()
    await rig.read()
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#, approve: true)
    expectEq(out.output, "clicked [1]; read the tab again to see the result", "unchanged")
}

@Test func typingReportsTheFieldLengthAndKeepsTheLineBreakWarning() async {
    let rig = makeToolRig()
    await rig.read()
    let typed = BrowserAfter(navigated: false, urlChanged: false, opened: nil, changed: true, fieldChars: 8)
    rig.channel.answerWrites(with: BrowserCopy.typedWithoutLineBreaks, after: typed)
    let out = await rig.run("browser_type", #"{"tab":12,"element":5,"text":"Hola\nAna"}"#)
    expect(out.ok && out.output.contains("line breaks"), "exact-match done still recognised: \(out.output)")
    expect(out.output.contains("8 characters"), "and the length follows: \(out.output)")
    rig.channel.answerWrites(with: "typed", after: typed)
    let plain = await rig.run("browser_type", #"{"tab":12,"element":5,"text":"Ana"}"#)
    expect(plain.output.contains("typed into [5]") && plain.output.contains("8 characters"), "plain: \(plain.output)")
}

@Test func aNavigationStillRecognisesStillLoadingWithAnAfterAttached() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.answerWrites(with: BrowserCopy.stillLoading, after: quietAfter)
    let out = await rig.run("browser_navigate", #"{"tab":12,"url":"https://crm.example/x"}"#, approve: true)
    expect(out.output.contains("still loading"), "stillLoading by exact match: \(out.output)")
}

private let quietAfter = BrowserAfter(navigated: false, urlChanged: false, opened: nil, changed: false, fieldChars: nil)

@Test func aKeyPressAndAHoverCarryTheNoteToo() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.answerWrites(after: BrowserAfter(navigated: false, urlChanged: true, opened: nil, changed: true, fieldChars: nil))
    let pressed = await rig.run("browser_press", #"{"tab":12,"key":"Escape"}"#)
    expect(pressed.ok && pressed.output.contains("the address changed"), "press: \(pressed.output)")
    let hovered = await rig.run("browser_hover", #"{"tab":12,"element":1}"#)
    expect(hovered.ok && hovered.output.contains("the address changed"), "hover: \(hovered.output)")
}

@Test func aSelectAndAPointerToolCarryTheNoteToo() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.answerWrites(after: menuOpened)
    let double = await rig.run("browser_double_click", #"{"tab":12,"element":1}"#, approve: true)
    expect(double.output.contains("a menu opened"), "double click: \(double.output)")
    let at = await rig.run("browser_click_at", #"{"tab":12,"x":40,"y":60}"#, approve: true)
    expect(at.ok && at.output.contains("a menu opened"), "click at: \(at.output)")
}

@Test func theNoteFollowsTheUsersLanguage() async {
    let presence = BrowserPresence()
    presence.set(.comet)
    let channel = FakeBrowserChannel(pages: [crmPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crmPage().url, active: false)])
    let leases = BrowserLeases(epoch: presence.epoch)
    leases.acquire(tab: 12, caller: "chat")
    let runner = BrowserToolRunner(channel: channel, presence: presence, language: { .es }, leases: leases, caller: "chat")
    let rig = BrowserToolRig(runner: runner, channel: channel, presence: presence)
    await rig.read()
    channel.answerWrites(after: menuOpened)
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#, approve: true)
    expect(out.output.contains("se abrió un menú"), "es: \(out.output)")
}
