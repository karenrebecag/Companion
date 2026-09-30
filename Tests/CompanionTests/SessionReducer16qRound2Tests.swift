import CompanionCore
import Foundation
import Testing

// 16q-1, second review round, reducer side: a request id already on the sheet
// is not queued twice (C1), and a brake inside the release tail closes the
// mic that is still listening (Q5).

@Test @MainActor func sessionReducer16qRound2Tests() {
    testADuplicateRequestIdIsIgnored()
    testAStopInsideTheReleaseTailClosesTheMicWithoutCommitting()
    testTheTotalStopInsideTheReleaseTailClosesTheMicToo()
}

private let alpha = JobID("alpha")
private let beta = JobID("beta")

private func request(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

private func queued(_ machine: SessionMachine) -> [String] {
    machine.projection.approvalQueue.map(\.requestId)
}

/// An id is one request: a repeat must neither add a second card nor take the
/// original away from the job that asked first.
@MainActor func testADuplicateRequestIdIsIgnored() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "a"), from: alpha))
    _ = m.handle(.job(.started(goal: "b"), from: beta))
    _ = m.handle(.job(.approvalRequested(request("r1")), from: alpha))
    _ = m.handle(.job(.approvalRequested(request("r1")), from: beta))
    expectEq(queued(m), ["r1"], "duplicado: una sola tarjeta")
    _ = m.handle(.stopJob(beta))
    expectEq(queued(m), ["r1"], "duplicado: parar al segundo no toca la peticion del primero")
    let effects = m.handle(.stopJob(alpha))
    expect(effects.contains(.resolveApproval(requestId: "r1", approved: false, remember: false)),
           "duplicado: la peticion sigue siendo del primero y su stop la niega")
    expectEq(queued(m), [], "duplicado: y la hoja queda vacia")
}

/// Press, release: the commit has not left yet and the voice still listens.
private func inTheReleaseTail() -> SessionMachine {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic, holdArmed: true)))
    _ = m.handle(.released)
    return m
}

@MainActor func testAStopInsideTheReleaseTailClosesTheMicWithoutCommitting() {
    var m = inTheReleaseTail()
    expectEq(m.projection.kind, .processing(.pending), "cola: esperando lo dicho")
    let effects = m.handle(.stopVoice)
    expect(effects.contains(.stopListening(commit: false)), "cola: el freno de voz cierra el mic sin enviar")
    expect(!effects.contains(.stopListening(commit: true)), "cola: y no envia lo que oyo")
}

@MainActor func testTheTotalStopInsideTheReleaseTailClosesTheMicToo() {
    var m = inTheReleaseTail()
    let effects = m.handle(.stop)
    expect(effects.contains(.stopListening(commit: false)), "cola total: el freno total tambien cierra el mic")
}
