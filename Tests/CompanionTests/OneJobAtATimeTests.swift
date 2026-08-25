import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test @MainActor func oneJobAtATimeTests() {
    testASecondRequestIsQueuedNotDropped()
    testTheUserIsToldItIsQueued()
    testNothingInvitesTheModelToCancel()
    testTheFirstRequestSaysWhatItUnderstood()
}

final class BusySubmitter: JobSubmitter, @unchecked Sendable {
    let busy: Bool
    private let lock = NSLock()
    private var _submissions = 0

    init(busy: Bool) { self.busy = busy }

    var submissions: Int {
        lock.lock(); defer { lock.unlock() }; return _submissions
    }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        count()
        events.finish()
        return JobResult(output: "hecho", isError: false)
    }

    private func count() {
        lock.lock(); defer { lock.unlock() }
        _submissions += 1
    }

    func cancel() async {}
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { busy } }
}

final class RecordingThread: ConversationPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: [String] = []
    var status: [String] {
        lock.lock(); defer { lock.unlock() }; return _status
    }
    func historyTurns() async -> [Turn] { [] }
    func appendUser(_ text: String) async {}
    func appendAssistant(_ text: String) async {}
    func appendStatus(_ text: String) async { record(text) }

    private func record(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        _status.append(text)
    }
    func showStream(_ text: String) async {}
    func finishStream() async {}
}

@MainActor private func voiceAsks(busy: Bool) -> (BusySubmitter, RecordingThread) {
    let submitter = BusySubmitter(busy: busy)
    let thread = RecordingThread()
    do {
        try runAsync {
            await VoiceJobBridge.run(
                Handoff(goal: "buscar cines", context: ""),
                jobs: submitter, thread: thread, language: .es)
        }
    } catch {
        expect(false, "el puente no debia tirar: \(error)")
    }
    return (submitter, thread)
}

@MainActor func testASecondRequestIsQueuedNotDropped() {
    // Lo que Karen esperaba, y lo que hacen las dos referencias: pedir otra
    // cosa no mata lo que corre. `JobQueue` ya serializa; lo que faltaba era
    // decirlo.
    let (submitter, _) = voiceAsks(busy: true)
    expectEq(submitter.submissions, 1,
             "el segundo encargo se manda igual: la cola decide cuando corre")
}

@MainActor func testTheUserIsToldItIsQueued() {
    let (_, thread) = voiceAsks(busy: true)
    let said = thread.status.joined(separator: " ").lowercased()
    expect(said.contains("cola"),
           "se dice que espera, no que arranco: \(said)")
}

@MainActor func testNothingInvitesTheModelToCancel() {
    // El bug que esto arregla: la version anterior decia "dime para si quieres
    // que lo deje", el modelo lo leyo como instruccion y llamo a stop_job.
    // Copy que llega a un modelo no es copy, es prompt.
    for language in [AppLanguage.en, .es] {
        let notice = Escalation.queuedNotice("x", language).lowercased()
        expect(!notice.contains("para si") && !notice.contains("stop"),
               "\(language): el aviso no sugiere parar nada")
        let announcement = Escalation
            .queuedAnnouncement("x", language).lowercased()
        expect(announcement.contains("no pares") || announcement.contains("not stop"),
               "\(language): y a la voz se le prohibe explicitamente")
    }
}

@MainActor func testTheFirstRequestSaysWhatItUnderstood() {
    let (submitter, thread) = voiceAsks(busy: false)
    expectEq(submitter.submissions, 1, "sin nada en vuelo, arranca")
    let said = thread.status.joined(separator: " ")
    expect(said.contains("Entendí") || said.contains("Heard"),
           "y repite lo entendido antes de tocar nada: \(said)")
}
