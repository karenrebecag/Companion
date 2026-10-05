import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

/// What a clear leaves behind when something was still running. The store is
/// the real one on a temp directory: a fake would not notice a file coming
/// back after the clear.
@Suite("ClearHistory")
struct ClearHistoryJobTests {
    @Test @MainActor func jobEventsAfterClearDoNotWriteANewChat() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        await rig.vm.appendUser("hola")
        let oldId = rig.vm.conversationId
        expect(try rig.store.load(oldId) != nil, "the chat is on disk before the clear")
        let run = rig.startJob()
        await pumpUntil("the job is running") { rig.jobs.started }

        try rig.vm.applyHistoryClear(.confirm)
        await pumpUntil("the clear stops the job") { rig.jobs.cancelled }
        rig.jobs.emit(.approvalRequested(ApprovalRequest(
            requestId: "late", toolName: "run_shell", summary: "ls", inputJSON: "{}")))
        rig.jobs.emit(.approvalDenied(tool: "run_shell"))
        await settle(0.1)
        rig.jobs.finish(.failure(CancellationError()))
        await run.value

        expect(try rig.store.list().isEmpty, "no chat was written after the clear")
        expect(try rig.store.load(oldId) == nil, "the deleted chat did not come back")
        expect(rig.vm.messages.isEmpty, "the new thread stays empty")
        expect(rig.vm.job == nil, "no job row is left")
    }

    @Test @MainActor func jobFinishingAfterClearDoesNotPersist() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        await rig.vm.appendUser("hola")
        let oldId = rig.vm.conversationId
        let run = rig.startJob()
        await pumpUntil("the job is running") { rig.jobs.started }

        try rig.vm.applyHistoryClear(.confirm)
        rig.jobs.finish(.success(JobResult(output: "informe final", isError: false)))
        await run.value

        expect(try rig.store.list().isEmpty, "a result that arrives late is not stored")
        expect(try rig.store.load(oldId) == nil, "the old id stays dead")
        expect(rig.vm.messages.isEmpty, "neither the result nor a record line reaches the new thread")
        expect(!rig.vm.cancelledJob, "the stop flag does not outlive the clear")
        expect(rig.vm.chatJobID == nil, "the chat has no job of its own left")
    }

    @Test @MainActor func jobResultSurvivesSwitchingConversationMidJob() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        await rig.vm.appendUser("hola")
        let run = rig.startJob()
        await pumpUntil("the job is running") { rig.jobs.started }

        rig.vm.newConversation()
        rig.jobs.finish(.success(JobResult(output: "informe final", isError: false)))
        await run.value

        expect(
            rig.vm.messages.contains { $0.text == "informe final" },
            "switching threads is not a clear: the finished result is kept, as before")
    }

    @Test @MainActor func voiceJobEventsAfterClearDoNotWriteANewChat() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        await rig.vm.appendUser("hola")
        let oldId = rig.vm.conversationId
        let voice = JobID("voz")
        rig.vm.receive(.job(.started(goal: "buscar vuelos"), from: voice))
        expect(rig.vm.job != nil, "a voice job is in the session")

        try rig.vm.applyHistoryClear(.confirm)
        rig.vm.receive(.job(.approvalRequested(ApprovalRequest(
            requestId: "late-voice", toolName: "run_shell", summary: "ls", inputJSON: "{}")), from: voice))
        rig.vm.receive(.job(.approvalDenied(tool: "run_shell"), from: voice))
        rig.vm.receive(.jobFinished(ok: false, from: voice))

        expect(try rig.store.list().isEmpty, "a voice job's late events are not stored")
        expect(try rig.store.load(oldId) == nil, "the deleted chat did not come back")
        expect(rig.vm.messages.isEmpty, "the new thread stays empty")
        expect(rig.vm.job == nil, "no job row is left")
    }

    @Test @MainActor func oldTurnFinishingAfterClearDoesNotTouchTheNewTurn() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let chat = TurnScriptChat(
            first: [.handoff(Handoff(goal: "ordenar", context: ""))],
            then: [.text("respuesta nueva")])
        let vm = rig.makeVM(chat: chat)
        vm.draft = "ordena"
        vm.send()
        await pumpUntil("the old turn's job is running") { rig.jobs.started }

        try vm.applyHistoryClear(.confirm)
        vm.draft = "nuevo"
        vm.send()
        await pumpUntil("the new turn is streaming") { chat.calls == 2 }
        vm.draft = "cola"
        vm.send()
        expectEq(vm.queued, ["cola"], "a message waits behind the new turn")

        rig.jobs.finish(.success(JobResult(output: "informe final", isError: false)))
        await settle(0.2)
        expect(vm.busy, "the old turn ending does not end the new one")
        expectEq(chat.calls, 2, "and does not start what was queued")
        expectEq(vm.queued, ["cola"], "the queue is untouched")

        let newId = vm.conversationId
        chat.release(call: 1)
        await pumpUntil("the queued message starts once") { chat.calls == 3 }
        await settle(0.1)
        expectEq(chat.calls, 3, "it started exactly once")
        let listed = try rig.store.list()
        expectEq(listed.map(\.id), [newId], "the store holds only the new conversation")
        expect(
            try rig.store.load(newId)?.messages.contains { $0.text == "respuesta nueva" } == true,
            "with its reply")
        vm.abandonTurn()
    }

    @Test @MainActor func failedClearKeepsTheJobResultUnderTheOriginalId() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        await rig.vm.appendUser("hola")
        let oldId = rig.vm.conversationId
        let run = rig.startJob()
        await pumpUntil("the job is running") { rig.jobs.started }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rig.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rig.root.path) }

        do {
            try rig.vm.applyHistoryClear(.confirm)
            expect(false, "the clear cannot move the folder, so it throws")
        } catch {}
        rig.jobs.finish(.success(JobResult(output: "informe final", isError: false)))
        await run.value

        expectEq(rig.vm.conversationId, oldId, "a failed clear keeps the thread")
        expect(rig.vm.messages.contains { $0.text == "informe final" }, "the result is kept")
        rig.vm.persist()
        expect(
            try rig.store.load(oldId)?.messages.contains { $0.text == "informe final" } == true,
            "and stored under the original id")
    }

    @Test @MainActor func parentToolRoundAfterClearDoesNotPersist() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let tools = RoundTools(holdsBound: false)
        let chat = TurnScriptChat(first: [.toolCalls(Self.twoCalls)], then: [])
        let vm = rig.makeVM(chat: chat, parentTools: tools)
        vm.draft = "mira"
        vm.send()
        await pumpUntil("the second call is running") { tools.executed == 2 }

        try vm.applyHistoryClear(.confirm)
        tools.release()
        await settle(0.2)

        expect(try rig.store.list().isEmpty, "the cards the round already held are not stored")
        expect(vm.messages.isEmpty, "the new thread stays empty")
        vm.abandonTurn()
    }

    @Test @MainActor func rememberedApprovalAfterClearDoesNotLand() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let tools = RoundTools(holdsBound: true)
        let chat = TurnScriptChat(first: [.toolCalls([Self.twoCalls[0]])], then: [])
        let approvals = ScriptedApprovals(holds: .nothing, remembers: true)
        let vm = rig.makeVM(chat: chat, parentTools: tools, approvals: approvals)
        vm.draft = "mira"
        vm.send()
        await pumpUntil("the gate is waiting on the app") { tools.boundStarted }

        try vm.applyHistoryClear(.confirm)
        tools.release()
        await settle(0.2)

        expectEq(approvals.rememberedCalls, 0, "an old turn does not ask the memory after the clear")
        expectEq(tools.grantedCount, 0, "and grants nothing")
        expect(vm.messages.isEmpty, "an old turn's approval line does not open the new thread")
        expect(try rig.store.list().isEmpty, "and nothing is stored")
        vm.abandonTurn()
    }

    @Test @MainActor func clearDuringRememberedDoesNotGrant() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let tools = RoundTools(holdsBound: false, gated: true)
        let chat = TurnScriptChat(first: [.toolCalls([Self.twoCalls[0]])], then: [])
        let approvals = ScriptedApprovals(holds: .remembered, remembers: true)
        let vm = rig.makeVM(chat: chat, parentTools: tools, approvals: approvals)
        vm.draft = "mira"
        vm.send()
        await pumpUntil("the memory is being asked") { approvals.rememberedCalls == 1 }

        try vm.applyHistoryClear(.confirm)
        approvals.release()
        await settle(0.2)

        expect(vm.messages.isEmpty, "the remembered line does not open the new thread")
        expectEq(tools.grantedCount, 0, "a yes from the old chat grants nothing")
        expect(try rig.store.list().isEmpty, "and nothing is stored")
        vm.abandonTurn()
    }

    @Test @MainActor func approvalAnsweredAfterClearDoesNotGrant() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let tools = RoundTools(holdsBound: false, gated: true)
        let chat = TurnScriptChat(first: [.toolCalls([Self.twoCalls[0]])], then: [])
        let approvals = ScriptedApprovals(holds: .request, remembers: nil)
        let vm = rig.makeVM(chat: chat, parentTools: tools, approvals: approvals)
        vm.draft = "mira"
        vm.send()
        await pumpUntil("the sheet is open") { approvals.requestCalls == 1 }

        try vm.applyHistoryClear(.confirm)
        approvals.release()
        await settle(0.2)

        expectEq(tools.grantedCount, 0, "a yes given after the clear grants nothing")
        expect(vm.messages.isEmpty, "the new thread stays empty")
        vm.abandonTurn()
    }

    private static let twoCalls = [
        ToolCallRef(id: "c1", name: "look", arguments: "{}"),
        ToolCallRef(id: "c2", name: "look", arguments: "{}"),
    ]

    @Test @MainActor func clearingDoesNotWriteAStoppedLine() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let run = rig.startJob()
        await pumpUntil("the job is running") { rig.jobs.started }
        try rig.vm.applyHistoryClear(.confirm)
        expect(rig.vm.messages.isEmpty, "the stop is part of the clear, not a line in the new chat")
        rig.jobs.finish(.failure(CancellationError()))
        await run.value
        expect(try rig.store.list().isEmpty, "nothing was stored")
    }

    @Test @MainActor func streamingTurnCompletingAfterClearDoesNotPersist() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let chat = HeldChat(releasing: [.text("respuesta tardia")])
        let vm = rig.makeVM(chat: chat)
        vm.draft = "hola"
        vm.send()
        await pumpUntil("the provider is streaming") { chat.started }
        let oldId = vm.conversationId

        try vm.applyHistoryClear(.confirm)
        chat.release()
        await settle(0.1)

        expect(try rig.store.list().isEmpty, "a reply that lands late is not stored")
        expect(try rig.store.load(oldId) == nil, "the deleted chat did not come back")
        expect(vm.messages.isEmpty, "the new thread stays empty")
        expect(vm.streaming.isEmpty, "nothing is left streaming")
    }

    @Test @MainActor func turnWhoseJobFinishesAfterClearDoesNotPersist() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let chat = HeldChat(releasing: [.handoff(Handoff(goal: "ordenar", context: ""))])
        let vm = rig.makeVM(chat: chat)
        vm.draft = "ordena"
        vm.send()
        await pumpUntil("the provider is streaming") { chat.started }
        chat.release()
        await pumpUntil("the job is running") { rig.jobs.started }
        let oldId = vm.conversationId

        try vm.applyHistoryClear(.confirm)
        rig.jobs.finish(.success(JobResult(output: "informe final", isError: false)))
        await settle(0.2)

        expect(try rig.store.list().isEmpty, "the turn's own persist does not recreate the chat")
        expect(try rig.store.load(oldId) == nil, "the old id stays dead")
        expect(vm.messages.isEmpty, "the new thread stays empty")
    }

    @Test @MainActor func clearErasesTheAttachmentCopiesAndKeepsTheUsersFiles() async throws {
        let rig = try ClearJobRig()
        defer { rig.cleanup() }
        let picked = rig.root.appendingPathComponent("informe.txt")
        try Data("el archivo de ella".utf8).write(to: picked)
        let attachments = AttachmentStore(root: rig.root.appendingPathComponent("attachments"))
        let vm = rig.makeVM(chat: FakeChatProvider(), attachments: attachments)
        let ref = try #require(vm.attach(picked), "the file was adopted")
        expect(FileManager.default.fileExists(atPath: ref.path), "the app keeps its own copy")
        expect(attachments.storedBytes() > 0, "the copy is stored")

        try vm.applyHistoryClear(.confirm)

        expect(!FileManager.default.fileExists(atPath: ref.path), "the copy is erased with the chats")
        expectEq(attachments.storedBytes(), 0, "no attachment bytes stay behind")
        expect(vm.pendingAttachments.isEmpty, "nothing staged for the next message")
        expect(FileManager.default.fileExists(atPath: picked.path), "the file she picked stays")
    }
}

@MainActor private final class ClearJobRig {
    let root: URL
    let store: ConversationStore
    let jobs = HeldJob()
    let vm: ChatViewModel

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-g12-jobs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ConversationStore(directory: root.appendingPathComponent("conversations"))
        vm = ClearJobRig.build(store: store, jobs: jobs, chat: FakeChatProvider(), attachments: nil)
    }

    func makeVM(
        chat: any ChatProvider, attachments: (any AttachmentStoring)? = nil,
        parentTools: (any ParentToolExecuting)? = nil, approvals: (any ApprovalsProvider)? = nil
    ) -> ChatViewModel {
        ClearJobRig.build(
            store: store, jobs: jobs, chat: chat, attachments: attachments,
            parentTools: parentTools, approvals: approvals)
    }

    func startJob() -> Task<Void, Never> {
        let vm = vm
        let jobs = jobs
        return Task { @MainActor in
            await vm.runJob(
                preface: "", handoff: Handoff(goal: "ordenar", context: ""), submitter: jobs)
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    private static func build(
        store: ConversationStore, jobs: HeldJob, chat: any ChatProvider,
        attachments: (any AttachmentStoring)?,
        parentTools: (any ParentToolExecuting)? = nil, approvals: (any ApprovalsProvider)? = nil
    ) -> ChatViewModel {
        let vm = ChatViewModel(
            chat: chat, secrets: TestSecretStore([.openAI: "sk-test"]),
            store: store, config: .default, jobSubmitter: jobs, attachments: attachments,
            parentTools: parentTools, approvals: approvals)
        vm.onAppear()
        return vm
    }
}

/// A job that stays up until the test lets it go, and keeps talking after it
/// was told to stop: the way a process that is slow to die behaves.
private final class HeldJob: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var sink: AsyncStream<JobEvent>.Continuation?
    private var gate: CheckedContinuation<JobResult, Error>?
    private var stopped = false

    var started: Bool { lock.withLock { gate != nil } }
    var cancelled: Bool { lock.withLock { stopped } }

    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                sink = events
                gate = continuation
            }
        }
    }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, as: JobID.mint(), events: events)
    }

    func emit(_ event: JobEvent) {
        _ = lock.withLock { sink }?.yield(event)
    }

    func finish(_ result: Result<JobResult, Error>) {
        let held = lock.withLock { () -> CheckedContinuation<JobResult, Error>? in
            defer { gate = nil }
            return gate
        }
        held?.resume(with: result)
    }

    func cancel() async { lock.withLock { stopped = true } }
    func cancel(job id: JobID) async { await cancel() }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

/// The stream opens and says nothing until `release()`.
private final class HeldChat: ChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var held: AsyncThrowingStream<ChatDelta, Error>.Continuation?
    private let deltas: [ChatDelta]

    init(releasing deltas: [ChatDelta]) { self.deltas = deltas }

    var started: Bool { lock.withLock { held != nil } }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in lock.withLock { held = continuation } }
    }

    func release() {
        let continuation = lock.withLock { held }
        for delta in deltas { continuation?.yield(delta) }
        continuation?.finish()
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

/// The first request hands off at once; each later one stays open until
/// `release(call:)`, like a model still thinking.
private final class TurnScriptChat: ChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var held: [Int: AsyncThrowingStream<ChatDelta, Error>.Continuation] = [:]
    private var count = 0
    private let first: [ChatDelta]
    private let then: [ChatDelta]

    init(first: [ChatDelta], then: [ChatDelta]) {
        self.first = first
        self.then = then
    }

    var calls: Int { lock.withLock { count } }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        let index = lock.withLock { () -> Int in
            defer { count += 1 }
            return count
        }
        return AsyncThrowingStream { continuation in
            if index == 0 {
                for delta in first { continuation.yield(delta) }
                continuation.finish()
            } else {
                lock.withLock { held[index] = continuation }
            }
        }
    }

    func release(call: Int) {
        let continuation = lock.withLock { held[call] }
        for delta in then { continuation?.yield(delta) }
        continuation?.finish()
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                waiting = continuation
                lock.unlock()
            }
        }
    }

    func open() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            opened = true
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume()
    }
}

/// Without `holdsBound`, the first call answers with a card at once and the
/// second stays running until `release()`. With it, the gate stops at `bound`.
private final class RoundTools: ParentToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = OneShotGate()
    private let holdsBound: Bool
    private let gated: Bool
    private var runs = 0
    private var parked = false
    private var grants = 0

    /// `gated` asks for approval without holding `bound`.
    init(holdsBound: Bool, gated: Bool = false) {
        self.holdsBound = holdsBound
        self.gated = gated
    }

    var grantedCount: Int { lock.withLock { grants } }
    func granted(_ request: ApprovalRequest) { lock.withLock { grants += 1 } }

    var executed: Int { lock.withLock { runs } }
    var boundStarted: Bool { lock.withLock { parked } }

    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }

    func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        holdsBound || gated
            ? ApprovalRequest(requestId: "r1", toolName: call.name, summary: "x", inputJSON: "{}")
            : nil
    }

    func bound(_ request: ApprovalRequest) async -> ApprovalRequest {
        guard holdsBound else { return request }
        lock.withLock { parked = true }
        await gate.wait()
        return request
    }

    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        let index = lock.withLock { () -> Int in
            runs += 1
            return runs
        }
        if index == 1, !holdsBound, !gated {
            let pin = LocationsBlock.Location(name: "Cafe", lat: 19.4, lng: -99.1)
            return ParentToolOutcome(
                ok: true, output: "found 1",
                card: Card(payload: .locations(LocationsBlock(locations: [pin])), source: .tool),
                tool: name)
        }
        if !holdsBound, !gated { await gate.wait() }
        return ParentToolOutcome(ok: true, output: "done", tool: name)
    }

    func release() { gate.open() }
}

/// Answers yes, optionally parking inside `remembered` or `request` until
/// `release()`, and counts the asks.
private final class ScriptedApprovals: ApprovalsProvider, @unchecked Sendable {
    enum Hold { case nothing, remembered, request }

    private let lock = NSLock()
    private let gate = OneShotGate()
    private let hold: Hold
    private let memory: Bool?
    private var asked = 0
    private var requests = 0

    init(holds hold: Hold, remembers memory: Bool?) {
        self.hold = hold
        self.memory = memory
    }

    var rememberedCalls: Int { lock.withLock { asked } }
    var requestCalls: Int { lock.withLock { requests } }
    func release() { gate.open() }

    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        lock.withLock { requests += 1 }
        if hold == .request { await gate.wait() }
        return ApprovalResponse(requestId: approval.requestId, approved: true, remember: false)
    }

    func resolve(requestId: String, approved: Bool) async -> Bool { true }

    func remembered(_ approval: ApprovalRequest) async -> Bool? {
        lock.withLock { asked += 1 }
        if hold == .remembered { await gate.wait() }
        return memory
    }
}
