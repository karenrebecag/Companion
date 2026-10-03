import CompanionCore
import Foundation

/// What the parent's hands need (Wave 15g): the four ports, the trust check
/// the rest of Accessibility already reads, and the app the user was in.
/// `target` is `FrontmostAppSensor.lastOtherPID` — never Companion's own —
/// read when the call arrives and read again right before acting.
package struct ScreenHands: Sendable {
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
    /// What changed after a hand acted. Nil keeps the older "look again"
    /// results, which is what every test without an observer expects.
    let changes: (any AXChangeWatching)?
    /// Checked right before a capture: `see` without it fails silently.
    let screenRecording: @Sendable () -> Bool
    let locked: @Sendable () -> Bool
    /// open_app's view of the app it launched; nil leaves open_app returning
    /// as soon as the launch was requested.
    let launch: (any AppWindowProbing)?
    let windowWait: WindowWait
    let tickets = ApprovalTickets()
    let turn = TurnTarget()
    let scans = ScanMemory()

    package init(
        injector: any TextInjecting,
        reader: any FocusedReading,
        keys: any KeyPressing,
        windows: any WindowRaising,
        trusted: @escaping @Sendable () -> Bool,
        target: @escaping @Sendable () -> Int32?,
        bundleID: @escaping @Sendable (Int32) -> String?,
        selfInFront: @escaping @Sendable () -> Bool = { false },
        screen: (any ScreenActing)? = nil,
        see: (@Sendable (SeeRequest) async -> ScreenBrief?)? = nil,
        changes: (any AXChangeWatching)? = nil,
        screenRecording: @escaping @Sendable () -> Bool = { true },
        locked: @escaping @Sendable () -> Bool = { false },
        launch: (any AppWindowProbing)? = nil,
        windowWait: WindowWait = .standard
    ) {
        self.screen = screen
        self.see = see
        self.changes = changes
        self.screenRecording = screenRecording
        self.locked = locked
        self.launch = launch
        self.windowWait = windowWait
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
    package init(
        ax: AXTextInjector, screen: AXScreen, target: @escaping @Sendable () -> Int32?,
        selfInFront: @escaping @Sendable () -> Bool = { false },
        see: (@Sendable (SeeRequest) async -> ScreenBrief?)? = nil,
        changes: (any AXChangeWatching)? = nil
    ) {
        self.init(
            injector: ax, reader: ax, keys: ax, windows: ax,
            trusted: { ax.isTrusted() }, target: target,
            bundleID: { AXTextInjector.bundleID(of: $0) }, selfInFront: selfInFront,
            screen: screen, see: see, changes: changes,
            screenRecording: { ScreenRecordingPermission().isGranted() }, locked: { SessionLock.isLocked() },
            launch: screen)
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
        /// The concrete thing approved when the call's own arguments name it
        /// only loosely (a menu item found by partial name).
        let item: String
        /// A click's ids expire on the next look, so its ticket carries the
        /// node the id pointed at and the scan generation that numbered it:
        /// the bare `{"id":N}` would match whatever a later look put at N.
        let node: Int?
        let generation: Int?

        init(
            name: String, arguments: String, pid: Int32, item: String = "",
            node: Int? = nil, generation: Int? = nil
        ) {
            self.name = name
            self.arguments = arguments
            self.pid = pid
            self.item = item
            self.node = node
            self.generation = generation
        }

        /// Bound to the element AND the scan it was read from, label included
        /// so a control that changed its text under the same node is refused.
        static func click(
            _ call: ToolCallRef, pid: Int32, element: ScreenElement, generation: Int
        ) -> Ticket {
            Ticket(name: call.name, arguments: call.arguments, pid: pid, item: element.label,
                   node: element.node, generation: generation)
        }
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

    /// By name and arguments only: the pid, node or scan a ticket was bound
    /// to may have moved since, and the dropped call cannot rebuild them. A
    /// pending one goes too, or a late yes would grant it afterwards. An
    /// identical call in another lane loses its ticket with it; that one
    /// fails closed and asks again.
    func revoke(name: String, arguments: String) {
        lock.withLock {
            granted.removeAll { $0.ticket.name == name && $0.ticket.arguments == arguments }
            if let parked = pending, parked.ticket.name == name, parked.ticket.arguments == arguments {
                pending = nil
            }
        }
    }

    func reset() {
        lock.withLock {
            pending = nil
            granted = []
        }
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
        if call.name == ParentTool.click.rawValue {
            return clickApproval(call, said: said, hands: hands, pid: pid)
        }
        let ticket = ApprovalTickets.Ticket(name: call.name, arguments: call.arguments, pid: pid)
        if call.name == ParentTool.menu.rawValue {
            return menuApproval(call, said: said, hands: hands, pid: pid, ticket: ticket)
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
        guard let hands = installedHands else {
            return .failed(Self.handsError(BridgeCode.notAvailable, "no hands on this Mac"), tool: tool.rawValue)
        }
        if hands.locked() {
            Log.app("hands: \(tool.rawValue) refused, session locked")
            return .failed(Self.handsError(BridgeCode.screenLocked, BridgeMessages.screenLocked), tool: tool.rawValue)
        }
        guard hands.trusted() else {
            return .failed(Self.handsError(BridgeCode.needsAccessibility, BridgeMessages.needsAccessibility),
                           tool: tool.rawValue)
        }
        guard !hands.selfInFront() else {
            return .failed(Self.handsError(BridgeCode.selfInFront, BridgeMessages.selfInFront), tool: tool.rawValue)
        }
        guard let pid = hands.target(), pid != Self.ownPID else {
            return .failed(Self.handsError("no_target", "no app in front other than Companion"),
                           tool: tool.rawValue)
        }
        if let spoken = hands.turn.pin(for: pid), spoken != pid {
            Log.app("hands: \(tool.rawValue) target_changed since the user spoke pid=\(pid)")
            return .failed(Self.handsError(
                "target_changed", "the app in front is not the one the user was in; "
                    + "ask the user to bring that app to the front, then retry"),
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
        let outcome: ParentToolOutcome
        if tool == .see {
            outcome = await runSee(arguments, hands: hands, pid: pid)
        } else if tool.isSight {
            outcome = await runSight(tool, call, arguments, hands: hands, pid: pid, bundle: bundle ?? "-")
        } else {
            let act = HandsAct(hands: hands, pid: pid, bundle: bundle ?? "-", tool: tool)
            switch tool {
            case .typeText: outcome = await hands.observing(pid: pid, titles: false) { await act.type(arguments) }
            case .pressKey: outcome = await hands.observing(pid: pid) { act.press(arguments) }
            case .focusWindow: outcome = act.raise(arguments)
            case .readFocused: outcome = act.read()
            case .openApp, .openURL, .openFile, .listApps, .readSkill, .look, .click, .scroll, .menu, .see:
                outcome = .failed(.notFound("not a hands tool: \(tool.rawValue)"), tool: tool.rawValue)
            }
        }
        // A lock that landed while acting: whatever happened, nobody saw it.
        guard tool.changesSomething, hands.locked() else { return outcome }
        Log.app("hands: \(tool.rawValue) session locked during the action pid=\(pid)")
        return .failed(Self.handsError(BridgeCode.screenLocked, BridgeMessages.lockedDuringAction),
                       target: outcome.target, tool: tool.rawValue)
    }
}

extension ScreenHands {
    /// Runs one hand action and closes its result with what changed. The
    /// watch opens before the action so nothing it causes is missed, and a
    /// failed action never pays the wait: nothing happened to observe.
    func observing(
        pid: Int32, titles: Bool = true, _ act: () async -> ParentToolOutcome
    ) async -> ParentToolOutcome {
        guard let changes else { return await act() }
        let watch = changes.begin(pid: pid)
        var outcome = await act()
        guard outcome.ok else {
            watch.cancel()
            return outcome
        }
        let report = await watch.settle(.standard)
        outcome.output += "\n" + ChangeSummary.line(report, titles: titles)
        return outcome
    }
}

/// One call of the hands against one captured pid. Logs carry the tool,
/// counts, pid and bundle id — never the text typed or read.
private struct HandsAct {
    let hands: ScreenHands
    let pid: Int32
    let bundle: String
    let tool: ParentTool

    /// The front app moved mid-action: its ids are no longer worth anything.
    static let appMoved = "the app in front changed; call look again, then act on the app you mean"

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
        case .failure(let error) where error.code == "no_focused_field" && hands.screen != nil:
            // A bare failure was retried as-is; menu is the way out, and it
            // is offered only with sight.
            return fail(error.code, error.message + "; if it needs a new document, create it with "
                + "menu (e.g. File > New Note, Archivo > Nueva nota) and type again")
        case .failure(let error): return fail(error.code, error.message)
        case .success(let found): target = found
        }
        guard !moved else { return fail("target_changed", Self.appMoved) }
        // What the field holds before typing, read the way `read_focused`
        // reads it: the proof is that the text shows up MORE times after.
        let before = hands.reader.read(pid: pid).map {
            TypedProof.occurrences(of: text, in: FocusedText.clip($0))
        }
        switch await hands.injector.inject(text, into: target) {
        case .injected(let count, let route):
            Log.app("hands: type_text typed chars=\(count) via=\(route.rawValue) pid=\(pid)")
            return ParentToolOutcome(
                ok: true, output: "typed \(count) chars" + TypedProof.unverifiedNote,
                tool: tool.rawValue, fieldPID: pid, typedBefore: before)
        case .failed(.needsAccessibility):
            return fail("needs_accessibility", BridgeMessages.needsAccessibility)
        case .failed(.fieldGone):
            return fail("target_changed", Self.appMoved)
        case .failed(.refused):
            return fail("refused", "the field did not accept the text")
        }
    }

    func press(_ arguments: [String: Any]) -> ParentToolOutcome {
        let raw = arguments["key"] as? String ?? ""
        switch KeyChord.parse(raw) {
        case .refused(let error): return .failed(error, tool: tool.rawValue)
        case .chord(let chord): return press(chord: chord)
        case .plain: break
        }
        let key: NamedKey
        do {
            key = try NamedKey.parse(raw)
        } catch {
            return .failed(error, tool: tool.rawValue)
        }
        guard !moved else { return fail("target_changed", Self.appMoved, target: key.rawValue) }
        guard hands.keys.press(key, pid: pid) else {
            return fail("refused", "the key could not be sent", target: key.rawValue)
        }
        Log.app("hands: press_key \(key.rawValue) pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(
            ok: true, output: "pressed \(key.rawValue)", target: key.rawValue, tool: tool.rawValue)
    }

    /// A shortcut is a command to the app, not text: a terminal or an agent
    /// chat gets none of them, however harmless the letter looks.
    private func press(chord: KeyChord) -> ParentToolOutcome {
        guard !CommandApps.isCommandApp(bundleID: bundle) else {
            return fail("chord_not_allowed", "shortcuts are not sent to a command app", target: chord.name)
        }
        guard !moved else { return fail("target_changed", "the app in front changed", target: chord.name) }
        guard hands.keys.press(chord: chord, pid: pid) else {
            return fail("refused", "the shortcut could not be sent", target: chord.name)
        }
        Log.app("hands: press_key chord pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(
            ok: true, output: "pressed \(chord.name)", target: chord.name, tool: tool.rawValue)
    }

    func raise(_ arguments: [String: Any]) -> ParentToolOutcome {
        let query = (arguments["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .failed(.invalidArgs("missing title"), tool: tool.rawValue) }
        guard !moved else { return fail("target_changed", Self.appMoved, target: query) }
        guard let title = hands.windows.raise(titleContaining: query, pid: pid) else {
            return fail("window_not_found", "no window whose title contains \"\(query)\"", target: query)
        }
        guard !moved else {
            return fail(BridgeCode.foregroundUnavailable, BridgeMessages.foregroundUnavailable, target: title)
        }
        Log.app("hands: focus_window raised pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(ok: true, output: "raised \(title)", target: title, tool: tool.rawValue)
    }

    func read() -> ParentToolOutcome {
        switch field() {
        case .failure(let error): return fail(error.code, error.message)
        case .success: break
        }
        guard !moved else { return fail("target_changed", Self.appMoved) }
        guard let text = hands.reader.read(pid: pid) else {
            return fail("no_focused_field", "the focused field has no readable text")
        }
        let clipped = FocusedText.clip(text)
        Log.app("hands: read_focused chars=\(clipped.count) pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(ok: true, output: clipped, tool: tool.rawValue, fieldPID: pid)
    }
}
