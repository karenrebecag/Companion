import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// 2026-10-05: a live click answered stale_id with no read in between. Like Incredible, the runner keeps the
// last reads of a tab, so an id the model saw in a recent read still resolves, bound to that read.

/// A narrow read (a finder) renumbers from 1 and lists far fewer elements than the full read before it.
private func finderPage(generation: Int) -> BrowserPage {
    BrowserPage(
        tab: 12, origin: crm, url: crm + "/a", title: "CRM", text: "Ayuda", generation: generation,
        elements: [webElement(1, "link", "Ayuda", href: crm + "/help")], truncated: false)
}

@Test func anIdOnlyInARecentReadStillActsBoundToThatRead() async {
    let rig = makeToolRig(page: crmPage(generation: 3))
    await rig.read()
    rig.channel.setPage(finderPage(generation: 4))
    await rig.read()
    let out = await rig.run("browser_click", #"{"tab":12,"element":7}"#, approve: true)
    expect(out.ok, "element 7 is only in the full read: \(out.output)")
    guard case .click(_, let generation, let element)? = rig.channel.writes.last else {
        Issue.record("no click sent"); return
    }
    expectEq(generation, 3, "sent with the generation of the read it came from")
    expectEq(element, 7, "and its own number")
}

@Test func anIdInTheLastReadAlwaysMeansTheLastRead() async {
    let rig = makeToolRig(page: crmPage(generation: 3))
    await rig.read()
    rig.channel.setPage(finderPage(generation: 4))
    await rig.read()
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#, said: "abre ayuda", approve: true)
    expect(out.ok, "element 1 of the last read: \(out.output)")
    guard case .click(_, let generation, _)? = rig.channel.writes.last else {
        Issue.record("no click sent"); return
    }
    expectEq(generation, 4, "the newest read wins where both have the number")
}

@Test func theApprovalBindsTheReadTheIdCameFrom() async {
    let rig = makeToolRig(page: crmPage(generation: 3))
    await rig.read()
    rig.channel.setPage(finderPage(generation: 4))
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    let request = rig.runner.approval(for: rig.call("browser_click", arguments), said: "guarda el registro")
    expect(request?.summary.contains("Eliminar") == true, "the sheet names the element of that read: \(request?.summary ?? "nil")")
    if let request { rig.runner.granted(request) }
    // A new read that also has no element 2 keeps the same binding; one that does have it takes the number over.
    rig.channel.setPage(BrowserPage(
        tab: 12, origin: crm, url: crm + "/a", title: "CRM", text: "", generation: 5,
        elements: [webElement(1, "button", "Otro"), webElement(2, "button", "Pagar")], truncated: false))
    await rig.read()
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "the yes was for Eliminar, not Pagar: \(out.output)")
    expect(rig.channel.writes.isEmpty, "nothing pressed")
}

@Test func onlyTheLastTwentyReadsAreKept() async {
    let rig = makeToolRig(page: crmPage(generation: 3))
    await rig.read()
    for generation in 4...23 {
        rig.channel.setPage(finderPage(generation: generation))
        await rig.read()
    }
    let out = await rig.run("browser_click", #"{"tab":12,"element":7}"#, approve: true)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "the 21st read back is gone: \(out.output)")
    expect(rig.channel.writes.isEmpty, "nothing sent")
}

@Test func aStaleAnswerStillForgetsEveryReadOfTheTab() async {
    let rig = makeToolRig(page: crmPage(generation: 3))
    await rig.read()
    rig.channel.setPage(finderPage(generation: 4))
    await rig.read()
    rig.channel.failWrites(with: ContractError(code: BridgeCode.staleId, message: "gone"))
    _ = await rig.run("browser_click", #"{"tab":12,"element":7}"#, approve: true)
    let again = await rig.run("browser_hover", #"{"tab":12,"element":7}"#)
    expect(!again.ok && again.output.contains(BridgeCode.staleId), "read again first: \(again.output)")
    expectEq(rig.channel.writes.count, 1, "the second call never reached the extension")
}

@Test func theTwentiethReadBackStillActsBoundToItsGeneration() async {
    let rig = makeToolRig(page: crmPage(generation: 3))
    await rig.read()
    for generation in 4...22 {
        rig.channel.setPage(finderPage(generation: generation))
        await rig.read()
    }
    let out = await rig.run("browser_click", #"{"tab":12,"element":7}"#, approve: true)
    expect(out.ok, "20 reads kept, the first among them: \(out.output)")
    guard case .click(_, let generation, let element)? = rig.channel.writes.last else {
        Issue.record("no click sent"); return
    }
    expectEq(generation, 3, "the generation of that first read")
    expectEq(element, 7, "its own number")
}

@Test func aReadThatArrivesLateNeverBecomesTheLatest() async {
    let rig = makeToolRig(page: crmPage(generation: 5))
    await rig.read()
    rig.channel.setPage(crmPage(generation: 4))
    await rig.read()
    expectEq(rig.runner.cachedPage(12)?.generation, 5, "generations only move forward")
    let out = await rig.run("browser_click_at", #"{"tab":12,"x":10,"y":10}"#, approve: true)
    expect(out.ok, "click_at on the newest read: \(out.output)")
    guard case .clickAt(_, let generation, _, _)? = rig.channel.writes.last else {
        Issue.record("no click_at sent"); return
    }
    expectEq(generation, 5, "bound to the newest read, not the one that arrived last")
}

@Test func aGrantedApprovalKeepsItsReadAfterANarrowerOne() async {
    let rig = makeToolRig(page: crmPage(generation: 3))
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    guard let request = rig.runner.approval(for: rig.call("browser_click", arguments), said: "guarda el registro") else {
        Issue.record("Eliminar not said asks"); return
    }
    rig.runner.granted(request)
    rig.channel.setPage(finderPage(generation: 5))
    await rig.read()
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(out.ok, "the yes still points at Eliminar of read 3: \(out.output)")
    expectEq(rig.channel.writes.last, .click(tab: 12, generation: 3, element: 2), "sent bound to that read")
}

@Test func aStaleDecidedByTheAppIsLoggedWithItsReason() async {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-stale-host-\(UUID().uuidString).log")
    await Log.capturing(to: url) {
        let rig = makeToolRig()
        _ = await rig.run("browser_click", #"{"tab":12,"element":1}"#)
    }
    let log = Log.tail(lines: 20, from: url).joined(separator: "\n")
    expect(log.contains("tool=browser_click code=stale_id reason=host_cache_miss"), "no read kept: \(log)")
}

@Test func theExtensionsStaleReasonIsTheEndOfTheChannelLogLine() {
    let line = BrowserChannel.logLine(
        .click(tab: 12, generation: 3, element: 1),
        .failure(ContractError(code: BridgeCode.staleId, message: "gone")), reason: "element_gone")
    expect(line.hasSuffix("code=stale_id reason=element_gone"), line)
    let plain = BrowserChannel.logLine(.click(tab: 12, generation: 3, element: 1), .success(.done(id: 1, message: "ok")), reason: nil)
    expectEq(plain, "tool=browser_click code=ok", "no reason, nothing added")
}
