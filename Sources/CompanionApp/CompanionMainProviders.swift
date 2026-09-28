import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import CoreGraphics
import SwiftUI

/// The chat clients (main + hold ladder) and the conversation store. Split
/// out of `applicationDidFinishLaunching` when CompanionMain crossed the
/// 400-line gate.
struct ChatProviders {
    let localCatalog: LocalCatalog
    let chat: ChatProviderClient
    let holdChat: FastBrainChatProvider
    let store: ConversationStore
}

/// Verbatim from the chat-client section of the old
/// `applicationDidFinishLaunching`.
func makeChatProviders(environment env: LaunchEnvironment) -> ChatProviders {
    // Which local model exists is a fact about THIS Mac, so the Ollama row
    // is resolved at runtime instead of shipping a fixed tag. Scanned once
    // at launch; the router reads the result per request.
    let localCatalog = LocalCatalog(
        scan: OllamaModelScan(transport: env.transport))
    // The router needs this even when onboarding never runs: someone with
    // a key still deserves the local model as a fallback. The onboarding
    // probe below refreshes it again only when there is NO key, which is
    // one extra GET to localhost in exchange for never routing to a model
    // the daemon does not have.
    Task {
        await localCatalog.refresh(
            preferred: ProviderPreference.localModel)
    }
    // One shape for every chat client below: they differ only in which
    // providers they may ask and how patiently.
    let makeChat: (
        [ProviderDescriptor], (@Sendable () -> [ProviderDescriptor])?, Int, Bool
    ) -> ChatProviderClient = { catalog, catalogSource, maxAttempts, voice in
        ChatProviderClient(
            secrets: env.secrets,
            probe: env.probe,
            transport: env.transport,
            settings: env.config.chat,
            ownerFirstName: env.config.ownerFirstName,
            ownerAbout: env.config.ownerAbout,
            ownerInstructions: env.config.ownerInstructions,
            profileSource: {
                let live = env.configProvider.current
                return (live.ownerFirstName, live.ownerAbout,
                        live.ownerInstructions)
            },
            languageSource: { env.configProvider.current.language },
            memorySource: { env.configProvider.current.memory },
            skillsSource: { env.configProvider.current.skills },
            catalog: catalog,
            catalogSource: catalogSource,
            maxAttempts: maxAttempts,
            voice: voice)
    }
    let chat = makeChat(
        ProviderDescriptor.catalog, { localCatalog.effective() },
        RetryPolicy.maxAttempts, false)
    // Wave 15c-3/15e-3: the hold's own brain — Cerebras, one attempt;
    // its ladder falls to OpenAI's mini (`HoldBrainCatalog`).
    // 15d-9: both hold clients speak; only they get the voice rules.
    let fastBrain = makeChat(HoldBrainCatalog.fast, nil, 1, true)
    let holdLadder = makeChat(
        HoldBrainCatalog.ladder(ProviderDescriptor.catalog),
        { HoldBrainCatalog.ladder(localCatalog.effective()) },
        RetryPolicy.maxAttempts, true)
    let holdChat = FastBrainChatProvider(fast: fastBrain, ladder: holdLadder)
    let store = ConversationStore(directory: env.support)

    return ChatProviders(
        localCatalog: localCatalog, chat: chat, holdChat: holdChat, store: store)
}

/// Job execution: the executor catalog, the picker and the runner. Split out
/// of `applicationDidFinishLaunching` when CompanionMain crossed the
/// 400-line gate. `self.executorChoice` is set by the caller, which keeps
/// that stored property private to CompanionMain.swift.
struct JobInfrastructure {
    let approvals: Approvals
    let choice: ExecutorChoice
    let jobRunner: JobRunner
}

/// Verbatim from the "Job execution infrastructure" section of the old
/// `applicationDidFinishLaunching`.
func makeJobInfrastructure(
    environment env: LaunchEnvironment, chat: ChatProviderClient
) -> JobInfrastructure {
    // Job execution infrastructure
    let approvals = Approvals(clock: RealtimeClock())
    let jobQueue = JobQueue()
    let nativeExecutor = NativeExecutor(
        descriptor: ExecutorCatalog.native,
        chatProvider: chat,
        config: env.config,
        approvals: approvals,
        webSearch: BraveWebSearch(transport: env.transport, secrets: env.secrets),
        skills: env.skillsLocation,
        skillsSource: { env.configProvider.current.skills })
    // The real provider probes for claude and hermes; without them the
    // catalog is just the native executor and nothing changes (ADR 001).
    let sessions = FileExecutorSessionStore(
        fileURL: env.support
            .deletingLastPathComponent()
            .appendingPathComponent("executor-sessions.json"))
    let executors = ExecutorProvider(
        nativeExecutor: nativeExecutor,
        cliProbe: CLIExecutorProbe(),
        workdir: env.config.workdir,
        approvals: approvals,
        sessions: sessions,
        skills: { env.configProvider.current.skills })
    // The picker starts with the native executor and grows when the probe
    // finds a CLI; nothing appears if none is installed (ADR 001).
    let choice = ExecutorChoice(
        available: [ExecutorCatalog.native],
        selected: .native
    ) { id in
        _ = executors.selectExecutor(id: id)
    }
    Task {
        await executors.refreshAvailableExecutors()
        await MainActor.run {
            choice.refresh(
                executors.getAvailableExecutors(),
                selected: executors.getSelectedExecutorId())
        }
    }

    let jobRunner = JobRunner(
        executorProvider: executors,
        queue: jobQueue,
        approvals: approvals,
        language: { env.configProvider.current.language })

    return JobInfrastructure(approvals: approvals, choice: choice, jobRunner: jobRunner)
}
