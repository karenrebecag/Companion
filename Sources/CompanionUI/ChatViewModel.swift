import CompanionCore
import Foundation
import Observation

/// How a message enters the model's memory, when that differs from how the
/// reader sees it. The thread and the model's history used to be one array,
/// and their requirements are opposite: the reader wants the whole report, the
/// model wants a bounded, correctly attributed trace of it.
public struct Recall: Sendable, Equatable {
    public var role: TurnRole
    public var content: String
    public var toolCalls: [ToolCallRef]
    public var toolCallID: String?

    public init(
        role: TurnRole,
        content: String,
        toolCalls: [ToolCallRef] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }
}

public struct ChatMessage: Identifiable, Equatable {
    public let id: UUID
    public var role: TurnRole?
    public var isStatus: Bool
    public var text: String
    public var attachments: [AttachmentRef]
    /// Painted from its own channel, not parsed out of the text. A card that
    /// is here never passed through the model.
    public var card: Card?
    /// nil means "remember me as you read me", which is every ordinary
    /// message and therefore changes nothing for them.
    public var recall: Recall?

    public init(
        id: UUID = UUID(),
        role: TurnRole? = nil,
        isStatus: Bool = false,
        text: String,
        attachments: [AttachmentRef] = [],
        card: Card? = nil,
        recall: Recall? = nil
    ) {
        self.id = id
        self.role = role
        self.isStatus = isStatus
        self.text = text
        self.attachments = attachments
        self.card = card
        self.recall = recall
    }
}

@Observable
@MainActor
public final class ChatViewModel: ConversationPresenting {
    public internal(set) var needsOnboarding = true
    /// How the launch resolved. `needsOnboarding` stays true until this
    /// settles, so the root never paints the thread and takes it back.
    public internal(set) var startup: StartupState = .probing
    public internal(set) var messages: [ChatMessage] = []
    public private(set) var streaming = ""
    public private(set) var busy = false
    public private(set) var queued: [String] = []
    public internal(set) var pendingAttachments: [AttachmentRef] = []
    public var dropTargeted = false
    public private(set) var busySince: Date?
    /// The session's state (Wave 12a): kind, job, sheet queue. This model
    /// sends events into it and paints from it; it never writes it.
    public let session: SessionModel
    /// Set by the brake so the job's own ending knows it was stopped rather
    /// than broken.
    var cancelledJob = false

    public var folderName: String?

    public var folderLabel: String? {
        folderName
            ?? WorkdirPreference.label
            ?? config.workdir.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public func setFolder(_ path: String) {
        guard WorkdirPreference.isAllowed(path) else { return }
        WorkdirPreference.stored = path
        folderName = WorkdirPreference.label
    }

    /// Asked instead of comparing the label: a translated string deciding
    /// whether a button is enabled breaks the moment the language changes.
    public var hasStoredAttachments: Bool {
        (attachments?.storedBytes() ?? 0) > 0
    }

    public var attachmentsStorageLabel: String {
        let bytes = attachments?.storedBytes() ?? 0
        if bytes <= 0 { return Localized.string("settings.storage.empty") }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    public func purgeStoredAttachments() {
        attachments?.purge()
        pendingAttachments = []
    }
    public private(set) var recents: [ConversationMeta] = []
    /// The task Follow up handed to the island (spec 16j §8); the next turn
    /// continues it.
    public var followUp: String?
    public internal(set) var errorText: String?
    public var draft = ""
    public var onboardingKey = ""
    public private(set) var onboardingBusy = false

    private let chat: any ChatProvider
    let secrets: any SecretStore
    private let store: any ConversationStoring
    private let config: Config
    /// Spec 15d §5: while the user's words are written to disk, the window
    /// and the island say so.
    public var debugTranscripts: Bool { config.debugTranscripts }
    let startupProbe: (any StartupProbing)?
    /// The local path this user accepted, held in memory so a stale
    /// preference can never unlock the app on its own: it only counts once
    /// the probe has seen that path alive in THIS launch.
    var acceptedLocal: LocalPath?
    var probeTask: Task<Void, Never>?
    let jobSubmitter: (any JobSubmitter)?
    public let notices: NoticeCenter
    let attachments: (any AttachmentStoring)?
    /// The parent's hands (Wave 10b): what the turn does itself, no job.
    private let parentTools: (any ParentToolExecuting)?
    /// What the app perceives around the turn (Wave 10a). Sensed for the
    /// current turn only; the thread never shows it, the store never keeps it.
    private let sensor: (any ContextSensing)?
    /// Probed at launch and shown in Settings; the sensor reads it per turn.
    public let accessibility: (any AccessibilityChecking)?
    public let screenRecording: (any ScreenRecordingChecking)?
    /// Where `open_url` waits for the sheet (Wave 10c 3D): the same actor
    /// the specialist's permissions go through.
    let approvals: (any ApprovalsProvider)?
    /// A safety, not a goal: normal use is one or two rounds.
    static let maxParentRounds = ParentToolCopy.maxRounds
    var conversationId = UUID().uuidString
    private var inFlight: Task<Void, Never>?
    /// The thread's own clock (Wave 15a): the last write, `persist()` or
    /// `restore()`; nil while the thread is empty. Ephemeral rollover reads
    /// this, never a timer.
    var lastActivity: Date?
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void

    public init(
        chat: any ChatProvider,
        secrets: any SecretStore,
        store: any ConversationStoring,
        config: Config,
        jobSubmitter: (any JobSubmitter)? = nil,
        notices: NoticeCenter = NoticeCenter(),
        attachments: (any AttachmentStoring)? = nil,
        startupProbe: (any StartupProbing)? = nil,
        parentTools: (any ParentToolExecuting)? = nil,
        sensor: (any ContextSensing)? = nil,
        accessibility: (any AccessibilityChecking)? = nil,
        screenRecording: (any ScreenRecordingChecking)? = nil,
        approvals: (any ApprovalsProvider)? = nil,
        session: SessionModel? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.chat = chat
        self.session = session ?? SessionModel(jobs: jobSubmitter, approvals: approvals)
        self.parentTools = parentTools
        self.sensor = sensor
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.approvals = approvals
        self.secrets = secrets
        self.store = store
        self.config = config
        self.startupProbe = startupProbe
        self.jobSubmitter = jobSubmitter
        self.notices = notices
        self.attachments = attachments
        self.now = now
        self.log = log
        self.folderName = WorkdirPreference.label
            ?? config.workdir.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public func toast(_ text: String, level: NoticeLevel = .info) {
        notices.toast(text, level: level)
    }

    public func submitOnboarding() async {
        guard !onboardingBusy else { return }
        let key = onboardingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            errorText = ChatCopy.emptyKey
            return
        }
        // A pasted URL or a truncation is answerable here: sending it out
        // buys the same rejection two seconds later and blames the key.
        if !APIKeyShape.looksPlausible(key) {
            errorText = ChatCopy.malformedKey
            return
        }
        onboardingBusy = true
        errorText = nil
        defer { onboardingBusy = false }
        do {
            try await chat.verify(key, provider: .openAI)
            try secrets.write(.openAI, value: key)
            onboardingKey = ""
            startup = .premium
            needsOnboarding = false
            try loadMostRecent()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    public func changeKey() {
        abandonTurn()
        dropParentApprovals()
        queued = []
        pendingAttachments = []
        streaming = ""
        onboardingKey = ""
        errorText = nil
        // Someone already talking to a local model must not go mute for
        // touching the premium field. The door closes only if nothing is left.
        if acceptedLocal == nil { needsOnboarding = true }
    }

    public func send() {
        guard !needsOnboarding else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        draft = ""
        errorText = nil
        if busy {
            queued.append(text)
            return
        }
        startTurn(text)
    }

    public func newConversation() {
        abandonTurn()
        dropParentApprovals()
        queued = []
        pendingAttachments = []
        errorText = nil
        persist()
        conversationId = UUID().uuidString
        messages = []
        streaming = ""
        draft = ""
    }

    public func openConversation(_ id: String) {
        guard id != conversationId else { return }
        abandonTurn()
        dropParentApprovals()
        queued = []
        errorText = nil
        persist()
        do {
            guard let record = try store.load(id) else { return }
            restore(record)
            streaming = ""
            pendingAttachments = []
            recents = try store.list()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    /// A task's conversation for its detail sheet, read without switching
    /// away from the one in progress.
    public func transcript(_ id: String) -> [ChatMessage] {
        guard id != conversationId else { return messages }
        do {
            return try store.load(id).map { Self.messages(of: $0) } ?? []
        } catch {
            errorText = ChatCopy.error(error)
            return []
        }
    }

    /// Switching conversations abandons the turn in progress; Follow up
    /// waits for it instead of dropping it (code review 16j-2).
    public var canFollowUp: Bool {
        !busy && session.projection.job == nil
    }

    /// Follow up: the task becomes the conversation, and the island carries it.
    @discardableResult
    public func followUp(_ task: ConversationMeta) -> Bool {
        guard canFollowUp else { return false }
        openConversation(task.id)
        followUp = task.title
        return true
    }

    public func historyTurns() async -> [Turn] {
        rolloverIfDue()
        return windowedTurns()
    }

    /// Wave 15b-9: what the NEXT turn's clock should read. Nil for an empty
    /// thread, and nil when a rollover is due — read before it actually
    /// happens, so the stale thread's clock never appears as a tag on the
    /// fresh one about to replace it.
    public func lastInteraction() async -> Date? {
        ConversationRollover.shouldRollover(activity(), now: now()) ? nil : lastActivity
    }

    /// Raw words only, in order, no status lines: the session note must not
    /// learn which app was in front (security review 2026-09-05).
    public func memoryTurns() async -> [Turn] {
        messages.compactMap { message in
            guard !message.isStatus, let role = message.role, !message.text.isEmpty
            else { return nil }
            // A job's report is shown whole and remembered bounded; the
            // memory takes the bounded one. A user turn's recall carries the
            // compact context line, so there the painted words win.
            if let recall = message.recall, recall.role == .tool {
                return Turn(role: role, content: recall.content)
            }
            return Turn(role: role, content: message.text)
        }
    }

    public func appendUser(_ text: String) async {
        await appendUser(text, context: nil)
    }

    public func appendUser(_ text: String, context: TurnContext?) async {
        rolloverIfDue()
        messages.append(ChatMessage(
            role: .user, text: text, recall: context.map { recall(text, $0) }))
        persist()
    }

    /// Remembered as "[voice · Safari · 2 docs] text": that there WAS context,
    /// and of what kind — never the clipboard's content.
    private func recall(_ text: String, _ ctx: TurnContext) -> Recall {
        Recall(role: .user,
               content: ContextBlock.compact(ctx, language: config.language) + " " + text)
    }

    public func appendAssistant(_ text: String) async {
        // A result landing means the job is over: a live card left running
        // under the report is the app lying about what it is doing.
        finishJob()
        messages.append(ChatMessage(role: .assistant, text: text))
        persist()
    }

    public func appendStatus(_ text: String) async {
        finishJob()
        messages.append(ChatMessage(isStatus: true, text: text))
        persist()
    }

    public func showStream(_ text: String) async {
        streaming = text
    }

    public func finishStream() async {
        streaming = ""
    }

    private func startTurn(_ text: String) {
        parentTools?.beginTurn()
        rolloverIfDue()
        // 15b-9: read before the append below stamps `lastActivity` to
        // now — this turn's own arrival must not report zero seconds since
        // itself.
        let previousInteraction = lastActivity
        let staged = pendingAttachments
        pendingAttachments = []
        messages.append(ChatMessage(role: .user, text: text, attachments: staged))
        persist()
        busy = true
        busySince = Date()
        streaming = ""
        session.send(.typedSubmitted)
        let id = conversationId
        let index = messages.count - 1
        inFlight = Task { [weak self] in
            guard let self else { return }
            let history = await self.sensedHistory(
                text, messageIndex: index, previousInteraction: previousInteraction)
            await self.consume(history: history, conversationId: id, said: text)
        }
    }

    /// The full block goes in the LAST user turn of the request only; the
    /// history carries the compact line. Sensing happens after the message
    /// is on screen, so a slow Accessibility tree never delays the bubble.
    private func sensedHistory(
        _ text: String, messageIndex: Int, previousInteraction: Date?
    ) async -> [Turn] {
        guard let sensor else { return windowedTurns() }
        var ctx = await sensor.sense(config.contextChannels, budget: config.contextBudget)
        ctx.source = .typed
        // 15b-9: the thread's own clock wins over whatever the sensor
        // itself guessed.
        ctx.sinceLastTurn = previousInteraction.map { now().timeIntervalSince($0) }
        guard messages.indices.contains(messageIndex), messages[messageIndex].text == text
        else { return windowedTurns() }
        messages[messageIndex].recall = recall(text, ctx)
        var history = windowedTurns()
        if let last = history.indices.last, history[last].role == .user {
            history[last].content = ContextBlock.wrap(
                text, with: ContextBlock.render(ctx, language: config.language))
        }
        return history
    }

    private func consume(history: [Turn], conversationId id: String, said: String) async {
        guard isCurrent(id) else { return }
        var history = history
        do {
            // Up to `maxParentRounds`: stream, act on the parent's tool calls,
            // stream again with their results in the history. A handoff
            // closes the turn after the parent's actions, as does text alone.
            for round in 1 ... Self.maxParentRounds {
                let (preface, handoff, calls) = try await streamRound(history, id: id)
                guard isCurrent(id) else { return }
                streaming = ""
                guard let parentTools, !calls.isEmpty else {
                    await commit(preface: preface, handoff: handoff)
                    break
                }
                await act(preface: preface, calls: calls, said: said, using: parentTools)
                guard isCurrent(id) else { return }
                if let handoff {
                    await commit(preface: "", handoff: handoff)
                    break
                }
                if round == Self.maxParentRounds {
                    messages.append(ChatMessage(
                        isStatus: true, text: ParentToolCopy.roundCap(config.language)))
                    break
                }
                history = windowedTurns()
            }
            persist()
            endTurn()
            drain()
        } catch is CancellationError {
            guard isCurrent(id) else { return }
            streaming = ""
            endTurn()
        } catch {
            guard isCurrent(id) else { return }
            streaming = ""
            errorText = ChatCopy.error(error)
            persist()
            endTurn()
            drain()
        }
    }

    private func endTurn() {
        busy = false
        busySince = nil
        session.send(.typedReplyFinished)
    }

    /// A turn cancelled by a switch never reaches `endTurn` (its guards see
    /// a stale conversation id), so the session is told here or it keeps
    /// painting a turn that no longer exists (code review 2026-09-06).
    private func abandonTurn() {
        inFlight?.cancel()
        inFlight = nil
        if busy { endTurn() }
    }

    private func streamRound(
        _ history: [Turn], id: String
    ) async throws -> (preface: String, handoff: Handoff?, calls: [ToolCallRef]) {
        var preface = ""
        var handoff: Handoff?
        var calls: [ToolCallRef] = []
        let tools = (parentTools?.specs(config.language) ?? [])
            + [.delegate(config.language)]
        for try await delta in chat.stream(history, tools: tools) {
            guard isCurrent(id) else { throw CancellationError() }
            switch delta {
            case .text(let chunk):
                if preface.isEmpty { session.send(.typedReplyStreaming) }
                preface += chunk
                streaming = preface
            case .handoff(let value):
                handoff = value
            case .toolCalls(let round):
                // Anything the parent cannot do itself is the specialist's
                // and only ever arrives as a handoff.
                calls += round.filter { parentTools?.handles($0.name) == true }
            }
        }
        return (preface, handoff, calls)
    }

    /// The call survives in the history the way the delegate call does (9d):
    /// the assistant turn carries the calls, one status line per result
    /// answers them with the same id. The thread reads what the app did by
    /// itself; the model reads what the tool returned.
    private func act(
        preface: String, calls: [ToolCallRef], said: String,
        using tools: any ParentToolExecuting
    ) async {
        let recall = Recall(role: .assistant, content: preface, toolCalls: calls)
        let targets = calls.map(ParentTool.target(of:))
        if !preface.isEmpty {
            messages.append(ChatMessage(role: .assistant, text: preface, recall: recall))
        } else {
            messages.append(ChatMessage(
                isStatus: true,
                text: ParentToolCopy.acting(targets, config.language),
                recall: recall))
        }
        session.send(.parentActing(targets: targets))
        defer { session.send(.parentActed) }
        // Every tool answer first, cards after: a provider validates that
        // the answers to one assistant turn arrive together, and an assistant
        // turn wedged between them is a rejected request.
        var cards: [Card] = []
        for call in calls {
            // A turn that stopped being current must not keep opening things.
            guard !Task.isCancelled else { break }
            // A URL the user did not say waits for the sheet (10c 3D).
            let outcome: ParentToolOutcome
            if let denied = await gate(call, said: said, tools: tools) {
                outcome = denied
            } else {
                // The sheet may have outlived the conversation: a turn that
                // was switched away must not open or paint anything.
                guard !Task.isCancelled else { break }
                outcome = await tools.execute(name: call.name, argumentsJSON: call.arguments)
            }
            guard !Task.isCancelled else { break }
            messages.append(ChatMessage(
                isStatus: true,
                text: ParentToolCopy.status(call.name, outcome, config.language),
                recall: Recall(role: .tool, content: outcome.output, toolCallID: call.id)))
            if let card = outcome.card { cards.append(card) }
        }
        for card in cards {
            messages.append(ChatMessage(
                role: .assistant, text: "", card: card,
                recall: Recall(role: .assistant, content: ChatCopy.cardShown(card))))
        }
        persist()
    }

    /// Nil = go ahead. Otherwise the denial that answers the model: from the
    /// session's memory without a sheet, from the sheet, or — with no actor
    /// to ask — closed.
    private func gate(
        _ call: ToolCallRef, said: String, tools: any ParentToolExecuting
    ) async -> ParentToolOutcome? {
        guard let request = tools.approval(for: call, said: said) else { return nil }
        let denied = ParentToolOutcome.failed(
            .deniedByUser(config.language), target: ParentTool.target(of: call),
            tool: call.name)
        guard let approvals else { return denied }
        if let decision = await approvals.remembered(request) {
            messages.append(ChatMessage(
                isStatus: true, text: ChatCopy.approvalRemembered(call.name, approved: decision)))
            if decision { tools.granted(request) }
            return decision ? nil : denied
        }
        session.send(.job(.approvalRequested(request)))
        messages.append(ChatMessage(isStatus: true, text: ChatCopy.approvalPending))
        let response = await approvals.request(request)
        session.send(.approvalSettled(requestId: request.requestId))
        guard response.approved else { return denied }
        tools.granted(request)
        return nil
    }

    /// The parent's own requests die with the turn that asked: leaving one
    /// on the sheet would answer it into another conversation. A job's
    /// request outlives the switch, like the job does.
    private func dropParentApprovals() {
        let parents = session.projection.approvalQueue
            .filter { ParentTool(rawValue: $0.toolName) != nil }
        for request in parents {
            session.send(.approvalDropped(requestId: request.requestId))
        }
    }

    private func commit(preface: String, handoff: Handoff?) async {
        if let handoff, let submitter = jobSubmitter {
            await runJob(preface: preface, handoff: handoff, submitter: submitter)
            return
        }

        // Fallback: show status if no runner
        if let handoff {
            if !preface.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: preface))
            }
            messages.append(ChatMessage(
                isStatus: true, text: ChatCopy.handoffUnavailable(handoff)))
            return
        }

        if !preface.isEmpty {
            messages.append(ChatMessage(role: .assistant, text: preface))
        }
    }

    /// Test seam: the history the provider would receive, which is now a
    /// different thing from what the thread shows.
    func historyForTests() -> [Turn] { windowedTurns() }

    private func drain() {
        guard !needsOnboarding, !queued.isEmpty else { return }
        startTurn(queued.removeFirst())
    }

    private func isCurrent(_ id: String) -> Bool {
        conversationId == id && !Task.isCancelled
    }

    func windowedTurns() -> [Turn] {
        let turns: [Turn] = messages.compactMap { message in
            // A status line carries no memory of its own — unless it was given
            // one, which is how the delegate call survives in the history.
            if let recall = message.recall {
                return Turn(
                    role: recall.role, content: recall.content,
                    attachments: message.attachments,
                    toolCalls: recall.toolCalls,
                    toolCallID: recall.toolCallID)
            }
            if message.isStatus { return nil }
            guard let role = message.role else { return nil }
            // What the assistant said goes through the same filter as a
            // specialist report: card payloads are interface, not context, and
            // the chat layer can emit them too now.
            let content = role == .assistant
                ? ConversationMemory.recall(message.text)
                : message.text
            return Turn(
                role: role, content: content,
                attachments: message.attachments)
        }
        let window = max(0, config.chat.historyWindow)
        guard window > 0, turns.count > window else { return turns }
        // What falls out of the window leaves a note instead of a hole.
        let kept = Self.dropOrphanedToolTurns(Array(turns.suffix(window)))
        let dropped = Array(turns.prefix(turns.count - window))
        guard let note = ConversationMemory.compaction(
            of: dropped, language: config.language)
        else { return kept }
        return [note] + kept
    }

    /// The window can fall between a delegate call and the result that answers
    /// it. A tool turn whose call was cut away is not merely useless: the
    /// provider rejects the whole request over it, so the turn after a long
    /// conversation would fail outright.
    static func dropOrphanedToolTurns(_ turns: [Turn]) -> [Turn] {
        var known: Set<String> = []
        var kept: [Turn] = []
        for turn in turns {
            for call in turn.toolCalls { known.insert(call.id) }
            if turn.role == .tool {
                guard let id = turn.toolCallID, known.contains(id) else {
                    continue
                }
            }
            kept.append(turn)
        }
        return kept
    }

    func loadMostRecent() throws {
        recents = try store.list()
        guard let meta = recents.first, let record = try store.load(meta.id) else {
            conversationId = UUID().uuidString
            messages = []
            lastActivity = nil
            return
        }
        restore(record)
        rolloverIfDue()
    }

    private func restore(_ record: ConversationRecord) {
        conversationId = record.id
        lastActivity = record.updatedAt
        messages = Self.messages(of: record)
    }

    private static func messages(of record: ConversationRecord) -> [ChatMessage] {
        record.messages.map { item in
            if item.role == "status" {
                return ChatMessage(isStatus: true, text: item.text)
            }
            return ChatMessage(role: TurnRole(rawValue: item.role), text: item.text)
        }
    }

    func persist() {
        let stored = messages.map { message -> ConversationMessage in
            let role = message.isStatus ? "status" : (message.role?.rawValue ?? "assistant")
            return ConversationMessage(role: role, text: message.text)
        }
        guard !stored.isEmpty else { return }
        let title = messages.first { $0.role == .user }
            .map { String($0.text.prefix(48)) }
            ?? Localized.string("thread.untitled")
        let timestamp = now()
        lastActivity = timestamp
        let record = ConversationRecord(
            id: conversationId, title: title, updatedAt: timestamp, messages: stored)
        do {
            try store.save(record)
            recents = try store.list()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    /// What the policy needs to know right now: the thread's own clock plus
    /// the guards nothing here must strand in another conversation.
    private func activity() -> ConversationActivity {
        ConversationActivity(
            lastActivity: lastActivity,
            turnInFlight: busy,
            jobRunning: session.projection.job != nil,
            approvalsPending: !session.projection.approvalQueue.isEmpty,
            liveRealtime: session.projection.pipeline == .realtime
                && (session.projection.voice == .live || session.projection.voice == .muted))
    }

    private func rolloverIfDue() {
        guard ConversationRollover.shouldRollover(activity(), now: now()) else { return }
        rollOver()
    }

    /// Wave 15a: past the idle window with nothing open, the stale thread is
    /// archived (it is already on disk, untouched) and a blank one starts.
    /// Never calls `persist()` — that would re-stamp the old thread's
    /// `updatedAt` and it would never expire.
    private func rollOver() {
        conversationId = UUID().uuidString
        messages = []
        streaming = ""
        lastActivity = nil
        log("conversation: rolled over after idle window")
    }

    /// `applicationDidBecomeActive` (§10 of the spec): a voice turn already
    /// under way decides this for itself once it reaches `historyTurns()` or
    /// `appendUser`, so this entry point only admits a resting chrome.
    public func rolloverIfIdle() {
        guard session.projection.kind == .idle || session.projection.kind == .hover else { return }
        rolloverIfDue()
    }
}
