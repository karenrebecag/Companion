import CompanionCore
import Foundation

/// Whether an extension is connected, readable from any thread. The tool
/// list asks this synchronously (a tool with nothing behind it is not
/// offered), so it cannot live behind the channel's actor.
package final class BrowserPresence: @unchecked Sendable {
    private let lock = NSLock()
    private var current: BrowserKind?
    private var counter = 0

    package init() {}

    package var browser: BrowserKind? { lock.withLock { current } }

    package var connected: Bool { browser != nil }

    /// Changes on every connect and disconnect, so a holder of per-connection
    /// state (pages read, approvals given) can tell it belongs to a
    /// connection that is gone.
    var epoch: Int { lock.withLock { counter } }

    func set(_ kind: BrowserKind?) {
        lock.withLock {
            current = kind
            counter += 1
        }
    }
}

/// Wave 18-2. The app's end of the browser socket: one extension, proven by
/// `hello`, then Companion calls and the extension answers by id. It never
/// dispatches anything the extension sends as a request: the extension is
/// code running beside arbitrary web pages, so it may answer but never ask.
package actor BrowserChannel {
    private struct Pending {
        let command: BrowserCommand
        let continuation: CheckedContinuation<Result<BrowserInbound, ContractError>, Never>
        let timer: Task<Void, Never>
    }

    private static let protocolVersion = 1

    private let presence: BrowserPresence
    private let token: @Sendable () -> String
    private let helloDeadline: Duration
    private var current: BridgeConnection?
    private var authenticated = false
    private var nextID = 0
    private var pending: [Int: Pending] = [:]

    package init(
        presence: BrowserPresence, token: @escaping @Sendable () -> String,
        helloDeadline: Duration = .seconds(5)
    ) {
        self.presence = presence
        self.token = token
        self.helloDeadline = helloDeadline
    }

    /// Serves one connection until it closes. The `BridgeListener` slot
    /// already keeps a second client out; the check here is for the window in
    /// which the listener freed the slot before this actor saw the close.
    package func attach(_ connection: BridgeConnection) async {
        if let existing = current, existing.isOpen {
            connection.send(line: BrowserCodec.encode(.error(
                id: nil, BridgeErrorBody(code: BridgeCode.busy, message: "another browser is connected"))))
            connection.close()
            return
        }
        if let stale = current { disconnected(stale) }
        current = connection
        authenticated = false

        let deadline = Task { [helloDeadline] in
            do { try await Task.sleep(for: helloDeadline) } catch { return }
            await self.helloDeadlineElapsed(connection)
        }
        for await line in connection.lines {
            // A connection that was replaced can still have lines buffered:
            // they must not authenticate the new one or answer its calls.
            guard current === connection else { break }
            if authenticated {
                handle(line: line, on: connection)
            } else if authenticate(line: line, on: connection) {
                deadline.cancel()
            } else {
                connection.close()
                break
            }
        }
        deadline.cancel()
        disconnected(connection)
    }

    /// The caller picks the timeout: a read is seconds, a navigation longer.
    package func send(
        _ command: BrowserCommand, timeout: Duration
    ) async -> Result<BrowserInbound, ContractError> {
        guard authenticated, let connection = current, connection.isOpen else {
            return .failure(Self.error(BridgeCode.notConnected, "No browser is connected"))
        }
        nextID += 1
        let id = nextID
        let line = BrowserCodec.encode(.call(id: id, command))
        // The relay would refuse it (and the listener would drop the
        // connection on a longer line), so it never leaves the app.
        guard line.utf8.count <= BrowserWire.maxLineBytes else {
            return .failure(Self.error(BridgeCode.frameTooLarge, "Command exceeds \(BrowserWire.maxLineBytes) bytes"))
        }
        return await withCheckedContinuation { continuation in
            let timer = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                await self.expire(id)
            }
            pending[id] = Pending(command: command, continuation: continuation, timer: timer)
            connection.send(line: line)
        }
    }

    // MARK: - handshake

    private func authenticate(line: String, on connection: BridgeConnection) -> Bool {
        guard case .success(.hello(let id, let hello)) = BrowserCodec.decode(line: line) else {
            reject(connection, id: nil)
            return false
        }
        guard hello.protocolVersion == Self.protocolVersion,
              Self.constantTimeEquals(hello.token, token())
        else {
            reject(connection, id: id)
            return false
        }
        authenticated = true
        presence.set(hello.browser)
        connection.send(line: BrowserCodec.encode(.helloOK(id: id)))
        Log.browser("connected browser=\(hello.browser.rawValue)")
        return true
    }

    /// One code for every handshake failure: telling a wrong token from a
    /// wrong version would help only someone guessing the token.
    private func reject(_ connection: BridgeConnection, id: Int?) {
        Log.browser("hello rejected code=\(BridgeCode.badToken)")
        connection.send(line: BrowserCodec.encode(.error(
            id: id, BridgeErrorBody(code: BridgeCode.badToken, message: "Handshake rejected"))))
    }

    private func helloDeadlineElapsed(_ connection: BridgeConnection) {
        guard current === connection, !authenticated else { return }
        Log.browser("no hello before the deadline")
        connection.close()
    }

    // MARK: - frames after hello

    private func handle(line: String, on connection: BridgeConnection) {
        switch BrowserCodec.decode(line: line) {
        case .success(let inbound):
            route(inbound, on: connection)
        case .failure(let body):
            // A `call` from the extension lands here as unknown_method: it is
            // answered with an error and goes nowhere else.
            Log.browser("inbound frame rejected code=\(body.code)")
            connection.send(line: BrowserCodec.encode(.error(id: nil, body)))
        }
    }

    private func route(_ inbound: BrowserInbound, on connection: BridgeConnection) {
        switch inbound {
        case .tabs(let id, _), .opened(let id, _), .page(let id, _), .done(let id, _):
            resolve(id, .success(inbound))
        case .error(let id, let body):
            guard let id else {
                Log.browser("error without id code=\(body.code)")
                return
            }
            // Code and message were already reduced to an allowlist and one short line by the codec.
            resolve(id, .failure(Self.error(body.code, body.message)))
        case .hello:
            connection.send(line: BrowserCodec.encode(.error(
                id: nil, BridgeErrorBody(code: BridgeCode.badFrame, message: "Already connected"))))
        }
    }

    private func resolve(_ id: Int, _ result: Result<BrowserInbound, ContractError>) {
        guard let entry = pending.removeValue(forKey: id) else {
            Log.browser("late or unknown reply dropped")
            return
        }
        entry.timer.cancel()
        let checked = Self.checked(entry.command, result)
        Log.browser(Self.summary(entry.command, checked))
        entry.continuation.resume(returning: checked)
    }

    private func expire(_ id: Int) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        let result: Result<BrowserInbound, ContractError> =
            .failure(Self.error(BridgeCode.timeout, "The browser did not answer in time"))
        Log.browser(Self.summary(entry.command, result))
        entry.continuation.resume(returning: result)
    }

    private func disconnected(_ connection: BridgeConnection) {
        guard current === connection else { return }
        current = nil
        authenticated = false
        presence.set(nil)
        let failed = pending
        pending = [:]
        for entry in failed.values {
            entry.timer.cancel()
            entry.continuation.resume(returning: .failure(Self.error(BridgeCode.notConnected, "The browser disconnected")))
        }
        Log.browser("disconnected pending=\(failed.count)")
    }

    // MARK: - pure helpers

    private static func error(_ code: String, _ message: String) -> ContractError {
        ContractError(code: code, message: message)
    }

    private static func tool(_ command: BrowserCommand) -> BrowserTool {
        switch command {
        case .tabs: return .tabs
        case .read: return .read
        case .click: return .click
        case .doubleClick: return .doubleClick
        case .rightClick: return .rightClick
        case .type: return .type
        case .select: return .select
        case .scroll, .scrollTo: return .scroll
        case .hover: return .hover
        case .press: return .press
        case .dragTo, .dragBy: return .drag
        case .clickAt: return .clickAt
        case .navigate: return .navigate
        case .open: return .open
        case .take: return .take
        case .release: return .release
        }
    }

    /// An extension answering a `click` with a page is broken or hostile;
    /// the caller must not receive a shape it did not ask for.
    private static func checked(
        _ command: BrowserCommand, _ result: Result<BrowserInbound, ContractError>
    ) -> Result<BrowserInbound, ContractError> {
        guard case .success(let inbound) = result else { return result }
        switch (command, inbound) {
        case (.tabs, .tabs), (.read, .page), (.click, .done), (.doubleClick, .done), (.rightClick, .done),
             (.type, .done), (.select, .done), (.press, .done), (.navigate, .done),
             (.scroll, .done), (.scrollTo, .done), (.hover, .done), (.dragTo, .done), (.dragBy, .done), (.clickAt, .done),
             (.open, .opened), (.take, .done), (.release, .done):
            return result
        default:
            return .failure(error(BridgeCode.badFrame, "Unexpected reply for \(tool(command).rawValue)"))
        }
    }

    /// Tool, outcome and a character count: enough to debug a call without
    /// the log ever holding what the page said or which site it was.
    private static func summary(_ command: BrowserCommand, _ result: Result<BrowserInbound, ContractError>) -> String {
        let name = tool(command).rawValue
        switch result {
        case .failure(let error):
            return "tool=\(name) code=\(error.code)"
        case .success(.page(_, let page)):
            return "tool=\(name) code=ok chars=\(page.text.count)"
        case .success:
            return "tool=\(name) code=ok"
        }
    }

    /// Runs over the longer of the two so the time does not tell how many
    /// leading characters matched. An empty expected token never matches.
    static func constantTimeEquals(_ given: String, _ expected: String) -> Bool {
        let a = Array(given.utf8)
        let b = Array(expected.utf8)
        var difference = a.count ^ b.count
        for index in 0 ..< max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            difference |= Int(x ^ y)
        }
        return difference == 0 && !b.isEmpty
    }
}
