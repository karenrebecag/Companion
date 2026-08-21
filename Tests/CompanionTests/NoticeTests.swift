import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func noticeTests() async {
    testQueueExpiresAfterLifetime()
    testQueueCapsVisibleAndDropsOldest()
    testCueMatchesLevel()
    testCenterPostsSoundAndVisible()
    testCenterTickExpires()
    testApprovalToasts()
    await testJobResultToasts()
}

@MainActor func testQueueExpiresAfterLifetime() {
    var queue = NoticeQueue()
    queue.add("hola", level: .info, at: 10)
    queue.expire(at: 13.9)
    expectEq(queue.visible.count, 1, "cola: sigue vivo a 3.9 s")
    queue.expire(at: 14)
    expectEq(queue.visible.count, 0, "cola: se va a los 4 s")
}

@MainActor func testQueueCapsVisibleAndDropsOldest() {
    var queue = NoticeQueue()
    queue.add("a", level: .info, at: 1)
    queue.add("b", level: .info, at: 2)
    queue.add("c", level: .info, at: 3)
    queue.add("d", level: .error, at: 4)
    expectEq(queue.visible.map(\.text), ["b", "c", "d"],
             "cola: el más viejo cede el sitio")
    expectEq(queue.visible.last?.level, .error, "cola: conserva la variante")
}

@MainActor func testCueMatchesLevel() {
    expectEq(SoundCue.forLevel(.info), .confirm, "cue: info confirma")
    expectEq(SoundCue.forLevel(.error), .alert, "cue: error alerta")
}

@MainActor func testCenterPostsSoundAndVisible() {
    let sound = RecordingSound()
    let center = NoticeCenter(sound: sound, now: { 100 })
    center.toast("listo")
    center.toast("falló", level: .error)
    expectEq(center.queue.visible.map(\.text), ["listo", "falló"],
             "center: apila")
    expectEq(sound.played, [.confirm, .alert], "center: cue por evento")
}

@MainActor func testCenterTickExpires() {
    var t: TimeInterval = 0
    let center = NoticeCenter(sound: nil, now: { t })
    center.toast("x")
    t = 4
    center.tick()
    expectEq(center.queue.visible.count, 0, "center: tick usa el reloj inyectado")
}

@MainActor func testApprovalToasts() {
    let sound = RecordingSound()
    let notices = NoticeCenter(sound: sound, now: { 1 })
    let submitter = RecordingSubmitter()
    let vm = ChatViewModel(
        chat: FakeChatProvider(),
        secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(),
        config: .default,
        jobSubmitter: submitter,
        notices: notices)
    vm.onAppear()
    vm.receiveJobEventForTesting(.approvalRequested(ApprovalRequest(
        requestId: "r1", toolName: "run_shell", summary: "ls", inputJSON: "{}")))
    vm.answerApproval(true)
    expectEq(notices.queue.visible.last?.text, ChatCopy.approvalAnswer(true),
             "toast: permiso resuelto avisa")
    expectEq(sound.played.last, .confirm, "toast: permiso concedido confirma")
    vm.receiveJobEventForTesting(.approvalRequested(ApprovalRequest(
        requestId: "r2", toolName: "run_shell", summary: "ls", inputJSON: "{}")))
    vm.answerApproval(false)
    expectEq(notices.queue.visible.last?.level, .error,
             "toast: permiso denegado es error")
}

@MainActor func testJobResultToasts() async {
    let sound = RecordingSound()
    let notices = NoticeCenter(sound: sound, now: { 1 })
    let handoff = Handoff(goal: "listar", context: "")
    let chat = FakeChatProvider(
        replies: [.success([.text("Voy. "), .handoff(handoff)])])
    let vm = ChatViewModel(
        chat: chat,
        secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(),
        config: .default,
        jobSubmitter: RecordingSubmitter(),
        notices: notices)
    vm.onAppear()
    vm.draft = "hazlo"
    vm.send()
    await pumpUntil("job toast: idle") { !vm.busy }
    expectEq(notices.queue.visible.last?.text, ChatCopy.jobDone,
             "toast: encargo terminado avisa")
    expectEq(sound.played.last, .confirm, "toast: encargo listo confirma")

    let failNotices = NoticeCenter(sound: sound, now: { 1 })
    let failChat = FakeChatProvider(
        replies: [.success([.text("Voy. "), .handoff(handoff)])])
    let failVM = ChatViewModel(
        chat: failChat,
        secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(),
        config: .default,
        jobSubmitter: FailingSubmitter(),
        notices: failNotices)
    failVM.onAppear()
    failVM.draft = "hazlo"
    failVM.send()
    await pumpUntil("job toast fail: idle") { !failVM.busy }
    expectEq(failNotices.queue.visible.last?.text, ChatCopy.jobFailed,
             "toast: encargo fallido avisa")
    expectEq(failNotices.queue.visible.last?.level, .error,
             "toast: encargo fallido es error")
}

final class FailingSubmitter: JobSubmitter, @unchecked Sendable {
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        JobResult(output: "boom", isError: true)
    }
    func cancel() async {}
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

final class RecordingSound: InterfaceSounding, @unchecked Sendable {
    private let lock = NSLock()
    private var cues: [SoundCue] = []
    var played: [SoundCue] { lock.withLock { cues } }
    func play(_ cue: SoundCue) { lock.withLock { cues.append(cue) } }
}
