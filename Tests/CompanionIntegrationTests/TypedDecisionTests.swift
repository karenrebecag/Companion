import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
@testable import CompanionUI
import CompanionServicesTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

// Typed words through the router a hold uses: same gate, same judge, same
// delegation head, nothing of it duplicated on the chat side.

@Test @MainActor func typedDecisionTests() async {
    await testATypedTrashOrderAsksAndATypedNoCancels()
    await testATypedOpenActsWithAReceipt()
    await testATypedBackgroundRequestKeepsDelegate()
    await testASureSelfHandledVerdictWithdrawsDelegateFromTheBrain()
    await testWithoutTheKeyNothingTypedReachesTypeSafe()
    await testTypedProseThatOpensWithAYesIsNotAnAnswer()
    await testASkippedTurnOrAClearedThreadDropsTheOpenQuestion()
    await testALongOrMultiLineMessageNeverReachesTheHostedJudge()
    await testAVoiceYesAfterATypedCardPickAnswersNothing()
}

@MainActor private func typedChat(
    hosted: ScriptedHosted, system: RecordingSystemActing = RecordingSystemActing(),
    opener: FakeWorkspaceOpener = FakeWorkspaceOpener(installed: ["Safari"]),
    replies: [Result<[ChatDelta], Error>] = [], jobs: (any JobSubmitter)? = nil,
    local: ScriptedDecision = ScriptedDecision { _ in nil }
) -> (ChatViewModel, FakeChatProvider) {
    let judge = DecisionJudge(hosted: hosted, local: local)
    let gate = DecisionGate(
        provider: judge, arbiter: NoArbiter(), tools: ParentToolRunner(workspace: opener),
        system: system, world: { DecisionWorld(apps: ["Safari"], sites: []) }, budget: .seconds(2))
    return typedChat(gate: gate, judge: judge, replies: replies, jobs: jobs)
}

@MainActor private func typedChat(
    gate: DecisionGate, judge: DecisionJudge,
    replies: [Result<[ChatDelta], Error>] = [], jobs: (any JobSubmitter)? = nil
) -> (ChatViewModel, FakeChatProvider) {
    var config = Config.default
    config.language = .es
    let chat = FakeChatProvider(replies: replies)
    let vm = ChatViewModel(
        chat: chat, secrets: TestSecretStore([.openAI: "sk-test"]), store: MemoryConversationStore(),
        config: config, jobSubmitter: jobs)
    vm.onAppear()
    vm.decider = TextTurnDecider(gate: gate, judge: judge, config: StaticConfigProvider(config))
    return (vm, chat)
}

@MainActor private func type(_ text: String, into vm: ChatViewModel) async {
    vm.draft = text
    vm.send()
    await pumpUntil("typed: \(text)") { !vm.busy }
}

/// The irreversible order asks in the thread; the next typed message
/// answers it, with the gate's own pending-confirmation semantics.
@MainActor func testATypedTrashOrderAsksAndATypedNoCancels() async {
    let script = trashProvider()
    let system = RecordingSystemActing()
    let (vm, chat) = typedChat(hosted: ScriptedHosted(configured: true) { script.body($0) }, system: system)
    await type("vacia la papelera", into: vm)
    expectEq(vm.messages.last?.text, "¿Vacío la papelera?", "typed trash: asks in the thread")
    await type("no", into: vm)
    expectEq(vm.messages.last?.text, DecisionCopy.declined(.es), "typed trash: the no cancels")
    expectEq(system.actCount, 0, "typed trash: nothing was emptied")
    expect(chat.histories.isEmpty, "typed trash: the brain was never asked")
}

@MainActor func testATypedOpenActsWithAReceipt() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let hosted = ScriptedHosted(configured: true) { question in
        switch question.id {
        case DecisionHead.action: return peaked("open_app", question.offeredIds)
        case DecisionHead.app: return peaked("Safari", question.offeredIds)
        default: return nil
        }
    }
    let (vm, chat) = typedChat(hosted: hosted, opener: opener)
    await type("abre Safari", into: vm)
    expectEq(opener.openedApps, ["Safari"], "typed open: Safari opened once")
    expect(chat.histories.isEmpty, "typed open: the brain was never asked")
    expectEq(vm.messages.map(\.role), [.user, .assistant], "typed open: the router replies in the thread")
    expect(vm.turnRing.records.last?.receipts.isEmpty == false, "typed open: the turn carries its receipt")
}

/// A head sure the words are the assistant's own, and an action head that
/// passes, so the turn reaches the brain with the verdict applied.
private func selfHandled() -> ScriptedHosted {
    ScriptedHosted(configured: true) { question in
        question.id == DelegationHead.id ? peaked(DelegationHead.answer, question.offeredIds) : nil
    }
}

@MainActor func testATypedBackgroundRequestKeepsDelegate() async {
    let (vm, chat) = typedChat(
        hosted: selfHandled(), replies: [.success([.text("ok")])], jobs: CapturingSubmitter())
    await type("resume mis notas en segundo plano", into: vm)
    expect(chat.toolsSeen.contains { $0.name == "delegate" }, "typed background: delegate stays offered")
}

@MainActor func testASureSelfHandledVerdictWithdrawsDelegateFromTheBrain() async {
    let (vm, chat) = typedChat(
        hosted: selfHandled(), replies: [.success([.text("ok")])], jobs: CapturingSubmitter())
    await type("resume mis notas", into: vm)
    expect(!chat.toolsSeen.contains { $0.name == "delegate" }, "typed withdraw: delegate is off the tools")
    expect(chat.histories.first?.last?.content.hasPrefix(DelegationHead.withdrawnNote) == true,
           "typed withdraw: the brain is told why")
}

@MainActor func testWithoutTheKeyNothingTypedReachesTypeSafe() async {
    let hosted = ScriptedHosted(configured: false) { _ in nil }
    let (vm, chat) = typedChat(
        hosted: hosted, replies: [.success([.text("ok")])], jobs: CapturingSubmitter())
    await type("abre Safari", into: vm)
    expectEq(hosted.calls, 0, "typed no key: TypeSafe is never asked")
    expectEq(chat.histories.count, 1, "typed no key: the brain answers, as before")
}

/// Security review of #360 (H1): a typed sentence that happens to open with
/// "si" or "yes" is prose, not the answer to an open question.
@MainActor func testTypedProseThatOpensWithAYesIsNotAnAnswer() async {
    let script = trashProvider()
    let system = RecordingSystemActing()
    let (vm, _) = typedChat(hosted: ScriptedHosted(configured: true) { script.body($0) }, system: system)
    for prose in ["si puedes, abre Safari", "yes please also tell me the weather"] {
        await type("vacia la papelera", into: vm)
        await type(prose, into: vm)
        expectEq(system.actCount, 0, "typed prose: \(prose) empties nothing")
    }
    await type("vacia la papelera", into: vm)
    await type("sí, dale", into: vm)
    expectEq(system.actCount, 1, "typed prose: a short yes still answers")
}

/// Security review of #360 (M1): the open question belongs to the turn that
/// asked it. A card pick in between, or a new thread, drops it.
@MainActor func testASkippedTurnOrAClearedThreadDropsTheOpenQuestion() async {
    let script = trashProvider()
    let system = RecordingSystemActing()
    let (vm, _) = typedChat(
        hosted: ScriptedHosted(configured: true) { script.body($0) }, system: system,
        replies: [.success([.text("ok")])])
    await type("vacia la papelera", into: vm)
    vm.startTurn("la segunda", origin: .choice)
    await pumpUntil("skipped: card turn done") { !vm.busy }
    await type("si", into: vm)
    expectEq(system.actCount, 0, "skipped: a yes after a card pick answers nothing")
    await type("vacia la papelera", into: vm)
    vm.newConversation()
    await type("si", into: vm)
    expectEq(system.actCount, 0, "skipped: a yes in a new thread answers nothing")
}

/// Karen, 2026-10-19: pasted code, an email or a long paragraph is never a
/// short command; with the key saved it still goes to the brain alone.
@MainActor func testALongOrMultiLineMessageNeverReachesTheHostedJudge() async {
    let hosted = ScriptedHosted(configured: true) { _ in nil }
    let long = String(repeating: "abre Safari y luego ", count: 12)
    let (vm, chat) = typedChat(
        hosted: hosted, replies: [.success([.text("ok")]), .success([.text("ok")])],
        jobs: CapturingSubmitter())
    await type("abre Safari\ny luego Slack", into: vm)
    await type(long, into: vm)
    expectEq(hosted.calls, 0, "typed long: the hosted judge is never asked")
    expectEq(chat.histories.count, 2, "typed long: the brain answers both")
    expect(chat.toolsSeen.contains { $0.name == "delegate" }, "typed long: delegate stays offered")
}

/// Re-review of #360 (M1): the question is dropped the moment the chat
/// moves on, not at its next typed turn, so the hold cannot answer it.
@MainActor func testAVoiceYesAfterATypedCardPickAnswersNothing() async {
    unsetenv("COMPANION_DECISION")
    let script = trashProvider()
    let system = RecordingSystemActing()
    let judge = DecisionJudge(
        hosted: ScriptedHosted(configured: true) { script.body($0) }, local: ScriptedDecision { _ in nil })
    let gate = DecisionGate(
        provider: judge, arbiter: NoArbiter(), tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    let (vm, _) = typedChat(gate: gate, judge: judge, replies: [.success([.text("ok")])])
    await type("vacia la papelera", into: vm)
    vm.startTurn("la segunda", origin: .choice)
    await pumpUntil("voice yes: card turn done") { !vm.busy }
    await pumpUntilAsync("voice yes: question dropped") { await !gate.answersPendingConfirmation("si") }
    let h = makeVoiceHarness(language: .es)
    await h.session.attachDecision(gate, judge: judge)
    h.transcriber.stoppedText = "si"
    await h.session.hold()
    await pumpUntil("voice yes: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("voice yes: the hold replies") { !h.synth.queue.isEmpty }
    expectEq(system.actCount, 0, "voice yes: the hold answers nothing")
}
