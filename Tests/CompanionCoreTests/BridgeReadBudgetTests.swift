import CompanionCore
import CompanionTestKit
import Foundation
import Testing

/// 20c D6 (M8b): reads (`look`, `see`, `read_focused`...) have their own
/// per-minute budget, apart from the action one. Before this reads were
/// unbounded, so a peer could hammer the screen capture and the vision model
/// for as long as it held the session; and the two must not share an
/// allowance, or either flood would starve the other.

private func openPolicy(_ now: Date) -> BridgePolicy {
    var policy = BridgePolicy()
    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)
    policy.approved(until: nil, now: now)
    return policy
}

private func rejectionCode(_ verdict: BridgeVerdict) -> String? {
    if case .reject(let code) = verdict { return code }
    return nil
}

@Test func readsHaveTheirOwnBudgetAndItRefusesWhenSpent() {
    let now = Date()
    var policy = openPolicy(now)
    for i in 0 ..< BridgePolicy.readBudgetPerMinute {
        expectEq(policy.admit(tool: "look", now: now), .proceed, "read \(i) is inside the budget")
    }
    expectEq(rejectionCode(policy.admit(tool: "see", now: now)), BridgeCode.rateLimited,
             "the next read (a different read tool) is rate limited")
    expectEq(policy.admit(tool: "look", now: now.addingTimeInterval(BridgePolicy.window + 1)), .proceed,
             "the read window slides")
}

@Test func aReadFloodCannotStarveActionsAndAnActionFloodCannotStarveReads() {
    let now = Date()
    var reads = openPolicy(now)
    for _ in 0 ..< BridgePolicy.readBudgetPerMinute { _ = reads.admit(tool: "look", now: now) }
    expectEq(reads.admit(tool: "click", now: now), .proceed, "actions still run with the read budget spent")

    var actions = openPolicy(now)
    for _ in 0 ..< BridgePolicy.budgetPerMinute { _ = actions.admit(tool: "click", now: now) }
    expectEq(rejectionCode(actions.admit(tool: "click", now: now)), BridgeCode.rateLimited,
             "the action budget still refuses when spent")
    for tool in ["look", "see", "read_focused", "list_apps"] {
        expectEq(actions.admit(tool: tool, now: now), .proceed, "\(tool) runs with the action budget spent")
    }
}

@Test func theReadBudgetIsPerProcessNotPerConnection() {
    let now = Date()
    var policy = openPolicy(now)
    for _ in 0 ..< BridgePolicy.readBudgetPerMinute { _ = policy.admit(tool: "look", now: now) }
    policy.disconnected()
    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)
    policy.approved(until: nil, now: now)
    expectEq(rejectionCode(policy.admit(tool: "look", now: now)), BridgeCode.rateLimited,
             "reconnecting does not launder the read budget")
}

/// Review D6 (code MEDIUM): a tool put on the allowlist but forgotten in
/// `writeTools` used to fall silently into the read budget. Every allowlisted
/// tool must sit in exactly one explicit bucket, so adding one forces the
/// decision.
@Test func everyAllowlistedBridgeToolIsInExactlyOneBudgetBucket() {
    expect(BridgePolicy.unbucketed(BridgeScope.bridgeTools).isEmpty,
           "allowlisted tools with no budget bucket: \(BridgePolicy.unbucketed(BridgeScope.bridgeTools).sorted())")
    let both = BridgePolicy.writeTools.intersection(BridgePolicy.readTools)
    expect(both.isEmpty, "a tool draws from one budget, not both: \(both.sorted())")
    expect(BridgeScope.bridgeTools.isSuperset(of: BridgePolicy.writeTools.union(BridgePolicy.readTools)),
           "a bucket names only allowlisted tools")
}

@Test func aToolInNeitherBucketFailsTheGuardAndDrawsFromTheStricterBudget() {
    expectEq(BridgePolicy.unbucketed(BridgeScope.bridgeTools.union(["brand_new_tool"])), ["brand_new_tool"],
             "a tool allowlisted but in neither bucket is reported")
    let now = Date()
    var policy = openPolicy(now)
    for i in 0 ..< BridgePolicy.budgetPerMinute {
        expectEq(policy.admit(tool: "brand_new_tool", now: now), .proceed, "call \(i) inside the action budget")
    }
    expectEq(rejectionCode(policy.admit(tool: "brand_new_tool", now: now)), BridgeCode.rateLimited,
             "an unbucketed tool is held to the action budget, not the looser read one")
}
