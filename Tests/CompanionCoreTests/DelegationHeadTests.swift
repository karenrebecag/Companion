import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The delegation head can only withdraw `delegate`, and only on a confident,
// valid "answer" or "own_tool". Every other reply keeps the tool offered.

@Test func delegationHeadWithdrawsOnlyOnAConfidentSelfHandledVerdict() {
    let ids = DelegationHead.question("hola").offeredIds
    expectEq(ids, ["answer", "own_tool", "delegate", "ask"], "head: four typed options")

    func verdict(_ choice: String, peak: Double) -> DecisionAnswer {
        let rest = (1 - peak) / Double(ids.count - 1)
        var distribution = Dictionary(uniqueKeysWithValues: ids.map { ($0, rest) })
        distribution[choice] = peak
        return DecisionAnswer(choice: choice, distribution: distribution, confidence: 0.99)
    }
    expect(!DelegationHead.offersDelegate(verdict("answer", peak: 0.97)), "answer, sure: withdrawn")
    expect(!DelegationHead.offersDelegate(verdict("own_tool", peak: 0.97)), "own tool, sure: withdrawn")
    expect(DelegationHead.offersDelegate(verdict("answer", peak: 0.6)),
           "answer, unsure: the mass caps the claimed 0.99, kept")
    expect(DelegationHead.offersDelegate(verdict("delegate", peak: 0.97)), "delegate: kept")
    expect(DelegationHead.offersDelegate(verdict("ask", peak: 0.97)), "ask: kept, never forced")
    expect(DelegationHead.offersDelegate(nil), "no verdict: kept")
    let invented = DecisionAnswer(choice: "answer", distribution: ["answer": 1], confidence: 1)
    expect(DelegationHead.offersDelegate(invented), "invalid distribution: kept")
}
