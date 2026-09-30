import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// The classic rig shared by the 16q-1 approval suites: a job asks, the voice
// says the question, a hold answers it.

let q1Flights = Handoff(goal: "busca vuelos en Safari", context: "")

func q1Req(_ id: String, tool: String = "run_shell") -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: tool, summary: "borrar build", inputJSON: "{}")
}

let q1SaysYes: [ChatDelta] = [
    .toolCalls([ToolCallRef(id: "y1", name: "resolve_approval", arguments: #"{"approved":true}"#)]),
]

final class Q1SessionVoiceBox: VoiceControlling, @unchecked Sendable {
    var session: VoiceSession?
    func setSpeed(_ speed: Double) async {}
    func setVolume(_ volume: Double) async {}
    func start() async {}
    func advance() async {}
    func hangUp() async {}
    func toggleMute() async {}
    func push(attachment: AttachmentRef) async {}
    func interrupt() async { await session?.interrupt() }
    func approvalClosed(requestId: String) async { await session?.approvalClosed(requestId: requestId) }
    var snapshots: AsyncStream<TurnSnapshot> { AsyncStream { $0.finish() } }
    var levels: AsyncStream<VoiceLevels> { AsyncStream { $0.finish() } }
}

@MainActor func q1Classic(
    _ jobs: GatedJob, model: SessionModel? = nil, rounds: [[ChatDelta]]? = nil
) async -> VoiceHarness {
    let h = makeVoiceHarness(jobs: jobs, language: .es, session: model)
    h.transcriber.stoppedText = "limpia el build"
    h.chat.rounds = rounds ?? [[.handoff(q1Flights)], [.text("Resumen.")]]
    await h.session.hold()
    await pumpUntil("rig: escuchando") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("rig: el encargo arranco") { jobs.goals.count == 1 }
    h.synth.yield(.finished)
    await pumpUntil("rig: el turno acabo") { h.watch.latest.state == .idle }
    return h
}

/// The job asks; the voice says the question and it finishes sounding. A
/// second call counts its own question, not one an earlier request left in
/// the synthesizer's queue.
@MainActor func q1AskedAndSaid(_ h: VoiceHarness, _ jobs: GatedJob, _ id: String = "r1") async {
    let question = Escalation.approvalAskedSpoken(.es)
    let before = h.synth.queue.filter { $0 == question }.count
    jobs.ask(q1Req(id))
    await pumpUntil("rig: la voz dice la pregunta") {
        h.synth.queue.filter { $0 == question }.count > before
    }
    h.synth.yield(.finished)
    await pumpUntilAsync("rig: anunciada") {
        let seen = await h.session.pendingApprovalSeen
        return seen?.requestId == id && seen?.announcedAt != nil
    }
}

@MainActor func q1HeldKey(_ h: VoiceHarness) async {
    h.clock.now += 5
    await h.session.hold()
    await pumpUntil("rig: hold") { h.watch.latest.state == .listening }
    h.clock.now += 1
}

