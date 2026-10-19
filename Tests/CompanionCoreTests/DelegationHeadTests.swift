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
    expect(!DelegationHead.offersDelegate(utterance: "hola", verdict("answer", peak: 0.97)), "answer, sure: withdrawn")
    expect(!DelegationHead.offersDelegate(utterance: "hola", verdict("own_tool", peak: 0.97)), "own tool, sure: withdrawn")
    expect(DelegationHead.offersDelegate(utterance: "hola", verdict("answer", peak: 0.6)),
           "answer, unsure: the mass caps the claimed 0.99, kept")
    expect(DelegationHead.offersDelegate(utterance: "hola", verdict("delegate", peak: 0.97)), "delegate: kept")
    expect(DelegationHead.offersDelegate(utterance: "hola", verdict("ask", peak: 0.97)), "ask: kept, never forced")
    expect(DelegationHead.offersDelegate(utterance: "hola", nil), "no verdict: kept")
    let invented = DecisionAnswer(choice: "answer", distribution: ["answer": 1], confidence: 1)
    expect(DelegationHead.offersDelegate(utterance: "hola", invented), "invalid distribution: kept")
}

/// M2: when the words themselves ask for a background or specialist job, no
/// verdict takes the hand-off away.
@Test func delegationHeadNeverWithdrawsAnExplicitHandOff() {
    let ids = DelegationHead.question("x").offeredIds
    var distribution = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0.01) })
    distribution["answer"] = 0.97
    let sure = DecisionAnswer(choice: "answer", distribution: distribution, confidence: 0.99)
    for said in [
        "resume este repo en segundo plano", "encárgate de ordenar mis descargas",
        "hazlo con Claude", "pásaselo al especialista", "delega la migracion",
        "do it in the background", "have Claude Code fix it", "hand this off",
    ] {
        expect(DelegationHead.asksToDelegate(said), "explicit: \(said)")
        expect(DelegationHead.offersDelegate(utterance: said, sure), "kept: \(said)")
    }
    for said in ["que hora es en tokio", "abre Safari", "explain claude shannon's theorem"] {
        expect(!DelegationHead.asksToDelegate(said), "not explicit: \(said)")
    }
}
