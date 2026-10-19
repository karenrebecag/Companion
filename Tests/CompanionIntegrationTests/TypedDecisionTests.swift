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
}

@MainActor private func typedChat(
    hosted: ScriptedHosted, system: RecordingSystemActing = RecordingSystemActing(),
    opener: FakeWorkspaceOpener = FakeWorkspaceOpener(installed: ["Safari"]),
    replies: [Result<[ChatDelta], Error>] = [], jobs: (any JobSubmitter)? = nil,
    local: ScriptedDecision = ScriptedDecision { _ in nil }
) -> (ChatViewModel, FakeChatProvider) {
    var config = Config.default
    config.language = .es
    let judge = DecisionJudge(hosted: hosted, local: local)
    let gate = DecisionGate(
        provider: judge, arbiter: NoArbiter(), tools: ParentToolRunner(workspace: opener),
        system: system, world: { DecisionWorld(apps: ["Safari"], sites: []) }, budget: .seconds(2))
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
