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
package actor BridgeSession {
    let tools: any ParentToolExecuting
    let guardian: ParentToolGuard
    private let token: @Sendable () -> String
    let language: @Sendable () -> AppLanguage
    private let accessibility: @Sendable () -> Bool
    let now: @Sendable () -> Date
    let onState: @Sendable (BridgeState) -> Void
    /// Fires when a session starts and when it ends, so state tied to "the
    /// bridge" (browser tab leases) never outlives the client that made it.
    let onSessionBoundary: @Sendable () -> Void
    /// 17-2's island chip blinks on this: fired after a successful write
    /// action (§3 "cada acción de escritura lo hace parpadear").
    let onAction: @Sendable (String) -> Void
    let onCall: @Sendable (String) -> Void

    var policy = BridgePolicy()
    /// The request ids this connection has used (20c D6, M8a). Replaced with
    /// a fresh ledger wherever the connection's state is reset.
    var ledger = BridgeRequestLedger()
    /// The client name from `hello` ("claude-code"), carried into the
    /// session-open sheet's `inputJSON` so the sheet can name who is
    /// asking. Display only — never a memory key (see `handleSessionApproval`).
    var client = ""
    /// The connection `serve(_:)` is currently driving, so `stop()` can
    /// close it directly — the shim only reconnects when the socket drops,
    /// and `stop()` alone (just closing the session in `policy`) left the
    /// live connection open with nothing to ever tell it to reconnect.
    var current: BridgeConnection?
    /// The sheet (session-open or per-call) the current call is waiting on,
    /// so `stop()` ("Corte"), the peer leaving, or a replacing connection can
    /// withdraw it instead of leaving it on screen and the slot held.
    let parked: BridgeParkedSheet
    var epoch = 0
    private let idleTimeout: TimeInterval
    private let idleCheckInterval: TimeInterval
    private var lastActivity: Date
    /// Calls and sheets being awaited right now: a session working for the
    /// peer is not idle, the sheet has its own timeout.
    private var inFlight = 0

    package init(
        tools: any ParentToolExecuting,
        guard parentGuard: ParentToolGuard,
        token: @escaping @Sendable () -> String,
        language: @escaping @Sendable () -> AppLanguage,
        accessibility: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = { Date() },
        onState: @escaping @Sendable (BridgeState) -> Void = { _ in },
        onAction: @escaping @Sendable (String) -> Void = { _ in },
        onCall: @escaping @Sendable (String) -> Void = { _ in },
        onSessionBoundary: @escaping @Sendable () -> Void = {},
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
        self.onSessionBoundary = onSessionBoundary
    }

    package var state: BridgeState { policy.state }

    /// Reads lines off `connection` until it closes or a reply says to close
    /// it. One call drives one connection start to finish.
    package func serve(_ connection: BridgeConnection) async {
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
        onSessionBoundary()
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
        onSessionBoundary()
        connectionClosed()
    }

    /// Closes the live connection once it has been quiet for `idleTimeout`:
    /// the session is closed (a fresh hello and sheet are needed) and the
    /// peer sees EOF. True when it acted.
    @discardableResult
    package func expireIfIdle() -> Bool {
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
    func markActive() {
        lastActivity = now()
    }

    /// Pure enough to test without a socket: one line in, one reply out.
    package func handle(line: String) async -> (reply: String, close: Bool) {
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
    package func connectionClosed() {
        epoch += 1
        policy.disconnected()
        ledger = BridgeRequestLedger()
        onState(policy.state)
    }

    /// Karen started a hold or sent a chat: the bridge yields the pin.
    package func pause() {
        policy.pause()
        onState(policy.state)
    }

    /// The voice turn ended: reopen and re-pin, so the hands follow
    /// whatever app Karen left in front rather than the one from before.
    package func resume() {
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
    package func stop() async {
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
}
