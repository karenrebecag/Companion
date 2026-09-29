import CompanionCore
import Foundation

/// Wave 17. The protocol actor: turns wire requests into `BridgePolicy`
/// decisions, approval-sheet round trips through `ParentToolGuard`, and
/// `ParentToolExecuting` calls. One instance per process, reused across
/// connections one at a time — `BridgeListener` never hands out a second
/// live connection while one is open.
///
/// Wave 20c D5 (M1): the session state belongs to ONE connection. Every
/// served connection gets a new `epoch`; anything that resumes after an
/// `await` (a sheet answered late, a gate check) drops its result when the
/// epoch moved, so a connection that went away cannot authorize the one that
/// replaced it, and a new connection always starts from `idle` (it must send
/// its own valid `hello`).
public actor BridgeSession {
    private let tools: any ParentToolExecuting
    private let guardian: ParentToolGuard
    private let token: @Sendable () -> String
    private let language: @Sendable () -> AppLanguage
    private let accessibility: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private let onState: @Sendable (BridgeState) -> Void
    /// 17-2's island chip blinks on this: fired after a successful write
    /// action (§3 "cada acción de escritura lo hace parpadear").
    private let onAction: @Sendable (String) -> Void
    private let onCall: @Sendable (String) -> Void

    private var policy = BridgePolicy()
    /// The request ids this connection has used (20c D6, M8a). Replaced with
    /// a fresh ledger wherever the connection's state is reset.
    private var ledger = BridgeRequestLedger()
    /// The client name from `hello` ("claude-code"), carried into the
    /// session-open sheet's `inputJSON` so the sheet can name who is
    /// asking. Display only — never a memory key (see `handleSessionApproval`).
    private var client = ""
    /// The connection `serve(_:)` is currently driving, so `stop()` can
    /// close it directly — the shim only reconnects when the socket drops,
    /// and `stop()` alone (just closing the session in `policy`) left the
    /// live connection open with nothing to ever tell it to reconnect.
    private var current: BridgeConnection?
    /// The sheet (session-open or per-call) the current call is waiting on,
    /// so `stop()` ("Corte"), the peer leaving, or a replacing connection can
    /// withdraw it instead of leaving it on screen and the slot held.
    private let parked: BridgeParkedSheet
    private var epoch = 0
    private let idleTimeout: TimeInterval
    private let idleCheckInterval: TimeInterval
    private var lastActivity: Date
    /// Calls and sheets being awaited right now: a session working for the
    /// peer is not idle, the sheet has its own timeout.
    private var inFlight = 0

    public init(
        tools: any ParentToolExecuting,
        guard parentGuard: ParentToolGuard,
        token: @escaping @Sendable () -> String,
        language: @escaping @Sendable () -> AppLanguage,
        accessibility: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = { Date() },
        onState: @escaping @Sendable (BridgeState) -> Void = { _ in },
        onAction: @escaping @Sendable (String) -> Void = { _ in },
        onCall: @escaping @Sendable (String) -> Void = { _ in },
        idleTimeout: TimeInterval = BridgePolicy.idleTimeout,
        idleCheckInterval: TimeInterval = BridgePolicy.idleCheckInterval
    ) {
        self.idleTimeout = idleTimeout
        self.idleCheckInterval = idleCheckInterval
        self.lastActivity = now()
        self.tools = tools
        self.guardian = parentGuard
        self.token = token
        self.language = language
        self.accessibility = accessibility
        self.now = now
        self.parked = BridgeParkedSheet(now: now)
        self.onState = onState
        self.onAction = onAction
        self.onCall = onCall
    }

    public var state: BridgeState { policy.state }

    /// Reads lines off `connection` until it closes or a reply says to close
    /// it. One call drives one connection start to finish.
    public func serve(_ connection: BridgeConnection) async {
        connection.holdSlotUntilServed()
        defer { connection.releaseSlot() }
        if let live = current, live.isOpen {
            // The listener never hands out a second live connection; if one
            // arrives anyway it must not share, or take over, the first's
            // session.
            connection.send(line: errorLine(nil, BridgeCode.busy, "another session is active"))
            connection.close()
            return
        }
        epoch += 1
        let mine = epoch
        // Synchronous, before any line of this connection is read: whatever
        // the previous connection left (an open session, a parked sheet) is
        // not this connection's.
        policy.disconnected()
        ledger = BridgeRequestLedger()
        client = ""
        current = connection
        lastActivity = now()
        onState(policy.state)
        let watchdog = Task { await self.watchIdle(mine: mine) }
        // `handle` can sit on a sheet while the peer hangs up; nothing reads
        // `lines` then, so the close has to be noticed from the side.
        let leaving = Task { await self.withdrawWhenClosed(connection, mine: mine) }
        defer {
            watchdog.cancel()
            leaving.cancel()
        }
        await withdrawPendingSheet()
        for await line in connection.lines {
            guard mine == epoch else { break }
            let (reply, close) = await handle(line: line, mine: mine)
            guard mine == epoch else { break }
            connection.send(line: reply)
            if close {
                connection.close()
                break
            }
        }
        guard mine == epoch else { return }
        current = nil
        connectionClosed()
    }

    /// Closes the live connection once it has been quiet for `idleTimeout`:
    /// the session is closed (a fresh hello and sheet are needed) and the
    /// peer sees EOF. True when it acted.
    @discardableResult
    public func expireIfIdle() -> Bool {
        guard current != nil, inFlight == 0,
              now().timeIntervalSince(lastActivity) >= idleTimeout
        else { return false }
        Log.bridge("idle timeout; session closed")
        policy.stop()
        onState(policy.state)
        current?.close()
        return true
    }

    /// A negative, NaN or infinite interval would trap in the conversion.
    private var idleCheckNanoseconds: UInt64 {
        let nanoseconds = idleCheckInterval * 1_000_000_000
        guard nanoseconds.isFinite else { return 0 }
        return UInt64(max(0, min(nanoseconds, Double(UInt64.max / 2))))
    }

    private func watchIdle(mine: Int) async {
        while !Task.isCancelled, mine == epoch {
            do {
                try await Task.sleep(nanoseconds: idleCheckNanoseconds)
            } catch {
                return
            }
            if mine == epoch, expireIfIdle() { return }
        }
    }

    private func withdrawWhenClosed(_ connection: BridgeConnection, mine: Int) async {
        for await _ in connection.closure {}
        guard !Task.isCancelled, mine == epoch else { return }
        await withdrawPendingSheet()
    }

    private func withdrawPendingSheet() async {
        guard let sheet = parked.takeForWithdrawal() else { return }
        await guardian.withdraw(sheet)
    }

    /// Only a real hello or an admitted call is activity: a peer that sends
    /// junk, a bad token or rejected calls must not hold the slot forever.
    private func markActive() {
        lastActivity = now()
    }

    /// Pure enough to test without a socket: one line in, one reply out.
    public func handle(line: String) async -> (reply: String, close: Bool) {
        await handle(line: line, mine: epoch)
    }

    private func handle(line: String, mine: Int) async -> (reply: String, close: Bool) {
        inFlight += 1
        defer { inFlight -= 1 }
        switch BridgeCodec.decode(line: line) {
        case .failure(let error):
            // Spec §3c: an oversized line closes the connection. The
            // transport cuts it first in production; this entry point is
            // the documented socket-free one, so it keeps the contract too.
            let tooLarge = error.code == BridgeCode.frameTooLarge
            return (BridgeCodec.encode(.error(id: nil, error)), tooLarge)
        case .success(.hello(let id, let hello)):
            return await handleHello(id: id, hello: hello)
        case .success(.call(let id, let call)):
            return await handleDeduplicated(id: id, call: call, mine: mine)
        case .success(.bye(let id)):
            policy.disconnected()
            ledger = BridgeRequestLedger()
            onState(policy.state)
            return (BridgeCodec.encode(.bye(id: id)), true)
        }
    }

    /// The connection dropped without a `bye` (crash, network loss): reset
    /// to `idle` so the next connection can `hello` again.
    public func connectionClosed() {
        epoch += 1
        policy.disconnected()
        ledger = BridgeRequestLedger()
        onState(policy.state)
    }

    /// Karen started a hold or sent a chat: the bridge yields the pin.
    public func pause() {
        policy.pause()
        onState(policy.state)
    }

    /// The voice turn ended: reopen and re-pin, so the hands follow
    /// whatever app Karen left in front rather than the one from before.
    public func resume() {
        policy.resume(now: now())
        onState(policy.state)
        if policy.isOpen {
            tools.beginTurn()
        }
    }

    /// "Stop hands" (spec §3 "Corte"): closes the session from any state,
    /// withdraws a parked session-open sheet as denied so its caller does
    /// not wait forever, and closes the live connection so the client sees
    /// EOF and reconnects (a fresh `hello` finds `idle` again — the same
    /// path `connectionClosed()` already takes on any other disconnect).
    /// The in-flight call (if any) finishes; its reply is `denied_by_user`
    /// or `session_closed`.
    public func stop() async {
        Log.bridge("stop requested by user")
        policy.stop()
        onState(policy.state)
        await withdrawPendingSheet()
        current?.close()
    }

    // MARK: - hello

    private func handleHello(id: Int, hello: BridgeHello) async -> (String, Bool) {
        guard hello.token == token() else {
            // The code only, never any token content: this line is the one
            // trace of a same-uid process knocking with the wrong key.
            Log.bridge("hello rejected: bad token")
            return (errorLine(id, BridgeCode.badToken, "invalid token"), true)
        }
        let verdict = policy.helloReceived(now: now())
        onState(policy.state)
        switch verdict {
        case .reject(let code):
            Log.bridge("hello rejected: \(code)")
            return (errorLine(id, code, rejectionMessage(code)), code == BridgeCode.coolingDown)
        case .needsApproval:
            // BridgePolicy.helloReceived never asks for approval (the sheet
            // moves to the first `call`, §9-4); kept for exhaustiveness.
            return (errorLine(id, BridgeCode.busy, "unexpected state"), false)
        case .proceed:
            markActive()
            client = hello.client
            Log.bridge("hello client=\(loggableName(client)); tools listed")
            let result = BridgeHelloResult(
                session: UUID().uuidString,
                language: language(),
                accessibility: accessibility(),
                tools: tools.specs(language())
                    .filter { BridgeScope.allows($0.name) }
                    .map(BridgeToolSpec.init))
            return (BridgeCodec.encode(.hello(id: id, result)), false)
        }
    }

    // MARK: - call

    /// A call's reply with what it means to the ledger, decided where the
    /// reply is built rather than guessed from its text.
    private struct Handled {
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
    private func handleDeduplicated(id: Int, call: BridgeCall, mine: Int) async -> (String, Bool) {
        switch ledger.begin(id) {
        case .replay(let reply):
            Log.bridge("call id \(id) repeated; first answer sent again, nothing executed")
            return (reply, false)
        case .tooLargeToReplay:
            Log.bridge("call id \(id) repeated; its first answer was too large to keep, nothing executed")
            let line = errorLine(id, BridgeCode.replyTooLarge, "the answer to request \(id) was too large to send again")
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
            return .refused(errorLine(id, code, rejectionMessage(code)))
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
                return .refused(errorLine(id, BridgeCode.coolingDown, rejectionMessage(BridgeCode.coolingDown)), close: true)
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
            return .refused(errorLine(id, code, rejectionMessage(code)))
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
        guard mine == epoch else { return .dropped }
        if verdict.answer == .refused { return refuseSheet(id: id) }
        if let denied = verdict.denial {
            let counts = verdict.answer.map { countsAsDenial($0, withdrawn: withdrawn) } ?? true
            return denyCall(id: id, denied, counts: counts)
        }
        // Same M4 guard as the session sheet: the yes may have landed after
        // the peer left, and there is nobody to answer or to act for.
        guard current?.isOpen ?? true else {
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
        return .refused(errorLine(id, BridgeCode.coolingDown, rejectionMessage(BridgeCode.coolingDown)), close: true)
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
    private func loggableName(_ name: String) -> String {
        String(name.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "." }
            .prefix(32)
            .map(Character.init))
    }

    private func errorLine(_ id: Int?, _ code: String, _ message: String) -> String {
        BridgeCodec.encode(.error(id: id, BridgeErrorBody(code: code, message: message)))
    }

    private func unavailableMessage(_ code: String, tool: String) -> String {
        switch code {
        case BridgeCode.selfInFront:
            return "Companion is in front; bring the app to act on to the front"
        case BridgeCode.needsAccessibility:
            return "Accessibility is not granted to Companion"
        default: return "\(tool) is not available right now"
        }
    }

    private func rejectionMessage(_ code: String) -> String {
        switch code {
        case BridgeCode.busy: return "another session is active"
        case BridgeCode.rateLimited:
            return "budget exceeded (\(BridgePolicy.budgetPerMinute) actions, \(BridgePolicy.readBudgetPerMinute) reads per minute)"
        case BridgeCode.noSession: return "no active session; send hello first"
        case BridgeCode.sessionClosed: return "session is closed"
        case BridgeCode.coolingDown: return "too many denied requests; try again later"
        default: return code
        }
    }
}
