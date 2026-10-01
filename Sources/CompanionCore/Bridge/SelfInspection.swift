import Foundation

// Read-only self-inspection contract (spec self-qa-inspeccion, PR-1). Nothing
// here is served yet: the runner, the allowlist and the UI source land in
// later PRs. The shape is the guarantee: the port has no method that writes,
// and every output type carries case names, counts and lengths, never the
// user's words (R1-R8, D1-D5).

package enum CompanionTool: String, CaseIterable, Sendable {
    case state = "companion_state"
    case island = "companion_island"
    case settings = "companion_settings"
    case thread = "companion_thread"
    case lastMessageMatches = "companion_last_message_matches"
    case log = "companion_log"

    /// The name is wire contract and never translates; the description is
    /// read by the agent and follows the language of the answer.
    package func spec(_ language: AppLanguage) -> ToolSpec {
        ToolSpec(
            name: rawValue,
            description: Self.description(self, language) + " " + BridgeCopy.toolDataSuffix(language),
            properties: properties(language),
            required: self == .lastMessageMatches ? ["expected"] : [])
    }

    private func properties(_ language: AppLanguage) -> [ToolProperty] {
        switch self {
        case .log:
            [ToolProperty(
                name: "lines", type: "integer",
                description: language == .es
                    ? "cuántas líneas finales (50 por defecto, máximo 200)"
                    : "how many trailing lines (default 50, max 200)")]
        case .lastMessageMatches:
            [ToolProperty(
                name: "expected", type: "string",
                description: language == .es
                    ? "el texto que se espera que sea el último mensaje de la usuaria"
                    : "the text expected to be the user's last message")]
        case .state, .island, .settings, .thread:
            []
        }
    }

    private static func description(_ tool: CompanionTool, _ language: AppLanguage) -> String {
        switch (tool, language) {
        case (.state, .en):
            "Companion's own session: kind and phase, voice, pipeline, job and approval counts, "
                + "notice and card names. Read-only; carries no text from the conversation. "
                + "handsActing reflects this very inspection."
        case (.state, .es):
            "La sesión de Companion: tipo y fase, voz, pipeline, conteos de trabajo y aprobación, "
                + "nombres de aviso y tarjetas. Solo lectura; no lleva texto de la conversación. "
                + "handsActing refleja esta misma inspección."
        case (.island, .en):
            "What the island is painting now: size, meter, line name, text lengths, light and action. "
                + "Read-only; texts come back as lengths."
        case (.island, .es):
            "Lo que la isla pinta ahora: tamaño, medidor, nombre de línea, longitudes de texto, luz y "
                + "acción. Solo lectura; los textos vuelven como longitudes."
        case (.settings, .en):
            "Companion's non-secret settings. Read-only; free text such as name or instructions "
                + "comes back as a length, and no key or credential is ever included."
        case (.settings, .es):
            "Los ajustes no secretos de Companion. Solo lectura; el texto libre como nombre o "
                + "instrucciones vuelve como longitud, y nunca incluye claves ni credenciales."
        case (.thread, .en):
            "The active conversation as metadata: role, origin, flags, length and detected language "
                + "per message. Read-only; the words themselves are never returned."
        case (.thread, .es):
            "La conversación activa como metadatos: rol, origen, marcas, longitud e idioma detectado "
                + "por mensaje. Solo lectura; las palabras nunca se devuelven."
        case (.lastMessageMatches, .en):
            "Answers only true or false: whether the user's last message equals the expected text "
                + "(surrounding whitespace ignored, case sensitive). Limited to 10 checks per minute."
        case (.lastMessageMatches, .es):
            "Responde solo true o false: si el último mensaje de la usuaria es igual al texto esperado "
                + "(sin contar espacios de los extremos, distingue mayúsculas). Máximo 10 por minuto."
        case (.log, .en):
            "The last lines of Companion's main log (default 50, max 200). Read-only."
        case (.log, .es):
            "Las últimas líneas del log principal de Companion (50 por defecto, máximo 200). Solo lectura."
        }
    }
}

/// Read port. No method writes anything: R1/R3/R8 by shape.
package protocol SelfInspecting: Sendable {
    func session() async -> SessionProjection
    func island() async -> PaintedIsland?
    func screen() async -> InspectedScreen?
    func settings() async -> SettingsInspection
    func activeThread() async -> [ThreadMessageInput]
}

/// What the view last painted, mirrored as it was drawn rather than rebuilt.
/// `catalogText` is the copy-catalog sentence for the line, set only when the
/// line carries no user content.
package struct PaintedIsland: Sendable, Equatable {
    package var state: IslandState
    package var catalogText: String?

    package init(state: IslandState, catalogText: String?) {
        self.state = state
        self.catalogText = catalogText
    }
}

package enum ThreadMessageOrigin: String, Sendable, Equatable {
    case typed, choice
}

/// A message with its words. Not Encodable on purpose, and printing it shows
/// a length: nothing built from it can serialize the text by accident.
package struct ThreadMessageInput: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    package let role: TurnRole?
    package let isStatus: Bool
    package let origin: ThreadMessageOrigin
    package let isFailure: Bool
    package let restored: Bool
    package let attachments: Int
    package let text: String

    package init(
        role: TurnRole?, isStatus: Bool, origin: ThreadMessageOrigin, isFailure: Bool,
        restored: Bool, attachments: Int, text: String
    ) {
        self.role = role
        self.isStatus = isStatus
        self.origin = origin
        self.isFailure = isFailure
        self.restored = restored
        self.attachments = attachments
        self.text = text
    }

    package var description: String { "<thread message: \(text.count) chars>" }
    package var debugDescription: String { description }
    /// `dump` and `Mirror` read stored properties, not descriptions.
    package var customMirror: Mirror { Mirror(self, children: []) }
}

/// The equality oracle (D3): a bool against the last user message, never the
/// message. Canonical String equality, trimmed at the ends, case sensitive.
package enum LastMessageMatch {
    package static let maxExpectedScalars = 2_000

    package static func matches(_ expected: String, in thread: [ThreadMessageInput]) -> Bool {
        let wanted = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty probe would turn the oracle into "did the user type anything".
        guard !wanted.isEmpty, expected.unicodeScalars.count <= maxExpectedScalars else { return false }
        guard let last = lastUserIndex(in: thread) else { return false }
        return thread[last].text.trimmingCharacters(in: .whitespacesAndNewlines) == wanted
    }

    /// Identity of the message being probed: a hash of its text and position,
    /// so the text itself is never kept. Per-process seed, never persisted.
    package static func messageKey(in thread: [ThreadMessageInput]) -> Int? {
        guard let index = lastUserIndex(in: thread) else { return nil }
        var hasher = Hasher()
        hasher.combine(thread[index].text)
        hasher.combine(index)
        return hasher.finalize()
    }

    private static func lastUserIndex(in thread: [ThreadMessageInput]) -> Int? {
        thread.lastIndex { $0.role == .user && !$0.isStatus }
    }
}

package enum EqualityCheckAdmission: Sendable, Equatable {
    case admitted, rateLimited, exhausted
}

/// Sliding window over the equality checks, same shape as `BridgeSheetLimit`,
/// plus a total budget per user message. A refused check is not recorded, so
/// probing cannot extend its own lockout.
///
/// PR-2 contract for the runner: check admission BEFORE validating the
/// expected text (empty or oversize probes must spend budget too, or they are
/// a free side channel), and hold ONE shared instance per process, not one
/// per connection or per call.
package struct EqualityCheckLimit: Sendable, Equatable {
    package static let perMinute = 10
    package static let perMessage = 30
    package static let window: TimeInterval = 60

    private var admitted: [Date] = []
    private var currentKey: Int?
    private var spentOnCurrent = 0

    package init() {}

    package mutating func admit(now: Date) -> Bool {
        admit(now: now, messageKey: nil) == .admitted
    }

    /// `messageKey` identifies the message being probed (`LastMessageMatch.messageKey`);
    /// a different key starts a fresh budget, which is how a new user message resets it.
    package mutating func admit(now: Date, messageKey: Int?) -> EqualityCheckAdmission {
        if messageKey != currentKey {
            currentKey = messageKey
            spentOnCurrent = 0
        }
        if messageKey != nil, spentOnCurrent >= Self.perMessage { return .exhausted }
        let cutoff = now.addingTimeInterval(-Self.window)
        admitted = admitted.filter { $0 > cutoff }
        guard admitted.count < Self.perMinute else { return .rateLimited }
        admitted.append(now)
        spentOnCurrent += 1
        return .admitted
    }
}

extension IslandState.Line {
    /// True when an associated value is text that can hold user or model
    /// content. Exhaustive on purpose: a new case must say which side it is on.
    package var carriesText: Bool {
        switch self {
        case .none, .holdHint, .keyBlocked, .pending, .thinking, .speaking, .completed,
             .couldntHear, .permission, .failure, .pasting, .transcriptsDebug, .cancelled,
             .dropZones, .replyCut:
            false
        case .acting, .job, .dictating, .dictated, .dictationResult, .updateAvailable,
             .followUp, .connectApp, .signInApp, .chatError, .receipt:
            true
        }
    }

    var textLengths: [Int] {
        switch self {
        case .acting(let targets): targets.map(\.count)
        case .job(let goal, let step, _): [goal?.count, step?.count].compactMap { $0 }
        case .dictating(let text), .dictated(let text), .followUp(let text), .chatError(let text):
            [text.count]
        case .dictationResult(let app, let text): [app.count, text.value.count]
        case .updateAvailable(let tag): [tag.count]
        case .connectApp(let slug, let name), .signInApp(let slug, let name): [slug.count, name.count]
        case .receipt(let receipt): receipt.lines.map(\.count)
        case .none, .holdHint, .keyBlocked, .pending, .thinking, .speaking, .completed,
             .couldntHear, .permission, .failure, .pasting, .transcriptsDebug, .cancelled,
             .dropZones, .replyCut:
            []
        }
    }
}

/// Case name of an enum value without its payload. Reflection, so a new case
/// is named for free; the tests pin every name that is on the wire.
func inspectionCaseName(_ value: Any) -> String {
    Mirror(reflecting: value).children.first?.label ?? String(describing: value)
}

package struct InspectedScreen: Sendable, Encodable, Equatable {
    package var settingsOpen: Bool
    package var settingsTab: String?
    package var page: String

    package init(settingsOpen: Bool, settingsTab: String?, page: String) {
        self.settingsOpen = settingsOpen
        self.settingsTab = settingsTab
        self.page = page
    }
}
