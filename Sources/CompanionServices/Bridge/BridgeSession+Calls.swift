import CompanionCore
import Foundation

/// The call half of `BridgeSession`: dedup by request id, the per-call and
/// session-open sheets, and the wire replies. Split out so the actor file
/// keeps to the connection lifecycle; it shares the actor's state, which is
/// internal (not public) for that reason.
extension BridgeSession {
    // MARK: - call

    /// A call's reply with what it means to the ledger, decided where the
    /// reply is built rather than guessed from its text.
    struct Handled {
        let reply: String
        let close: Bool
        let outcome: BridgeRequestLedger.Outcome

        static func answered(_ line: String, close: Bool = false) -> Handled {
            Handled(reply: line, close: close, outcome: .answered(line))
        }

        static func refused(_ line: String, close: Bool = false) -> Handled {
            Handled(reply: line, close: close, outcome: .refused)
        }

        static let dropped = Handled(reply: "", close: false, outcome: .dropped)
    }

    /// M8a: an id already used on this connection never runs a second time,
    /// whatever the tool: it gets the first answer back, or `busy` while the
    /// first is still running. Only a call that reached its tool is
    /// remembered: one refused up front (no session, over budget, unknown
    /// tool) did nothing, so the same id may be sent again once that is fixed.
    func handleDeduplicated(id: Int, call: BridgeCall, mine: Int) async -> (String, Bool) {
        switch ledger.begin(id) {
        case .replay(let reply):
            Log.bridge("call id \(id) repeated; first answer sent again, nothing executed")
            return (reply, false)
        case .tooLargeToReplay:
            Log.bridge("call id \(id) repeated; its first answer was too large to keep, nothing executed")
            let line = errorLine(
                id, BridgeCode.replyTooLarge, "the answer to request \(id) was too large to send again")
            return (line, false)
        case .inFlight:
            return (errorLine(id, BridgeCode.busy, "request \(id) is already running"), false)
        case .fresh:
            break
        }
        let handled = await handleCall(id: id, call: call, mine: mine)
        // A newer connection owns the ledger now; this one is not its to edit.
        guard mine == epoch else { return (handled.reply, handled.close) }
        ledger.finish(id, outcome: handled.outcome)
        return (handled.reply, handled.close)
    }

    private func handleCall(id: Int, call: BridgeCall, mine: Int) async -> Handled {
        // Allowlist first: a tool nobody named for the bridge must not even
        // be admitted to exist, whatever the runner behind it can do.
        guard BridgeScope.allows(call.name) else {
            return .refused(errorLine(id, BridgeCode.unknownTool, "unknown tool: \(call.name)"))
        }
        guard tools.handles(call.name) else {
            if let reason = tools.unavailability(for: call.name) {
                return .refused(errorLine(id, reason, unavailableMessage(reason, tool: call.name)))
            }
            return .refused(errorLine(id, BridgeCode.unknownTool, "unknown tool: \(call.name)"))
        }
        let verdict = policy.admit(tool: call.name, now: now())
        onState(policy.state)
        switch verdict {
        case .reject(let code):
            return .refused(errorLine(id, code, rejectionMessage(code, tool: call.name)))
        case .proceed:
            return await performCall(id: id, call: call, mine: mine)
        case .needsApproval:
            return await handleSessionApproval(id: id, call: call, mine: mine)
        }
    }

    /// §9-5: no separate sheet or "1 hour" choice — the first `call` on a
    /// freshly `listed` session goes through the same sheet and `Approvals`
    /// actor the chat and terminal gates use ("wants to use your hands" /
    /// Allow / Deny). *Allow* opens the session for this connection only.
    ///
    /// Security review 2026-09-28 (HIGH): this request is deliberately
    /// never remembered (`ApprovalKey.from` has no case for
    /// `"bridge_session"`, on purpose — see `ApprovalMemoryTests`). `client`
    /// here is a name `hello` put on the wire, not an identity: any
    /// same-uid process that read `bridge.token` could send
    /// `client: "claude-code"` and, if this were ever remembered, inherit
    /// the hands with no sheet. One sheet per connection, every time,
    /// regardless of "remember" on the sheet.
    private func handleSessionApproval(id: Int, call: BridgeCall, mine: Int) async -> Handled {
        let request = ApprovalRequest(
            requestId: UUID().uuidString, toolName: BridgePolicy.sessionApprovalTool,
            summary: BridgeCopy.sheetTitle(language()), inputJSON: sessionApprovalInputJSON())
        // Seen live 2026-09-28: this whole round trip resolved with no
        // trace, and only the shim's error said anything happened. The
        // request and its resolution are the two lines that tell a silent
        // auto-deny apart from a user's "no".
        Log.bridge("session approval requested by \(loggableName(client))")
        let parkedSheet = parked
        let answer = await guardian.answer(request, parked: { parkedSheet.park($0, owner: mine) })
        if answer == .refused { return refuseSheet(id: id) }
        let withdrawn = parked.settle(request)
        let approved = answer == .approved
        Log.bridge("session approval resolved approved=\(approved) withdrawn=\(withdrawn)")
        // A newer connection took over while the sheet was up: this answer
        // belongs to a connection that is gone and must not touch the state.
        guard mine == epoch else { return .dropped }
        guard approved else {
            policy.denied()
            if countsAsDenial(answer, withdrawn: withdrawn) { policy.recordDenial(now: now()) }
            onState(policy.state)
            if policy.isCoolingDown(now: now()) {
                Log.bridge("cooling down after repeated denials")
                return .refused(
                    errorLine(id, BridgeCode.coolingDown, rejectionMessage(BridgeCode.coolingDown, tool: nil)), close: true)
            }
            return .refused(errorLine(id, BridgeCode.deniedByUser, "the user denied the hands"))
        }
        // M4 (security review 2026-09-28): the peer may have left (a plain
        // EOF, not "Stop hands") while `guardian.ask` was awaiting the
        // sheet. Acting now would `beginTurn()` and execute on a connection
        // nobody is reading from any more — the reply would be dropped
        // anyway, so there is nothing to gain and a live app to protect.
        // `current?.isOpen ?? true`: `handle(line:)` is also driven directly
        // in tests without ever calling `serve(_:)` — no wired connection to
        // check is not the same thing as a connection that went away, so a
        // nil `current` proceeds exactly as it always did.
        guard current?.isOpen ?? true else {
            policy.disconnected()
            onState(policy.state)
            Log.bridge("session approved after the client left; nothing executed")
            return .dropped
        }
        policy.approved(until: nil, now: now())
        onState(policy.state)
        Log.bridge("session open for \(loggableName(client))")
        tools.beginTurn()
        let verdict = policy.admit(tool: call.name, now: now())
        onState(policy.state)
        switch verdict {
        case .reject(let code):
            return .refused(errorLine(id, code, rejectionMessage(code, tool: call.name)))
        case .needsApproval:
            return .refused(errorLine(id, BridgeCode.busy, "unexpected state"))
        case .proceed:
            return await performCall(id: id, call: call, mine: mine)
        }
    }

    /// The per-call gate (destructive click, Return in a terminal, `type_text`
    /// always) runs with `said: ""`: nothing was spoken, so anything 15g/16
    /// would have trusted a spoken word for goes to the sheet instead.
    private func performCall(id: Int, call: BridgeCall, mine: Int) async -> Handled {
        markActive()
        defer { markActive() }
        let ref = ToolCallRef(id: UUID().uuidString, name: call.name, arguments: call.argumentsJSON)
        let parkedSheet = parked
        let verdict = await guardian.verdict(
            ref, said: "", language: language(), tools: tools, parked: { parkedSheet.park($0, owner: mine) })
        let withdrawn = parked.settleCurrent(owner: mine)
        guard mine == epoch else {
            tools.withdraw(ref)
            return .dropped
        }
        if verdict.answer == .refused { return refuseSheet(id: id) }
        if let denied = verdict.denial {
            let counts = verdict.answer.map { countsAsDenial($0, withdrawn: withdrawn) } ?? true
            return denyCall(id: id, denied, counts: counts)
        }
        // Same M4 guard as the session sheet: the yes may have landed after
        // the peer left, and there is nobody to answer or to act for.
        guard current?.isOpen ?? true else {
            tools.withdraw(ref)
            Log.bridge("call approved after the client left; nothing executed")
            return .dropped
        }
        let outcome = await tools.execute(name: call.name, argumentsJSON: call.argumentsJSON)
        if outcome.ok { onCall(call.name) }
        if outcome.ok, BridgePolicy.writeTools.contains(call.name) {
            onAction(call.name)
        }
        // Never the arguments or the output — name, outcome, target, size.
        Log.bridge("call \(call.name) ok=\(outcome.ok) target=\(outcome.target) "
            + "chars=\(call.argumentsJSON.utf8.count)")
        return .answered(BridgeCodec.encode(.call(id: id, BridgeCallResult(outcome))))
    }

    /// The sheets-per-window limit is spent: no sheet was shown and the
    /// session is shut off, with the same code and close as the cool-down.
    private func refuseSheet(id: Int) -> Handled {
        Log.bridge("sheet limit reached; session shut off")
        policy.stop()
        onState(policy.state)
        return .refused(
            errorLine(id, BridgeCode.coolingDown,
                      BridgeMessages.sheetLimit(waitSeconds: parked.secondsUntilRoom())), close: true)
    }

    /// Only the user refusing counts: "Corte" (withdrawn by us) and a sheet
    /// nobody answered before its deadline are not refusals, and counting
    /// them would lock the hands for minutes after three quiet timeouts.
    private func countsAsDenial(_ answer: ParentToolGuard.SheetAnswer, withdrawn: Bool) -> Bool {
        answer == .denied && !withdrawn
    }

    /// A per-call denial counts toward the cool-down like the session sheet:
    /// the Nth one shuts the session off and closes the connection.
    private func denyCall(id: Int, _ outcome: ParentToolOutcome, counts: Bool) -> Handled {
        if counts { policy.recordDenial(now: now()) }
        let coolingDown = policy.isCoolingDown(now: now())
        if coolingDown {
            Log.bridge("cooling down after repeated denials; session shut off")
            policy.stop()
            onState(policy.state)
        }
        return .answered(BridgeCodec.encode(.call(id: id, BridgeCallResult(outcome))), close: coolingDown)
    }

    /// Built with `JSONSerialization`, not string interpolation: the client
    /// name came off the wire and must not be able to break the JSON shape
    /// `ApprovalKey.from` parses back out.
    private func sessionApprovalInputJSON() -> String {
        do {
            var fields: [String: Any] = ["client": client]
            if let peer = current?.peer {
                fields["pid"] = Int(peer.pid)
                if !peer.path.isEmpty { fields["process"] = peer.path }
            }
            let data = try JSONSerialization.data(withJSONObject: fields)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            Log.bridge("session sheet input could not be serialized: \(error.localizedDescription)")
            return "{}"
        }
    }

    /// Wire-provided names pass through here before logging: a crafted
    /// client name must not forge log lines or spray control characters.
    func loggableName(_ name: String) -> String {
        String(name.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "." }
            .prefix(32)
            .map(Character.init))
    }

    func errorLine(_ id: Int?, _ code: String, _ message: String) -> String {
        BridgeCodec.encode(.error(id: id, BridgeErrorBody(code: code, message: message)))
    }

    private func unavailableMessage(_ code: String, tool: String) -> String {
        switch code {
        case BridgeCode.selfInFront:
            return BridgeMessages.selfInFront
        case BridgeCode.needsAccessibility:
            return BridgeMessages.needsAccessibility
        default: return "\(tool) is not available right now"
        }
    }

    /// `tool` sizes the wait for `rate_limited` (nil on hello, which is never
    /// rate limited); the session state tells an open sheet apart from another
    /// agent, which share the code `busy`.
    func rejectionMessage(_ code: String, tool: String?) -> String {
        switch code {
        case BridgeCode.busy:
            return policy.state == .awaitingApproval ? BridgeMessages.sheetOpen : BridgeMessages.anotherAgent
        case BridgeCode.paused: return BridgeMessages.paused
        case BridgeCode.rateLimited:
            let wait = tool.map { policy.secondsUntilRoom(tool: $0, now: now()) }
                ?? BridgePolicy.readTools.union(BridgePolicy.writeTools)
                    .map { policy.secondsUntilRoom(tool: $0, now: now()) }.max() ?? 0
            return BridgeMessages.rateLimited(waitSeconds: wait)
        case BridgeCode.noSession: return "no active session; send hello first"
        // The state is reachable again by hello (BridgePolicy.helloReceived), so say so: the agent
        // cannot see the denied or expired sheet that closed it.
        case BridgeCode.sessionClosed:
            return "session is closed: the user denied it, the approval sheet expired, or the hands were "
                + "stopped. Send hello again, then retry the call: it opens a new approval sheet on the Mac"
        case BridgeCode.coolingDown:
            return BridgeMessages.coolingDown(waitSeconds: policy.cooldownRemaining(now: now()))
        default: return code
        }
    }
}
