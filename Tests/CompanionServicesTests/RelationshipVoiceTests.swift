import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// The relationship head over the hold, as Incredible (Karen, 2026-10-19):
// a sure stop acts at once on that job only; anything less goes to the
// brain, which sees the running job and can stop it with `stop_job`. The
// voice's own brake never touches a job.

@Test @MainActor func relationshipVoiceTests() async {
    await testAStopEndsOnlyTheJudgedJob()
    await testAJobThatEndsDuringTheVerdictIsNeitherStoppedNorAnnounced()
    await testAnUnsureVerdictGoesToTheBrainWithTheJobInView()
    await testTheBrainsStopEndsOnlyTheJobItNames()
    await testTheVoiceBrakeLeavesTheJobsRunning()
    await testAnAdditionStartsAnotherJobAndStopsNone()
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
    expect(!h.synth.queue.contains { $0.contains("¿") }, "only: and asks nothing")
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

/// Not sure enough to act: no question; the brain gets the turn with the
/// job listed and `stop_job` offered, and nothing is stopped on its own.
@MainActor func testAnUnsureVerdictGoesToTheBrainWithTheJobInView() async {
    let (h, jobs, _) = await relationHarness { peaked("unclear", $0.offeredIds) }
    await say("crea un archivo", to: h)
    guard let id = await runningJob("crea un archivo", on: h) else { return }
    await say("ya no", to: h)
    expect(!h.synth.queue.contains { $0.contains("¿") }, "unsure: asks nothing")
    expect(h.chat.toolsSeen.contains { $0.name == "stop_job" }, "unsure: the brain can stop it")
    expect(h.chat.histories.last?.last?.content.contains(id.raw) == true, "unsure: the brain sees the job")
    expect(jobs.stopped.isEmpty && jobs.stoppedAll == 0, "unsure: nothing is stopped on its own")
}

@MainActor func testTheBrainsStopEndsOnlyTheJobItNames() async {
    let (h, jobs, _) = await relationHarness { peaked("append", $0.offeredIds) }
    await say("crea un archivo", to: h)
    let first = await runningJob("crea un archivo", on: h)
    await say("crea otro archivo", to: h)
    guard let second = await runningJob("crea otro archivo", on: h) else { return }
    h.chat.rounds = [
        [.toolCalls([ToolCallRef(id: "c1", name: "stop_job", arguments: #"{"job_id":"\#(second.raw)"}"#)])],
        [.text("Listo.")],
    ]
    await say("deja eso", to: h)
    await pumpUntil("brain stop: stopped") { !jobs.stopped.isEmpty }
    expectEq(jobs.stopped, [second], "brain stop: the named job")
    expectEq(jobs.stoppedAll, 0, "brain stop: nothing else")
    expect(first.map { jobs.live.contains($0) } == true, "brain stop: the other job keeps running")
}

/// The island's pill and Esc cut the turn and its voice, never the work.
@MainActor func testTheVoiceBrakeLeavesTheJobsRunning() async {
    let (h, jobs, _) = await relationHarness { _ in nil }
    await say("crea un archivo", to: h)
    guard let id = await runningJob("crea un archivo", on: h) else { return }
    await h.session.interrupt()
    expect(jobs.stopped.isEmpty && jobs.stoppedAll == 0 && jobs.live.contains(id),
           "brake: the job keeps running")
}

/// Jobs take no steering, so an addition is a new job; the running one stays.
@MainActor func testAnAdditionStartsAnotherJobAndStopsNone() async {
    let (h, jobs, _) = await relationHarness { peaked("append", $0.offeredIds) }
    await say("crea un archivo", to: h)
    _ = await runningJob("crea un archivo", on: h)
    await say("crea otro archivo", to: h)
    _ = await runningJob("crea otro archivo", on: h)
    await pumpUntil("addition: two jobs") { jobs.live.count == 2 }
    expect(jobs.stopped.isEmpty && jobs.stoppedAll == 0, "addition: nothing is stopped")
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
