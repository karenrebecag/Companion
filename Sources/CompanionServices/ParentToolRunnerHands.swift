import CompanionCore
import Foundation

/// What the parent's hands need (Wave 15g): the four ports, the trust check
/// the rest of Accessibility already reads, and the app the user was in.
/// `target` is `FrontmostAppSensor.lastOtherPID` — never Companion's own —
/// read when the call arrives and read again right before acting.
public struct ScreenHands: Sendable {
    let injector: any TextInjecting
    let reader: any FocusedReading
    let keys: any KeyPressing
    let windows: any WindowRaising
    let trusted: @Sendable () -> Bool
    let target: @Sendable () -> Int32?
    let bundleID: @Sendable (Int32) -> String?
    /// Typed chat has Companion's own window in front: the field the hands
    /// would need is not the one in front, so they are not offered.
    let selfInFront: @Sendable () -> Bool
    /// Wave 16a: the window read as numbered elements, and pressed by id.
    /// Nil keeps look/click/scroll/menu unoffered.
    let screen: (any ScreenActing)?
    /// 16a-3: a capture described by vision, for questions about pixels.
    let see: (@Sendable (SeeRequest) async -> ScreenBrief?)?
    let tickets = ApprovalTickets()
    let turn = TurnTarget()
    let scans = ScanMemory()

    public init(
        injector: any TextInjecting,
        reader: any FocusedReading,
        keys: any KeyPressing,
        windows: any WindowRaising,
        trusted: @escaping @Sendable () -> Bool,
        target: @escaping @Sendable () -> Int32?,
        bundleID: @escaping @Sendable (Int32) -> String?,
        selfInFront: @escaping @Sendable () -> Bool = { false },
        screen: (any ScreenActing)? = nil,
        see: (@Sendable (SeeRequest) async -> ScreenBrief?)? = nil
    ) {
        self.screen = screen
        self.see = see
        self.injector = injector
        self.reader = reader
        self.keys = keys
        self.windows = windows
        self.trusted = trusted
        self.target = target
        self.bundleID = bundleID
        self.selfInFront = selfInFront
    }

    /// One adapter behind all four ports, as the app wires it.
    public init(
        ax: AXTextInjector, screen: AXScreen, target: @escaping @Sendable () -> Int32?,
        selfInFront: @escaping @Sendable () -> Bool = { false },
        see: (@Sendable (SeeRequest) async -> ScreenBrief?)? = nil
    ) {
        self.init(
            injector: ax, reader: ax, keys: ax, windows: ax,
            trusted: { ax.isTrusted() }, target: target,
            bundleID: { AXTextInjector.bundleID(of: $0) }, selfInFront: selfInFront,
            screen: screen, see: see)
    }
}

/// The app the user was in when they spoke (review 2026-09-25, HIGH-1).
/// The model can take seconds; if the user switched apps meanwhile, typing
/// into whatever is in front now would land in a window nobody asked for.
final class TurnTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: Int32?
    private var repin = false

    func begin(_ pid: Int32?) { lock.withLock { self.pid = pid; repin = false } }
    var current: Int32? { lock.withLock { pid } }

    /// An open the user asked for moved the front on purpose; the app is
    /// only frontmost a moment later, so the next hands call pins it — and
    /// anything after that is held to it (security review 16, H1).
    func release() { lock.withLock { pid = nil; repin = true } }

    /// The turn's pin for a call now acting on `observed`.
    func pin(for observed: Int32) -> Int32? {
        lock.withLock {
            if repin { pid = observed; repin = false }
            return pid
        }
    }
}

/// A command-app call runs only when the gate cleared that exact call on
/// that pid: `approval(for:said:)` either issues the ticket itself (the user
/// said the text) or parks it under the request id, `grant` (the gate, on a
/// yes) makes it spendable once, `execute` spends it. A denial never grants,
/// and a path that skipped the gate finds nothing — both fail closed instead
/// of pressing Return in a shell. One pending ask: the latest wins. A ticket
/// not spent within `lifetime` is gone, so a yes cannot wait for a later turn.
final class ApprovalTickets: @unchecked Sendable {
    static let lifetime: TimeInterval = 60

    struct Ticket: Equatable {
        let name: String
        let arguments: String
        let pid: Int32
    }

    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private var pending: (id: String, ticket: Ticket)?
    private var granted: [(ticket: Ticket, at: Date)] = []

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func park(_ ticket: Ticket, id: String) {
        lock.withLock { pending = (id, ticket) }
    }

    func grant(id: String) {
        lock.withLock {
            guard let parked = pending, parked.id == id else { return }
            granted.append((parked.ticket, now()))
            pending = nil
        }
    }

    func issue(_ ticket: Ticket) {
        lock.withLock { granted.append((ticket, now())) }
    }

    func redeem(_ ticket: Ticket) -> Bool {
        lock.withLock {
            let cutoff = now().addingTimeInterval(-Self.lifetime)
            granted = granted.filter { $0.at >= cutoff }
            guard let index = granted.firstIndex(where: { $0.ticket == ticket }) else { return false }
            granted.remove(at: index)
            return true
        }
    }
}

extension ParentToolRunner {
    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Enough of the prompt line to judge what Return would run.
    static let sheetLine = 200

    static func handsError(_ code: String, _ message: String) -> ContractError {
        ContractError(code: code, message: message)
    }

    /// Nil when the call does not need the sheet. Command-app detection is
    /// done here because only the runner knows which app it would act on.
    /// A refusal is also nil: `execute` refuses it with its reason.
    func handsApproval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard let hands = readyHands, let pid = hands.target(), pid != Self.ownPID else {
            return nil
        }
        let bundle = hands.bundleID(pid)
        let command = CommandApps.isCommandApp(bundleID: bundle)
        let ticket = ApprovalTickets.Ticket(name: call.name, arguments: call.arguments, pid: pid)
        if call.name == ParentTool.click.rawValue {
            return clickApproval(call, said: said, hands: hands, pid: pid, ticket: ticket)
        }
        switch HandsGate.verdict(call, commandApp: command, said: said) {
        case .refuse:
            return nil
        case .act:
            if HandsGate.needsTicket(call, commandApp: command) { hands.tickets.issue(ticket) }
            return nil
        case .ask:
            let app = hands.reader.focusedField(pid: pid)?.app ?? bundle ?? "app"
            let line = command && call.name == ParentTool.pressKey.rawValue
                ? hands.reader.read(pid: pid).map { String($0.suffix(Self.sheetLine)) } : nil
            let request = HandsGate.request(call, app: app, commandApp: command, line: line)
            hands.tickets.park(ticket, id: request.requestId)
            return request
        }
    }

    func runHands(
        _ tool: ParentTool, _ call: ToolCallRef, _ arguments: [String: Any]
    ) async -> ParentToolOutcome {
        guard let hands = readyHands else {
            return .failed(Self.handsError("needs_accessibility", "Accessibility is not granted"),
                           tool: tool.rawValue)
        }
        guard let pid = hands.target(), pid != Self.ownPID else {
            return .failed(Self.handsError("no_target", "no app in front other than Companion"),
                           tool: tool.rawValue)
        }
        if let spoken = hands.turn.pin(for: pid), spoken != pid {
            Log.app("hands: \(tool.rawValue) target_changed since the user spoke pid=\(pid)")
            return .failed(Self.handsError(
                "target_changed", "the app in front is not the one the user was in"),
                tool: tool.rawValue)
        }
        let bundle = hands.bundleID(pid)
        let command = CommandApps.isCommandApp(bundleID: bundle)
        if command, tool == .typeText,
           HandsWords.hasControl(arguments["text"] as? String ?? "", format: true) {
            Log.app("hands: type_text control_characters pid=\(pid) bundle=\(bundle ?? "-")")
            return .failed(Self.handsError(
                "control_characters", "control characters are never typed into a command app"),
                tool: tool.rawValue)
        }
        if HandsGate.needsTicket(call, commandApp: command),
           !hands.tickets.redeem(.init(name: call.name, arguments: call.arguments, pid: pid)) {
            Log.app("hands: \(tool.rawValue) refused, no approval pid=\(pid) bundle=\(bundle ?? "-")")
            return .failed(Self.handsError(
                "approval_required", "a command app needs approval for typing or Return"),
                tool: tool.rawValue)
        }
        if tool == .see { return await runSee(arguments, hands: hands, pid: pid) }
        if tool.isSight {
            return await runSight(tool, call, arguments, hands: hands, pid: pid, bundle: bundle ?? "-")
        }
        let act = HandsAct(hands: hands, pid: pid, bundle: bundle ?? "-", tool: tool)
        switch tool {
        case .typeText: return await act.type(arguments)
        case .pressKey: return act.press(arguments)
        case .focusWindow: return act.raise(arguments)
        case .readFocused: return act.read()
        case .openApp, .openURL, .openFile, .listApps, .readSkill, .look, .click, .scroll, .menu, .see:
            return .failed(.notFound("not a hands tool: \(tool.rawValue)"), tool: tool.rawValue)
        }
    }
}

/// One call of the hands against one captured pid. Logs carry the tool,
/// counts, pid and bundle id — never the text typed or read.
private struct HandsAct {
    let hands: ScreenHands
    let pid: Int32
    let bundle: String
    let tool: ParentTool

    private func fail(_ code: String, _ message: String, target: String = "") -> ParentToolOutcome {
        Log.app("hands: \(tool.rawValue) \(code) pid=\(pid) bundle=\(bundle)")
        return .failed(ParentToolRunner.handsError(code, message), target: target, tool: tool.rawValue)
    }

    /// The user may have switched apps while the model thought: acting on
    /// whatever is in front now would type into the wrong window.
    private var moved: Bool { hands.target() != pid }

    /// A field or the reason there is none, the same words for type and read.
    private func field() -> Result<FocusedField, ContractError> {
        guard let field = hands.reader.focusedField(pid: pid) else {
            return .failure(ContractError(
                code: "no_focused_field", message: "no focused text field in the app in front"))
        }
        guard !field.secure else {
            return .failure(ContractError(
                code: "secure_field", message: "the focused field is a password field"))
        }
        return .success(field)
    }

    func type(_ arguments: [String: Any]) async -> ParentToolOutcome {
        guard let raw = arguments["text"] as? String, !raw.isEmpty else {
            return .failed(.invalidArgs("missing text"), tool: tool.rawValue)
        }
        let text = HandsGate.stripped(raw)
        guard !text.isEmpty else { return .failed(.invalidArgs("missing text"), tool: tool.rawValue) }
        Log.app("hands: type_text chars=\(text.count) pid=\(pid) bundle=\(bundle)")
        let target: FocusedField
        switch field() {
        case .failure(let error): return fail(error.code, error.message)
        case .success(let found): target = found
        }
        guard !moved else { return fail("target_changed", "the app in front changed") }
        switch await hands.injector.inject(text, into: target) {
        case .injected(let count, let route):
            Log.app("hands: type_text typed chars=\(count) via=\(route.rawValue) pid=\(pid)")
            return ParentToolOutcome(ok: true, output: "typed \(count) chars", tool: tool.rawValue)
        case .failed(.needsAccessibility):
            return fail("needs_accessibility", "Accessibility is not granted")
        case .failed(.fieldGone):
            return fail("target_changed", "the app is no longer in front")
        case .failed(.refused):
            return fail("refused", "the field did not accept the text")
        }
    }

    func press(_ arguments: [String: Any]) -> ParentToolOutcome {
        let key: NamedKey
        do {
            key = try NamedKey.parse(arguments["key"] as? String ?? "")
        } catch {
            return .failed(error, tool: tool.rawValue)
        }
        guard !moved else { return fail("target_changed", "the app in front changed", target: key.rawValue) }
        guard hands.keys.press(key, pid: pid) else {
            return fail("refused", "the key could not be sent", target: key.rawValue)
        }
        Log.app("hands: press_key \(key.rawValue) pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(
            ok: true, output: "pressed \(key.rawValue)", target: key.rawValue, tool: tool.rawValue)
    }

    func raise(_ arguments: [String: Any]) -> ParentToolOutcome {
        let query = (arguments["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .failed(.invalidArgs("missing title"), tool: tool.rawValue) }
        guard !moved else { return fail("target_changed", "the app in front changed", target: query) }
        guard let title = hands.windows.raise(titleContaining: query, pid: pid) else {
            return fail("window_not_found", "no window whose title contains \"\(query)\"", target: query)
        }
        Log.app("hands: focus_window raised pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(ok: true, output: "raised \(title)", target: title, tool: tool.rawValue)
    }

    func read() -> ParentToolOutcome {
        switch field() {
        case .failure(let error): return fail(error.code, error.message)
        case .success: break
        }
        guard !moved else { return fail("target_changed", "the app in front changed") }
        guard let text = hands.reader.read(pid: pid) else {
            return fail("no_focused_field", "the focused field has no readable text")
        }
        let clipped = FocusedText.clip(text)
        Log.app("hands: read_focused chars=\(clipped.count) pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(ok: true, output: clipped, tool: tool.rawValue)
    }
}
