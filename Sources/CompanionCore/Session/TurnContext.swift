import Foundation

/// How the turn arrived. The reducer has known this since Wave 3
/// (`TurnSnapshot.typedTurn`); the model never did (Wave 10a).
package enum TurnSource: String, Sendable, Equatable {
    case voice, typed
}

/// What the clipboard holds, summarized. The kind always travels; the
/// preview is a bounded prefix and never the whole board.
package struct ClipboardSummary: Sendable, Equatable {
    package enum Kind: String, Sendable, Equatable {
        case text, image, files
    }

    package var kind: Kind
    package var preview: String

    package init(kind: Kind, preview: String) {
        self.kind = kind
        self.preview = preview
    }
}

/// What the app perceived around one turn: the source it came from, when,
/// and what was on the user's screen. Sensed for the current turn only,
/// rendered by `ContextBlock`, never persisted (spec 10a §4).
package struct TurnContext: Sendable, Equatable {
    package var source: TurnSource
    package var timestamp: Date
    /// Seconds since the previous sensed turn: the "you interrupted me,
    /// pick up without repeating" hint of the corpus (spec 06).
    package var sinceLastTurn: TimeInterval?
    package var focusedApp: String?
    package var openDocuments: [String]
    package var clipboard: ClipboardSummary?
    /// Compact screen brief from the sidecar (Wave 13a). Never a JPEG.
    package var screenSummary: String?
    package var screenSnippets: [ScreenSnippet]
    package var screenPending: Bool
    /// HIGH-2/M2 (2026-09-25): `screenSummary` carried over from a previous
    /// turn's late vision call — it describes a moment ago, not now.
    package var screenStale: Bool
    /// Wave 15b-11: this turn follows one the user cut short (a press mid
    /// `.thinking`/`.speaking`). Rendered as `<steer>`, our own prose — never
    /// the model's words repeated back to it.
    package var interrupted: Bool
    /// Wave 16o-3: what the cursor rested on while the user spoke.
    package var pointed: [PointedElement]
    /// Wave 16h-3: the window in front of the app in front, and the city the
    /// user is in. Sensed per turn, never persisted.
    package var focusedWindow: String?
    package var location: UserLocation?
    /// Wave 16h-3: what happened on the island since the last turn.
    package var islandEvents: [IslandEvent]
    /// The last fact in `islandEvents`, for the acknowledgement that follows
    /// building the prompt.
    package var islandEventsThrough: Int

    package init(
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
        pointed: [PointedElement] = [],
        focusedWindow: String? = nil,
        location: UserLocation? = nil,
        islandEvents: [IslandEvent] = [],
        islandEventsThrough: Int = 0
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
        self.focusedWindow = focusedWindow
        self.location = location
        self.islandEvents = islandEvents
        self.islandEventsThrough = islandEventsThrough
    }
}

/// A verbatim fragment visible on screen, tagged with the app it sat in.
package struct ScreenSnippet: Sendable, Equatable {
    package var app: String
    package var text: String

    package init(app: String, text: String) {
        self.app = app
        self.text = text
    }
}

/// What the sidecar produced for one hold. `pending` means the vision call
/// did not land in time; the turn still goes.
package struct ScreenBrief: Sendable, Equatable {
    package var summary: String?
    package var snippets: [ScreenSnippet]
    package var pending: Bool
    /// HIGH-2/M2: this summary was captured for an earlier turn and carried
    /// into this one — a moment ago, not now.
    package var stale: Bool
    /// Wave 16o-3: sampled from press to commit alongside the AX harvest.
    package var pointed: [PointedElement] = []

    package init(
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
package enum ScreenTextSnippets {
    package static let maxSnippets = 12
    package static let maxChars = 80

    package static func snippets(from texts: [String], app: String) -> [ScreenSnippet] {
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
package protocol ScreenSeeing: Sendable {
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
    package func axSnippets() async -> [ScreenSnippet] { [] }
    package func beginPointing() {}
}

/// Each channel is opt-out (corpus spec 09). The clipboard is born off:
/// reading it unasked is exactly what macOS 15 warns the user about.
package struct ContextChannels: OptionSet, Sendable, Equatable {
    package let rawValue: Int

    package init(rawValue: Int) {
        self.rawValue = rawValue
    }

    package static let focusedApp = ContextChannels(rawValue: 1 << 0)
    package static let openDocuments = ContextChannels(rawValue: 1 << 1)
    package static let clipboard = ContextChannels(rawValue: 1 << 2)
    package static let screen = ContextChannels(rawValue: 1 << 3)
    /// 16h-3: the city rides with every request. The system permission is
    /// asked only by a nearby search, never by this channel.
    package static let location = ContextChannels(rawValue: 1 << 4)

    package static let `default`: ContextChannels = [.focusedApp, .openDocuments, .screen, .location]
    package static let all: ContextChannels = [.focusedApp, .openDocuments, .clipboard, .screen, .location]
}

/// The perception port. Never throws: a channel that is off, unpermitted or
/// failing comes back empty, and the whole call ends within its budget —
/// the turn cannot wait for the Accessibility tree of a busy app.
package protocol ContextSensing: Sendable {
    func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext
    /// Whoever builds the prompt calls this after it carried `ctx`'s island
    /// events; sensing alone never consumes them.
    func acknowledgeIslandEvents(through: Int)
}

extension ContextSensing {
    package func acknowledgeIslandEvents(through: Int) {}
}
