import CompanionCore
import CompanionUIPro
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// An action she watched happen is not confirmed: the turn ends with no text,
// no receipt card and no "no answer" error. A failure is still told.

private final class OpenTools: ParentToolExecuting, @unchecked Sendable {
    let succeeds: Bool
    init(succeeds: Bool) { self.succeeds = succeeds }
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: succeeds, output: succeeds ? "opened" : "refused", target: "Safari", tool: name)
    }
}

@MainActor private func turn(succeeds: Bool) async -> ChatViewModel {
    let call = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let chat = FakeChatProvider(replies: [.success([.toolCalls([call])]), .success([])])
    let vm = primed(chat: chat, parentTools: OpenTools(succeeds: succeeds), config: Config(language: .es))
    vm.draft = "abre Safari"
    vm.send()
    await pumpUntil("quieto: el turno terminó") { !vm.busy }
    return vm
}

@Test @MainActor func testASuccessfulActionWithAnEmptyFinalReplyEndsCleanly() async {
    let vm = await turn(succeeds: true)
    let bubbles = vm.messages.filter { $0.role == .assistant && !$0.isStatus }
    expect(bubbles.isEmpty, "quieto: ninguna burbuja de asistente (\(bubbles.map(\.text)))")
    expect(!vm.messages.contains { $0.endedWithoutAnswer || $0.isFailure || $0.stepFailed },
           "quieto: nada marcado como fallo ni sin respuesta")
    expect(vm.errorText == nil, "quieto: sin error")
    expect(vm.session.projection.notice == nil, "quieto: sin tarjeta de recibo ni aviso")
}

@Test @MainActor func testAFailedActionWithAnEmptyFinalReplyIsStillTold() async {
    let vm = await turn(succeeds: false)
    expect(vm.messages.contains { $0.endedWithoutAnswer }, "fallo: la respuesta vacía tras un fallo se dice")
}
