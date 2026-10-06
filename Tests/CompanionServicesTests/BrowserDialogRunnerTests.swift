import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// A dialog the page opened is reported by the host in its own wording, next to the output of the next
// action or read, and never through the extension's done text, which the host matches exactly.

private let report = BrowserDialogReport(
    dialogs: [BrowserDialog(kind: .confirm, answer: .no, destructive: true, message: "Delete this account?")], more: 0)

@Test func anActionAfterADialogSaysWhatHappenedInTheHostsWords() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.answerWrites(with: "clicked", dialogs: report)
    let out = await rig.run("browser_type", #"{"tab":12,"element":5,"text":"Ana"}"#)
    expect(out.ok, "the action itself worked: \(out.output)")
    expect(out.output.contains("typed into [5]"), "its own text first: \(out.output)")
    expect(out.output.contains(#"(page content): "Delete this account?""#), "the page's words, quoted: \(out.output)")
    expect(out.output.contains("ask the person"), "and the next step: \(out.output)")
}

@Test func anActionWithoutADialogAddsNothing() async {
    let rig = makeToolRig()
    await rig.read()
    let out = await rig.run("browser_type", #"{"tab":12,"element":5,"text":"Ana"}"#)
    expect(!out.output.contains("dialog"), "nothing extra: \(out.output)")
}

@Test func theExactDoneChecksStillWorkWhenADialogIsPresent() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.answerWrites(with: BrowserCopy.typedWithoutLineBreaks, dialogs: report)
    let typed = await rig.run("browser_type", #"{"tab":12,"element":5,"text":"Hola\nAna"}"#)
    expect(typed.output.contains("without its line breaks"), "line breaks still reported: \(typed.output)")
    expect(typed.output.contains("confirm dialog"), "and the dialog: \(typed.output)")

    let nav = makeToolRig()
    await nav.read()
    nav.channel.answerWrites(with: BrowserCopy.stillLoading, dialogs: report)
    nav.channel.stillLoading()
    let out = await nav.run("browser_navigate", #"{"tab":12,"url":"https://crm.example/reports"}"#)
    expect(out.output.contains("still loading"), "still loading still recognised: \(out.output)")
}

@Test func aNavigationTheLoadedPageRefusedSaysThePageStayed() async {
    let rig = makeToolRig()
    await rig.read()
    rig.channel.answerWrites(with: BrowserCopy.stayedOnPage)
    rig.channel.stillLoading()
    rig.channel.answerNavigate(with: BrowserCopy.stayedOnPage)
    let out = await rig.run("browser_navigate", #"{"tab":12,"url":"https://crm.example/reports"}"#)
    expect(out.output.contains("did not leave"), "says it stayed: \(out.output)")
    expect(!out.output.contains("still loading") && !out.output.contains("it loaded"), "neither of the others: \(out.output)")
}

@Test func aReadCarriesTheDialogOutsideThePageText() async {
    var page = crmPage(text: "Hola")
    page.dialogs = report
    let rig = makeToolRig(page: page)
    let out = await rig.runner.execute(name: "browser_read", argumentsJSON: #"{"tab":12}"#)
    expect(out.output.contains("Hola"), "the page is there: \(out.output)")
    expect(out.output.contains(#"(page content): "Delete this account?""#), "and the dialog: \(out.output)")
    let clean = crmPage(text: "Hola")
    let none = await makeToolRig(page: clean).runner.execute(name: "browser_read", argumentsJSON: #"{"tab":12}"#)
    expect(!none.output.contains("dialog"), "no dialog, no note: \(none.output)")
}

@Test func aReadWithAnEmptyPageStillShowsTheDialog() async {
    var page = crmPage(text: "")
    page.dialogs = report
    let out = await makeToolRig(page: page).runner.execute(name: "browser_read", argumentsJSON: #"{"tab":12}"#)
    expect(out.output.contains("Delete this account?"), "shown: \(out.output)")
}
