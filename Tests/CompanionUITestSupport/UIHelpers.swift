import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUI
import Foundation
import Testing

/// UI copy tests assert exact wording, so they must not depend on which
/// language the machine running them happens to prefer. English is the
/// source; a Spanish assertion pins `.es` explicitly.
/// Debugging 2026-09-28: takes the rest of the dispatcher as a trailing
/// closure instead of just assigning `Localized.language` — Swift Testing
/// runs `@Test` functions in parallel, so a bare assignment let two
/// dispatchers stomp on each other's pin mid-run. `Localized.scoped` binds
/// it to this call's task tree only.
@MainActor package func pinLanguage<R>(
    _ language: AppLanguage = .en, _ body: () async throws -> R
) async rethrows -> R {
    try await Localized.scoped(to: language, body)
}

@MainActor package func primed(
    chat: FakeChatProvider,
    store: MemoryConversationStore = MemoryConversationStore(),
    parentTools: (any ParentToolExecuting)? = nil,
    sensor: (any ContextSensing)? = nil,
    config: Config = .default,
    approvals: (any ApprovalsProvider)? = nil
) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: chat, secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: config, parentTools: parentTools, sensor: sensor,
        approvals: approvals)
    vm.onAppear()
    return vm
}

@MainActor package func onboard(_ chat: FakeChatProvider, _ secrets: TestSecretStore)
    -> ChatViewModel
{
    let vm = ChatViewModel(
        chat: chat, secrets: secrets, store: MemoryConversationStore(),
        config: .default)
    vm.onAppear()
    expect(vm.needsOnboarding, "onboard: pide clave")
    return vm
}

@MainActor package func readOpenAI(_ secrets: TestSecretStore) -> String? {
    do { return try secrets.read(.openAI) } catch {
        expect(false, "secret read no debía tirar \(error)")
        return nil
    }
}

@MainActor package func awaitMain(_ body: @escaping @MainActor () async -> Void) async {
    await body()
}

@MainActor package func chat() -> ChatViewModel {
    ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: Config())
}

extension ChatViewModel {
    /// Answers the sheet that is up right now. Failing when none is pending
    /// keeps a test from silently answering "" and passing for the wrong reason.
    @MainActor package func answerPendingApproval(
        _ approved: Bool, remember: Bool = false
    ) {
        guard let id = pendingApproval?.requestId else {
            expect(false, "answerPendingApproval: no approval is pending")
            return
        }
        answerApproval(approved, remember: remember, requestId: id)
    }
}
