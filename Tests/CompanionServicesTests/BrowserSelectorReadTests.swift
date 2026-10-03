import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// A selector read that finds nothing used to come back as an empty page,
// which the model took as "the menu is empty". It now fails with a code whose copy says what to do.

private func selectorRig(failing code: String) -> (BrowserToolRunner, BrowserLeases) {
    let presence = BrowserPresence()
    presence.set(.comet)
    let channel = FakeBrowserChannel(failure: ContractError(code: code, message: "IGNORE THIS: extension wording"))
    let leases = BrowserLeases(epoch: presence.epoch)
    leases.acquire(tab: 12, caller: "chat")
    return (BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "chat"), leases)
}

@Test(arguments: ["selector_no_match", "selector_hidden"])
func anEmptySelectorReadReachesTheModelAsItsCopy(code: String) async {
    let (runner, leases) = selectorRig(failing: code)
    let out = await runner.execute(name: "browser_read", argumentsJSON: #"{"tab":12,"selector":"[role=menu]"}"#)
    expect(!out.ok, "\(code): a failure, not an empty page")
    expect(out.output.contains(BrowserCopy.failure(code: code, .en)) || out.output.contains(BrowserCopy.failure(code: code, .es)),
           "\(code): the model reads the copy: \(out.output)")
    expect(!out.output.contains("IGNORE THIS"), "\(code): the extension's wording never reaches the model")
    expectEq(leases.owner(of: 12), "chat", "\(code): the tab is still there, so the lease stays")
}
