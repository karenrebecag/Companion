import CompanionCore
import Foundation

/// Wave 17. The protocol actor: turns wire requests into `BridgePolicy`
/// decisions, approval-sheet round trips through `ParentToolGuard`, and
/// `ParentToolExecuting` calls. One instance per process, reused across
/// connections one at a time — `BridgeListener` never hands out a second
/// live connection while one is open.
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
    /// The client name from `hello` ("claude-code"), carried into the
    /// session-open sheet's `inputJSON` so the sheet can name who is
    /// asking. Display only — never a memory key (see `handleSessionApproval`).
    private var client = ""
    /// The connection `serve(_:)` is currently driving, so `stop()` can
    /// close it directly — the shim only reconnects when the socket drops,
    /// and `stop()` alone (just closing the session in `policy`) left the
    /// live connection open with nothing to ever tell it to reconnect.
    private var current: BridgeConnection?
    /// The session-open sheet `handleSessionApproval` is waiting on, if
    /// any, so `stop()` ("Corte") can withdraw it instead of leaving it
    /// parked forever.
    private var pendingSheet: ApprovalRequest?

    public init(
        tools: any ParentToolExecuting,
        guard parentGuard: ParentToolGuard,
        token: @escaping @Sendable () -> String,
        language: @escaping @Sendable () -> AppLanguage,
        accessibility: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = { Date() },
        onState: @escaping @Sendable (BridgeState) -> Void = { _ in },
        onAction: @escaping @Sendable (String) -> Void = { _ in },
        onCall: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.tools = tools
        self.guardian = parentGuard
        self.token = token
        self.language = language
        self.accessibility = accessibility
        self.now = now
        self.onState = onState
        self.onAction = onAction
        self.onCall = onCall
    }

    public var state: BridgeState { policy.state }

    /// Reads lines off `connection` until it closes or a reply says to close
    /// it. One call drives one connection start to finish.
    public func serve(_ connection: BridgeConnection) async {
        current = connection
        for await line in connection.lines {
            let (reply, close) = await handle(line: line)
            connection.send(line: reply)
            if close {
                connection.close()
                break
            }
        }
        current = nil
        connectionClosed()
    }

    /// Pure enough to test without a socket: one line in, one reply out.
    public func handle(line: String) async -> (reply: String, close: Bool) {
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
            return await handleCall(id: id, call: call)
        case .success(.bye(let id)):
            policy.disconnected()
            onState(policy.state)
            return (BridgeCodec.encode(.bye(id: id)), true)
        }
    }

    /// The connection dropped without a `bye` (crash, network loss): reset
    /// to `idle` so the next connection can `hello` again.
    public func connectionClosed() {
        policy.disconnected()
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
        if let pendingSheet {
            await guardian.withdraw(pendingSheet)
            self.pendingSheet = nil
        }
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
            return (errorLine(id, code, rejectionMessage(code)), false)
        case .needsApproval:
            // BridgePolicy.helloReceived never asks for approval (the sheet
            // moves to the first `call`, §9-4); kept for exhaustiveness.
            return (errorLine(id, BridgeCode.busy, "unexpected state"), false)
        case .proceed:
            client = hello.client
            Log.bridge("hello client=\(loggableName(client)); tools listed")
            let result = BridgeHelloResult(
                session: UUID().uuidString,
                language: language(),
                accessibility: accessibility(),
                tools: tools.specs(language())
                    .filter { !BridgeScope.isLocalOnly($0.name) }
                    .map(BridgeToolSpec.init))
            return (BridgeCodec.encode(.hello(id: id, result)), false)
        }
    }

    // MARK: - call

    private func handleCall(id: Int, call: BridgeCall) async -> (String, Bool) {
        // Local-only first: the bridge must not even say such a tool exists.
        guard !BridgeScope.isLocalOnly(call.name) else {
            return (errorLine(id, BridgeCode.unknownTool, "unknown tool: \(call.name)"), false)
        }
        guard tools.handles(call.name) else {
            if let reason = tools.unavailability(for: call.name) {
                return (errorLine(id, reason, unavailableMessage(reason, tool: call.name)), false)
            }
            return (errorLine(id, BridgeCode.unknownTool, "unknown tool: \(call.name)"), false)
        }
        let verdict = policy.admit(tool: call.name, now: now())
        onState(policy.state)
        switch verdict {
        case .reject(let code):
            return (errorLine(id, code, rejectionMessage(code)), false)
        case .proceed:
            return await performCall(id: id, call: call)
        case .needsApproval:
            return await handleSessionApproval(id: id, call: call)
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
    private func handleSessionApproval(id: Int, call: BridgeCall) async -> (String, Bool) {
        let request = ApprovalRequest(
            requestId: UUID().uuidString, toolName: BridgePolicy.sessionApprovalTool,
            summary: BridgeCopy.sheetTitle(language()), inputJSON: sessionApprovalInputJSON())
        pendingSheet = request
        // Seen live 2026-09-28: this whole round trip resolved with no
        // trace, and only the shim's error said anything happened. The
        // request and its resolution are the two lines that tell a silent
        // auto-deny apart from a user's "no".
        Log.bridge("session approval requested by \(loggableName(client))")
        let approved = await guardian.ask(request)
        pendingSheet = nil
        Log.bridge("session approval resolved approved=\(approved)")
        guard approved else {
            policy.denied()
            onState(policy.state)
            return (errorLine(id, BridgeCode.deniedByUser, "the user denied the hands"), false)
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
            return ("", false)
        }
        policy.approved(until: nil, now: now())
        onState(policy.state)
        Log.bridge("session open for \(loggableName(client))")
        tools.beginTurn()
        let verdict = policy.admit(tool: call.name, now: now())
        onState(policy.state)
        switch verdict {
        case .reject(let code):
            return (errorLine(id, code, rejectionMessage(code)), false)
        case .needsApproval:
            return (errorLine(id, BridgeCode.busy, "unexpected state"), false)
        case .proceed:
            return await performCall(id: id, call: call)
        }
    }

    /// The per-call gate (destructive click, Return in a terminal, `type_text`
    /// always) runs with `said: ""`: nothing was spoken, so anything 15g/16
    /// would have trusted a spoken word for goes to the sheet instead.
    private func performCall(id: Int, call: BridgeCall) async -> (String, Bool) {
        let ref = ToolCallRef(id: UUID().uuidString, name: call.name, arguments: call.argumentsJSON)
        let outcome: ParentToolOutcome
        if let denied = await guardian.check(ref, said: "", language: language(), tools: tools) {
            outcome = denied
        } else {
            outcome = await tools.execute(name: call.name, argumentsJSON: call.argumentsJSON)
        }
        if outcome.ok { onCall(call.name) }
        if outcome.ok, BridgePolicy.writeTools.contains(call.name) {
            onAction(call.name)
        }
        // Never the arguments or the output — name, outcome, target, size.
        Log.bridge("call \(call.name) ok=\(outcome.ok) target=\(outcome.target) "
            + "chars=\(call.argumentsJSON.utf8.count)")
        return (BridgeCodec.encode(.call(id: id, BridgeCallResult(outcome))), false)
    }

    /// Built with `JSONSerialization`, not string interpolation: the client
    /// name came off the wire and must not be able to break the JSON shape
    /// `ApprovalKey.from` parses back out.
    private func sessionApprovalInputJSON() -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: ["client": client])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
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

    private func errorLine(_ id: Int, _ code: String, _ message: String) -> String {
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
        case BridgeCode.rateLimited: return "budget exceeded (\(BridgePolicy.budgetPerMinute)/min)"
        case BridgeCode.noSession: return "no active session; send hello first"
        case BridgeCode.sessionClosed: return "session is closed"
        default: return code
        }
    }
}
