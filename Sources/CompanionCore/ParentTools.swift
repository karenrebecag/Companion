import Foundation

/// The error as contract (corpus LAYERING §3): a stable `code` the model
/// recovers by — `denied_path` means "ask for another path", never "give up
/// and delegate around it" — and a message the human reads.
public struct ContractError: Error, Sendable, Equatable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public static func deniedURL(_ message: String) -> ContractError {
        ContractError(code: "denied_url", message: message)
    }

    public static func deniedPath(_ message: String) -> ContractError {
        ContractError(code: "denied_path", message: message)
    }

    public static func invalidArgs(_ message: String) -> ContractError {
        ContractError(code: "invalid_args", message: message)
    }

    public static func notFound(_ message: String) -> ContractError {
        ContractError(code: "not_found", message: message)
    }

    /// The user said no (Wave 10c 3B.4): an instruction not to retry or
    /// route around, with the code first so the model can act on it.
    /// One shape for the sheet's denial in Services and in UI (12d).
    public static func deniedByUser(_ language: AppLanguage = .en) -> ContractError {
        ContractError(code: "denied_by_user", message: Escalation.deniedByUserMessage(language))
    }

    /// Code first, so a model parsing the result finds it without reading
    /// prose. Changing this shape changes the model's API.
    public var wire: String { "\(code): \(message)" }
}

/// What the conversational turn can do by itself. Opening and looking are
/// the parent's; reading, writing and running stay with the specialist and
/// its sandbox (corpus spec 24 §5, PRODUCT-DECISIONS §7). None of these asks
/// permission: the user just said it out loud, and the risk — an invented URL
/// or path — is the validator's to catch, not a sheet's.
public enum ParentTool: String, CaseIterable, Sendable, Equatable {
    case openApp = "open_app"
    case openURL = "open_url"
    case openFile = "open_file"
    case listApps = "list_apps"
    /// Read-only, by catalog name, never by path (Wave 11a §3.3): the
    /// parent's equivalent of the specialist's read_file on a skill.
    case readSkill = "read_skill"
    /// The hands (Wave 15g): act on the app the user was in, only with
    /// Accessibility granted, so they are declared apart from the rest.
    case typeText = "type_text"
    case pressKey = "press_key"
    case focusWindow = "focus_window"
    case readFocused = "read_focused"
    /// The sight (Wave 16a): read the window as numbered elements and press
    /// one. Hands too — they need Accessibility and act on the same app.
    case look
    case click
    case scroll
    case menu
    /// Pixels, on demand (16a-3): a capture described by the vision model.
    case see

    public var isHands: Bool {
        switch self {
        case .typeText, .pressKey, .focusWindow, .readFocused: true
        case .look, .click, .scroll, .menu, .see: true
        case .openApp, .openURL, .openFile, .listApps, .readSkill: false
        }
    }

    /// Offered only when the runner has a screen adapter behind them.
    public var isSight: Bool {
        switch self {
        case .look, .click, .scroll, .menu: true
        default: false
        }
    }

    /// The argument the status line names. `list_apps` has none.
    /// What the call is about ("Safari", a URL), for the line shown before
    /// it runs and for the session's `parentActing`. Empty when unreadable.
    public static func target(of call: ToolCallRef) -> String {
        guard let key = ParentTool(rawValue: call.name)?.targetKey,
              let object = ToolArguments.parse(call.arguments)
        else { return "" }
        return (object[key] as? String) ?? ""
    }

    public var targetKey: String? {
        switch self {
        case .openApp: "name"
        case .openURL: "url"
        case .openFile: "path"
        case .listApps: nil
        case .readSkill: "name"
        // Never "text" or "title": the status line and the chrome would show
        // what was typed into another app, or the name of a private window.
        // Nor the key: "Opening return…" says nothing (review 2026-09-25).
        case .typeText, .readFocused, .pressKey, .focusWindow: nil
        // Never the button's label either: the status line is saved.
        case .look, .click, .scroll, .menu, .see: nil
        }
    }

    /// The tools every runner offers. The hands are not here: they exist
    /// only with Accessibility granted (`handsSpecs`).
    public static func specs(_ language: AppLanguage) -> [ToolSpec] {
        allCases.filter { !$0.isHands }.map { $0.spec(language) }
    }

    public static func handsSpecs(
        _ language: AppLanguage, sight: Bool = false, see: Bool = false
    ) -> [ToolSpec] {
        allCases.filter { tool in
            guard tool.isHands else { return false }
            if tool == .see { return see }
            return sight || !tool.isSight
        }.map { $0.spec(language) }
    }

    /// Names are wire contract; descriptions follow the answer language, as
    /// the delegate spec does.
    public func spec(_ language: AppLanguage) -> ToolSpec {
        switch (self, language) {
        case (.openApp, .en):
            return ToolSpec(
                name: rawValue,
                description: "Open or bring to the front an application on "
                    + "this Mac, by name. Use list_apps if unsure of the name.",
                properties: [ToolProperty(
                    name: "name", type: "string",
                    description: "the app's name, e.g. Safari")],
                required: ["name"])
        case (.openApp, .es):
            return ToolSpec(
                name: rawValue,
                description: "Abre o trae al frente una aplicación de esta "
                    + "Mac, por nombre. Usa list_apps si dudas del nombre.",
                properties: [ToolProperty(
                    name: "name", type: "string",
                    description: "el nombre de la app, p. ej. Safari")],
                required: ["name"])
        case (.openURL, .en):
            return ToolSpec(
                name: rawValue,
                description: "Open an http or https URL in the user's "
                    + "default browser.",
                properties: [ToolProperty(
                    name: "url", type: "string",
                    description: "full URL, http or https")],
                required: ["url"])
        case (.openURL, .es):
            return ToolSpec(
                name: rawValue,
                description: "Abre una URL http o https en el navegador "
                    + "predeterminado de la usuaria.",
                properties: [ToolProperty(
                    name: "url", type: "string",
                    description: "URL completa, http o https")],
                required: ["url"])
        case (.openFile, .en):
            return ToolSpec(
                name: rawValue,
                description: "Open a file or folder inside the user's home "
                    + "with its default app (a folder opens in Finder). "
                    + "Hidden files and paths outside home are refused.",
                properties: [ToolProperty(
                    name: "path", type: "string",
                    description: "path under the home folder, e.g. ~/Downloads")],
                required: ["path"])
        case (.openFile, .es):
            return ToolSpec(
                name: rawValue,
                description: "Abre un archivo o carpeta dentro de la carpeta "
                    + "personal con su app predeterminada (una carpeta se "
                    + "abre en Finder). Se niegan los ocultos y lo que está "
                    + "fuera de home.",
                properties: [ToolProperty(
                    name: "path", type: "string",
                    description: "ruta bajo la carpeta personal, p. ej. ~/Downloads")],
                required: ["path"])
        case (.listApps, .en):
            return ToolSpec(
                name: rawValue,
                description: "List the applications on this Mac: running "
                    + "ones first, then installed. Use it to get an exact "
                    + "name before open_app.",
                properties: [], required: [])
        case (.listApps, .es):
            return ToolSpec(
                name: rawValue,
                description: "Lista las aplicaciones de esta Mac: primero las "
                    + "que corren, luego las instaladas. Úsala para tener el "
                    + "nombre exacto antes de open_app.",
                properties: [], required: [])
        case (.readSkill, .en):
            return ToolSpec(
                name: rawValue,
                description: "Read the instructions of a skill or a knowledge "
                    + "entry listed in <active_skills> / <active_knowledge>, by "
                    + "its exact name. Read before following a skill; never "
                    + "guess its content.",
                properties: [ToolProperty(
                    name: "name", type: "string",
                    description: "the name as listed, e.g. writing-content")],
                required: ["name"])
        case (.readSkill, .es):
            return ToolSpec(
                name: rawValue,
                description: "Lee las instrucciones de una skill o una entrada "
                    + "de knowledge listada en <active_skills> / "
                    + "<active_knowledge>, por su nombre exacto. Lee antes de "
                    + "seguir una skill; nunca supongas su contenido.",
                properties: [ToolProperty(
                    name: "name", type: "string",
                    description: "el nombre tal como está listado, p. ej. writing-content")],
                required: ["name"])
        case (.typeText, _), (.pressKey, _), (.focusWindow, _), (.readFocused, _):
            return handsSpec(language)
        case (.look, _), (.click, _), (.scroll, _), (.menu, _), (.see, _):
            return sightSpec(language)
        }
    }
}

/// The parent's only way to touch the system. No `Process`, no `open -a`,
/// no PATH: an adapter over NSWorkspace, or a fake that opens nothing.
public protocol WorkspaceOpening: Sendable {
    func openApplication(named name: String) async throws(ContractError)
    /// http(s) or file://. Validated before it gets here.
    func open(_ url: URL) async throws(ContractError)
    func runningApplications() -> [String]
    func installedApplications() -> [String]
}

/// What a parent tool produced: `output` is what the model reads, `target`
/// what the status line names, `card` what the interface paints on its own
/// channel. Lives in Core because the chat layer cannot see Services.
public struct ParentToolOutcome: Sendable, Equatable {
    public var ok: Bool
    public var output: String
    public var target: String
    public var card: Card?
    /// Which tool produced it, when the copy needs to know (11a).
    public var tool: String?

    public init(ok: Bool, output: String, target: String = "", card: Card? = nil,
                tool: String? = nil) {
        self.ok = ok
        self.output = output
        self.target = target
        self.card = card
        self.tool = tool
    }

    public static func failed(_ error: ContractError, target: String = "",
                              tool: String? = nil) -> ParentToolOutcome {
        ParentToolOutcome(ok: false, output: error.wire, target: target, tool: tool)
    }
}

/// The seam the three paths (chat, realtime, classic) call. A tool the
/// runner does not back is not in `specs`, and `handles` says no.
public protocol ParentToolExecuting: Sendable {
    func specs(_ language: AppLanguage) -> [ToolSpec]
    func handles(_ name: String) -> Bool
    /// Why a tool that exists is not served right now (`self_in_front`,
    /// `needs_accessibility`, `not_available`), nil for a name that is not
    /// a tool or one that is ready.
    func unavailability(for name: String) -> String?
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome
    /// The sheet this call needs before `execute`, or nil. Every path asks
    /// the runner, not `ParentToolGate` directly: only the runner knows the
    /// app it would act on (a terminal makes Return a command, Wave 15g).
    func approval(for call: ToolCallRef, said: String) -> ApprovalRequest?
    /// The request as the sheet and the memory see it, with what only the
    /// runner can resolve (the workbook a write would land in). Async: it asks
    /// the app. Called between `approval` and the sheet.
    func bound(_ request: ApprovalRequest) async -> ApprovalRequest
    /// The gate reports a yes, from the sheet or the session's memory. A
    /// runner that must not act unapproved (a terminal) acts only after it.
    func granted(_ request: ApprovalRequest)
    /// The user started a turn (a hold, a sent message): a runner that acts
    /// on another app pins the app that was in front now.
    func beginTurn()
    /// 16k-3: the turn's words, for runners whose tool list depends on
    /// what the user named (the connected apps' runner filters by the app
    /// the request names — spec §5's context budget rule).
    func noteTurn(_ said: String)
}

extension ParentToolExecuting {
    public func unavailability(for name: String) -> String? { nil }

    public func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        ParentToolGate.approval(for: call, said: said)
    }

    public func bound(_ request: ApprovalRequest) async -> ApprovalRequest { request }

    public func granted(_ request: ApprovalRequest) {}

    public func beginTurn() {}

    public func noteTurn(_ said: String) {}
}

/// The record of what the app did by itself, in the thread — same idea as
/// the job's record (9-0). Model-facing copy lives here, like `Escalation`,
/// because Services emits these lines too and cannot reach the catalog.
public enum ParentToolCopy: Sendable {
    public static func status(
        _ name: String, _ outcome: ParentToolOutcome, _ language: AppLanguage
    ) -> String {
        if let browser = BrowserTool(rawValue: name) {
            return BrowserCopy.status(browser, outcome, language)
        }
        guard outcome.ok else { return failed(outcome, language) }
        if let hands = ParentTool(rawValue: name), hands.isHands {
            return handsStatus(hands, outcome, language)
        }
        switch (ParentTool(rawValue: name), language) {
        case (.listApps, .en): return "Listed the apps on this Mac."
        case (.listApps, .es): return "Listé las apps de esta Mac."
        case (.readSkill, .en): return "Read the \(outcome.target) skill."
        case (.readSkill, .es): return "Leí la skill \(outcome.target)."
        case (.some, .en): return "Opened \(outcome.target)."
        case (.some, .es): return "Abrí \(outcome.target)."
        case (.none, .en): return "Done: \(name)."
        case (.none, .es): return "Hecho: \(name)."
        }
    }

    /// `failed` never got the tool's name; the outcome carries it since 11a
    /// so a read failure does not read as an open failure (code review).
    private static func name(of outcome: ParentToolOutcome) -> ParentTool? {
        outcome.tool.flatMap { ParentTool(rawValue: $0) }
    }

    private static func failed(_ outcome: ParentToolOutcome, _ language: AppLanguage) -> String {
        if let hands = name(of: outcome), hands.isHands {
            return handsFailed(hands, outcome, language)
        }
        if name(of: outcome) == .readSkill {
            switch language {
            case .en: return "Could not read the \(outcome.target) skill: \(outcome.output)"
            case .es: return "No pude leer la skill \(outcome.target): \(outcome.output)"
            }
        }
        let what = outcome.target.isEmpty ? "" : " \(outcome.target)"
        if outcome.output.hasPrefix("denied_by_user") {
            switch language {
            case .en: return "Did not open\(what): you said no."
            case .es: return "No abrí\(what): dijiste que no."
            }
        }
        switch language {
        case .en: return "Could not open\(what): \(outcome.output)"
        case .es: return "No pude abrir\(what): \(outcome.output)"
        }
    }

    /// Answered from the session's memory (Wave 10c 3D), no sheet shown.
    public static func remembered(_ name: String, approved: Bool, _ language: AppLanguage) -> String {
        switch (language, approved) {
        case (.en, true): "Allowed, as before: \(name)."
        case (.en, false): "Denied, as before: \(name)."
        case (.es, true): "Permitido, como antes: \(name)."
        case (.es, false): "Denegado, como antes: \(name)."
        }
    }

    /// Shown with the assistant's call when it said nothing before acting:
    /// the status line is the record of WHAT was asked, as the job's is.
    public static func acting(_ targets: [String], _ language: AppLanguage) -> String {
        let list = targets.filter { !$0.isEmpty }.joined(separator: ", ")
        switch language {
        case .en: return list.isEmpty ? "Acting…" : "Opening \(list)…"
        case .es: return list.isEmpty ? "Actuando…" : "Abriendo \(list)…"
        }
    }

    /// The round cap is a safety, not a goal; reaching it is recorded.
    /// A safety, not a goal. Wave 16a: look → click → look → type is four
    /// rounds before the answer; three only ever fit opening apps.
    public static let maxRounds = 8

    public static func roundCap(_ language: AppLanguage) -> String {
        switch language {
        case .en: "Stopped after \(maxRounds) actions in a row."
        case .es: "Me detuve tras \(maxRounds) acciones seguidas."
        }
    }
}
