import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Only a valid, confident relationship verdict counts, and the question
// carries the goal and the shape of the progress, never step summaries.

@Test func relationshipHeadReadsOnlyAConfidentValidVerdict() {
    let objective = PendingObjective(
        goal: "refactoriza la capa de red", jobID: nil, stepsDone: 3, currentTool: "run_shell",
        goalFromUser: true)
    let asked = RelationshipHead.question("olvidalo", about: objective)
    expectEq(asked.offeredIds, Relationship.allCases.map(\.rawValue), "relationship: six options")
    expect(asked.instructions.contains("refactoriza la capa de red"), "relationship: the goal is the state")
    expect(asked.instructions.contains("3 steps done, now using run_shell"), "relationship: progress shape only")

    func verdict(_ choice: Relationship, peak: Double) -> DecisionAnswer {
        let ids = asked.offeredIds
        let rest = (1 - peak) / Double(ids.count - 1)
        var distribution = Dictionary(uniqueKeysWithValues: ids.map { ($0, rest) })
        distribution[choice.rawValue] = peak
        return DecisionAnswer(choice: choice.rawValue, distribution: distribution, confidence: 0.99)
    }
    expectEq(RelationshipHead.read(verdict(.cancel, peak: 0.95)), .cancel, "relationship: sure cancel")
    expect(RelationshipHead.read(verdict(.cancel, peak: 0.5)) == nil, "relationship: unsure leaves the job alone")
    expect(RelationshipHead.read(nil) == nil, "relationship: no verdict leaves the job alone")
}

/// A goal the brain wrote may carry page or file content: only a generic
/// name goes out for it, and only a goal said in the hold counts as hers.
@Test func relationshipHeadSendsOnlyTheUsersOwnGoal() {
    expect(PendingObjective.isUsersOwn("crea un archivo", heard: "porfa Crea un archivo"),
           "own: said in the hold")
    expect(!PendingObjective.isUsersOwn("Resumir el informe Q3: ingresos 4,2M", heard: "resume esto"),
           "own: brain-written goal is not hers")
    expect(!PendingObjective.isUsersOwn("crea un archivo", heard: nil), "own: nothing heard")
    let brainGoal = PendingObjective(
        goal: "Resumir el informe Q3: ingresos 4,2M", jobID: nil, stepsDone: 2, goalFromUser: false)
    let asked = RelationshipHead.question("olvidalo", about: brainGoal)
    expect(!asked.instructions.contains("Q3"), "brain goal: its text never leaves")
    expect(asked.instructions.contains("a background task") && asked.instructions.contains("2 steps done"),
           "brain goal: a generic name and the step count")
}
