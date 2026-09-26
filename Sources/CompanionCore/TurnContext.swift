import Foundation

/// How the turn arrived. The reducer has known this since Wave 3
/// (`TurnSnapshot.typedTurn`); the model never did (Wave 10a).
public enum TurnSource: String, Sendable, Equatable {
    case voice, typed
}

/// What the clipboard holds, summarized. The kind always travels; the
/// preview is a bounded prefix and never the whole board.
public struct ClipboardSummary: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case text, image, files
    }

    public var kind: Kind
    public var preview: String

    public init(kind: Kind, preview: String) {
        self.kind = kind
        self.preview = preview
    }
}

/// What the app perceived around one turn: the source it came from, when,
/// and what was on the user's screen. Sensed for the current turn only,
/// rendered by `ContextBlock`, never persisted (spec 10a §4).
public struct TurnContext: Sendable, Equatable {
    public var source: TurnSource
    public var timestamp: Date
    /// Seconds since the previous sensed turn: the "you interrupted me,
    /// pick up without repeating" hint of the corpus (spec 06).
    public var sinceLastTurn: TimeInterval?
    public var focusedApp: String?
    public var openDocuments: [String]
    public var clipboard: ClipboardSummary?
    /// Compact screen brief from the sidecar (Wave 13a). Never a JPEG.
    public var screenSummary: String?
    public var screenSnippets: [ScreenSnippet]
    public var screenPending: Bool
    /// HIGH-2/M2 (2026-09-25): `screenSummary` carried over from a previous
    /// turn's late vision call — it describes a moment ago, not now.
    public var screenStale: Bool
    /// Wave 15b-11: this turn follows one the user cut short (a press mid
    /// `.thinking`/`.speaking`). Rendered as `<steer>`, our own prose — never
    /// the model's words repeated back to it.
    public var interrupted: Bool
    /// Wave 16o-3: what the cursor rested on while the user spoke.
    public var pointed: [PointedElement]

    public init(
        source: TurnSource,
        timestamp: Date = Date(),
        sinceLastTurn: TimeInterval? = nil,
        focusedApp: String? = nil,
        openDocuments: [String] = [],
        clipboard: ClipboardSummary? = nil,
        screenSummary: String? = nil,
        screenSnippets: [ScreenSnippet] = [],
        screenPending: Bool = false,
        screenStale: Bool = false,
        interrupted: Bool = false,
        pointed: [PointedElement] = []
    ) {
        self.source = source
        self.timestamp = timestamp
        self.sinceLastTurn = sinceLastTurn
        self.focusedApp = focusedApp
        self.openDocuments = openDocuments
        self.clipboard = clipboard
        self.screenSummary = screenSummary
        self.screenSnippets = screenSnippets
        self.screenPending = screenPending
        self.screenStale = screenStale
        self.interrupted = interrupted
        self.pointed = pointed
    }
}

/// A verbatim fragment visible on screen, tagged with the app it sat in.
public struct ScreenSnippet: Sendable, Equatable {
    public var app: String
    public var text: String

    public init(app: String, text: String) {
        self.app = app
        self.text = text
    }
}

/// What the sidecar produced for one hold. `pending` means the vision call
/// did not land in time; the turn still goes.
public struct ScreenBrief: Sendable, Equatable {
    public var summary: String?
    public var snippets: [ScreenSnippet]
    public var pending: Bool
    /// HIGH-2/M2: this summary was captured for an earlier turn and carried
    /// into this one — a moment ago, not now.
    public var stale: Bool
    /// Wave 16o-3: sampled from press to commit alongside the AX harvest.
    public var pointed: [PointedElement] = []

    public init(
        summary: String? = nil, snippets: [ScreenSnippet] = [], pending: Bool = false,
        stale: Bool = false
    ) {
        self.summary = summary
        self.snippets = snippets
        self.pending = pending
        self.stale = stale
    }
}

/// AX text turned into what the model reads: capped, deduped, one line
/// each, tagged with the app it came from. Pure — the AX walk (Services,
/// `AXScreenText`) hands raw strings, this never touches AppKit or
/// ApplicationServices (spec 15b-6).
public enum ScreenTextSnippets {
    public static let maxSnippets = 12
    public static let maxChars = 80

    public static func snippets(from texts: [String], app: String) -> [ScreenSnippet] {
        var seen = Set<String>()
        var out: [ScreenSnippet] = []
        for raw in texts {
            guard out.count < maxSnippets else { break }
            let flat = flatten(raw).trimmingCharacters(in: .whitespaces)
            guard !flat.isEmpty, seen.insert(flat).inserted else { continue }
            out.append(ScreenSnippet(app: app, text: cut(flat)))
        }
        return out
    }

    private static func cut(_ text: String) -> String {
        guard text.unicodeScalars.count > maxChars else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxChars)))
    }

    /// Newlines and control characters collapse to a space: a raw AX value
    /// can carry a whole paragraph's line breaks and would otherwise read as
    /// several entries once rendered (same rule as `ContextBlock.flatten`).
    private static func flatten(_ text: String) -> String {
        let breaks = CharacterSet.newlines.union(.controlCharacters)
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            out.append(breaks.contains(scalar) ? " " : scalar)
        }
        return String(out)
    }
}

/// Capture + vision, started on press, collected at commit.
public protocol ScreenSeeing: Sendable {
    func begin(app: String?)
    func cancel()
    /// The AX harvest (15b-6), already running since press: bounded by its
    /// own budget, so awaiting it never pays vision's wait. `ClassicRuntime`
    /// reads this BEFORE deciding whether to wait for vision at all
    /// (spec 15b-7b) — a default keeps every fake that predates it compiling.
    func axSnippets() async -> [ScreenSnippet]
    func finish(wait: Duration) async -> ScreenBrief
    /// Wave 16o-3: what the cursor points at, sampled locally from the
    /// confirmed hold to `finish`. Separate from `begin`, which uploads.
    func beginPointing()
}

extension ScreenSeeing {
    public func axSnippets() async -> [ScreenSnippet] { [] }
    public func beginPointing() {}
}

/// Each channel is opt-out (corpus spec 09). The clipboard is born off:
/// reading it unasked is exactly what macOS 15 warns the user about.
public struct ContextChannels: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let focusedApp = ContextChannels(rawValue: 1 << 0)
    public static let openDocuments = ContextChannels(rawValue: 1 << 1)
    public static let clipboard = ContextChannels(rawValue: 1 << 2)
    public static let screen = ContextChannels(rawValue: 1 << 3)

    public static let `default`: ContextChannels = [.focusedApp, .openDocuments, .screen]
    public static let all: ContextChannels = [.focusedApp, .openDocuments, .clipboard, .screen]
}

/// The perception port. Never throws: a channel that is off, unpermitted or
/// failing comes back empty, and the whole call ends within its budget —
/// the turn cannot wait for the Accessibility tree of a busy app.
public protocol ContextSensing: Sendable {
    func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext
}
