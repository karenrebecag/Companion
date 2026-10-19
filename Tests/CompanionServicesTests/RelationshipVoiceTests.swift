import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// The relationship head over the hold, after the security review of #366:
// it stops only the job it judged, only while that job still runs, asks a
// real question when unsure, and never judges a yes/no to an open question.

@Test @MainActor func relationshipVoiceTests() async {
    await testAStopEndsOnlyTheJudgedJob()
    await testAJobThatEndsDuringTheVerdictIsNeitherStoppedNorAnnounced()
    await testAnUnclearVerdictAsksAndAYesStopsOnlyThatJob()
    await testAYesToAnOpenQuestionNeverReachesTheRelationshipHead()
}

/// A judge whose relationship answers may wait, so a test can move the job
/// while the verdict is out.
private final class AsyncHosted: HostedDecisionProviding, @unchecked Sendable {
    let isConfigured = true
    private let body: @Sendable (DecisionQuestion) async -> DecisionAnswer?
    init(_ body: @escaping @Sendable (DecisionQuestion) async -> DecisionAnswer?) { self.body = body }
    func answer(_ question: DecisionQuestion) async -> DecisionAnswer? { await body(question) }
}

private final class VerdictFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _on = false
    var on: Bool { lock.withLock { _on } }
    func set() { lock.withLock { _on = true } }
}

/// Jobs for whole utterances, the trash for "vacia la papelera", nothing
/// for the other words; the relationship head answers through `relation`.
@MainActor private func relationHarness(
    relation: @escaping @Sendable (DecisionQuestion) async -> DecisionAnswer?
) async -> (VoiceHarness, KeyedJobs, RecordingSystemActing) {
    unsetenv("COMPANION_DECISION")
    let tasks = taskProvider()
    let trash = trashProvider()
    let hosted = AsyncHosted { question in
        if question.id == RelationshipHead.id { return await relation(question) }
        if question.instructions.contains("vacia la papelera") { return trash.body(question) }
        if question.instructions.contains("crea") { return tasks.body(question) }
        return question.id == DecisionHead.action ? peaked("none", question.offeredIds) : nil
    }
    let judge = DecisionJudge(hosted: hosted, local: ScriptedDecision { _ in nil })
    let system = RecordingSystemActing()
    let gate = DecisionGate(
        provider: judge, arbiter: NoArbiter(), tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    let jobs = KeyedJobs()
    let h = makeVoiceHarness(jobs: jobs, language: .es)
    await h.session.attachDecision(gate, judge: judge)
    return (h, jobs, system)
}

@MainActor private func say(_ words: String, to h: VoiceHarness) async {
    h.transcriber.stoppedText = words
    await h.session.hold()
    await pumpUntilAsync("say: armed for \(words)") { await h.session.holdOpen }
    await h.session.release()
    await h.session.awaitClassicTurn()
}

@MainActor private func runningJob(_ goal: String, on h: VoiceHarness) async -> JobID? {
    await pumpUntilAsync("job: \(goal) runs") { await h.session.runningObjective?.goal == goal }
    return await h.session.runningObjective?.jobID
}

/// HIGH: "olvídalo" used to stop every queued job while saying it stopped one.
@MainActor func testAStopEndsOnlyTheJudgedJob() async {
    let asked = CallCounter()
    let (h, jobs, _) = await relationHarness { question in
        asked.increment()
        return peaked(asked.count == 1 ? "append" : "cancel", question.offeredIds)
    }
    await say("crea un archivo", to: h)
    let first = await runningJob("crea un archivo", on: h)
    await say("crea otro archivo", to: h)
    let second = await runningJob("crea otro archivo", on: h)
    await say("olvidalo", to: h)
    await pumpUntil("only: stopped") { !jobs.stopped.isEmpty }
    expectEq(jobs.stopped, [second].compactMap { $0 }, "only: the judged job is stopped")
    expectEq(jobs.stoppedAll, 0, "only: nothing else is stopped")
    expect(first.map { jobs.live.contains($0) } == true, "only: the other job keeps running")
    expect(h.synth.queue.contains("Paré «crea otro archivo»."), "only: says which one")
}

/// MEDIUM: the verdict comes back after the job already ended; there is
/// nothing to stop and nothing to announce.
@MainActor func testAJobThatEndsDuringTheVerdictIsNeitherStoppedNorAnnounced() async {
    let out = VerdictFlag()
    let release = VerdictFlag()
    let (h, jobs, _) = await relationHarness { question in
        out.set()
        for _ in 0 ..< 400 where !release.on { try? await Task.sleep(for: .milliseconds(1)) }
        return peaked("cancel", question.offeredIds)
    }
    await say("crea un archivo", to: h)
    guard let id = await runningJob("crea un archivo", on: h) else { return }
    h.transcriber.stoppedText = "olvidalo"
    await h.session.hold()
    await pumpUntilAsync("ended: armed") { await h.session.holdOpen }
    await h.session.release()
    await pumpUntil("ended: verdict out") { out.on }
    jobs.finish(id)
    await pumpUntilAsync("ended: job over") { await h.session.runningObjective == nil }
    release.set()
    await h.session.awaitClassicTurn()
    expect(jobs.stopped.isEmpty && jobs.stoppedAll == 0, "ended: nothing is stopped")
    expect(!h.synth.queue.contains("Paré «crea un archivo»."), "ended: nothing is announced")
}

/// MEDIUM: an unsure verdict asks a real question; the next "sí" answers it
/// and stops that job only.
@MainActor func testAnUnclearVerdictAsksAndAYesStopsOnlyThatJob() async {
    let asked = CallCounter()
    let (h, jobs, _) = await relationHarness { question in
        asked.increment()
        return peaked("unclear", question.offeredIds)
    }
    await say("crea un archivo", to: h)
    guard let id = await runningJob("crea un archivo", on: h) else { return }
    await say("ya no", to: h)
    expect(h.synth.queue.contains("¿Paro lo que estoy haciendo o sigo?"), "unclear: asks")
    let before = asked.count
    await say("si", to: h)
    await pumpUntil("unclear: stopped") { !jobs.stopped.isEmpty }
    expectEq(jobs.stopped, [id], "unclear: the yes stops that job")
    expectEq(jobs.stoppedAll, 0, "unclear: and nothing else")
    expectEq(asked.count, before, "unclear: the yes is not judged again")
}

@MainActor func testAYesToAnOpenQuestionNeverReachesTheRelationshipHead() async {
    let said = TextBox()
    let (h, _, system) = await relationHarness { question in
        said.append(question.instructions)
        return peaked("append", question.offeredIds)
    }
    await say("crea un archivo", to: h)
    _ = await runningJob("crea un archivo", on: h)
    await say("vacia la papelera", to: h)
    await say("si", to: h)
    await pumpUntil("open: emptied") { system.actCount == 1 }
    expect(!said.all.contains { $0.contains("\"si\"") }, "open: the yes is never sent about the job")
}
