import CompanionCore
import Foundation

/// The turn engine: send a request, stream it, let the parent act on tool
/// calls, commit the result. Split out of ChatViewModel when it crossed the
/// 400-line gate: the model's public surface stays in one file, the mechanics
/// of a single turn stay in this one.
extension ChatViewModel {
    func startTurn(_ text: String, origin: MessageOrigin = .typed, mentions: [Mention] = []) {
        parentTools?.beginTurn()
        // 16k-3: the words decide which connected app's tools travel this
        // round — specs() is rebuilt per request further down this turn.
        // A pick's label is the model's text, not her words: it must not
        // name an app for the tool scope nor stand as consent for a host
        // (16m-6 security). Typed words still do both.
        let said = origin == .choice ? "" : text
        // 16q-2: a card turn reaches every connected app like any turn, but
        // through its own entry so the label can never be passed as words.
        if origin == .choice { parentTools?.noteChoiceTurn() } else { parentTools?.noteTurn(said) }
        rolloverIfDue()
        // 15b-9: read before the append below stamps `lastActivity` to
        // now — this turn's own arrival must not report zero seconds since
        // itself.
        let previousInteraction = lastActivity
        // A pick is not a send of what is staged: the chips stay in the
        // composer for the message she actually writes.
        let staged = origin == .choice ? [] : pendingAttachments
        if origin == .typed { pendingAttachments = [] }
        messages.append(ChatMessage(role: .user, text: text, attachments: staged, origin: origin, mentions: mentions))
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
                text, messageIndex: index, previousInteraction: previousInteraction, origin: origin)
            await self.consume(history: history, conversationId: id, said: said)
        }
    }

    /// The full block goes in the LAST user turn of the request only; the
    /// history carries the compact line. Sensing happens after the message
    /// is on screen, so a slow Accessibility tree never delays the bubble.
    private func sensedHistory(
        _ text: String, messageIndex: Int, previousInteraction: Date?, origin: MessageOrigin
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
            let marked = origin == .choice ? ChoiceOrigin.mark(text, language: config.language) : text
            let said = MentionContext.wrap(marked, mentions: messages[messageIndex].mentions, language: config.language)
            history[last].content = ContextBlock.wrap(
                said, with: ContextBlock.render(ctx, language: config.language))
            // The facts are in the request now: only here are they spent.
            sensor.acknowledgeIslandEvents(through: ctx.islandEventsThrough)
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
                    if preface.isEmpty, handoff == nil {
                        log("chat: round returned neither text nor calls")
                    }
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
            // The banner alone dies with the next conversation: a turn every
            // provider refused ended looking "completed", question simply
            // unanswered (live 2026-09-28). The thread keeps the record.
            messages.append(ChatMessage(isStatus: true, text: ChatCopy.error(error), isFailure: true))
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
    func abandonTurn() {
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
                for call in round where parentTools?.handles(call.name) != true {
                    // A dropped call is a decision worth a trace: a real
                    // tool falling here means the runner and the model
                    // disagree about the list (QA 16k-3). The name is
                    // model output — capped and stripped of control
                    // scalars so it cannot forge log lines.
                    let shown = call.name.unicodeScalars.prefix(64)
                        .filter { !CharacterSet.controlCharacters.contains($0) }
                    log("chat: dropped tool call \(String(String.UnicodeScalarView(shown)))")
                }
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
        var proven: [ReceiptLine] = []
        for call in calls {
            // A turn that stopped being current must not keep opening things.
            guard !Task.isCancelled else { break }
            // A URL the user did not say waits for the sheet (10c 3D).
            let outcome: ParentToolOutcome
            if let denied = await gate(call, said: said, tools: tools) {
                outcome = denied
            } else {
                // The sheet may have outlived the conversation: a turn that
                // was switched away must not open or paint anything, nor
                // leave the yes it got behind.
                guard !Task.isCancelled else {
                    tools.withdraw(call)
                    break
                }
                outcome = await tools.execute(name: call.name, argumentsJSON: call.arguments)
            }
            guard !Task.isCancelled else { break }
            messages.append(ChatMessage(
                isStatus: true,
                text: ParentToolCopy.status(call.name, outcome, config.language),
                recall: Recall(role: .tool, content: outcome.output, toolCallID: call.id)))
            if let card = outcome.card { cards.append(card) }
            if let line = ReceiptProof.entry(tool: call.name, outcome: outcome, language: config.language) {
                proven.append(line)
            }
        }
        if let receipt = ActionReceipt(entries: proven) { session.send(.receipt(receipt)) }
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
        guard let asked = tools.approval(for: call, said: said) else { return nil }
        let request = await tools.bound(asked)
        // A remembered "no" outranks the shortcut (see ParentToolGuard).
        if await tools.actsWithoutSheet(call), await approvals?.remembered(request) != false { return nil }
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
    func dropParentApprovals() {
        let parents = session.projection.approvalQueue
            .filter { ParentTool.ownsRequest($0.toolName) }
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

    private func drain() {
        guard !needsOnboarding, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        startTurn(next.text, origin: next.origin, mentions: next.mentions)
    }

    private func isCurrent(_ id: String) -> Bool {
        conversationId == id && !Task.isCancelled
    }
}
