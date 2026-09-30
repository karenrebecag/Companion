import CryptoKit
import Foundation

/// 16q-3: decides whether each write Companion is about to take is covered
/// by what the user said in that turn. The port never throws: a failure is
/// a verdict, and a failed verdict is never a covered one.
package protocol ActionJudging: Sendable {
    /// One verdict per action, in order.
    func judge(_ request: ActionJudgeRequest) async -> [JudgeVerdict]
}

// MARK: - The user's words

/// What the user said in the turn, from the trusted channel (the mic). A type
/// of its own so that no other string can reach the judge as "the user's
/// words", and so that printing anything that holds it never prints them.
package struct UserWords: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    package static let maxLength = 1000

    package let text: String

    /// nil when nothing is left after sanitising: there is nothing to judge.
    package init?(heard: String) {
        let clean = TextSanitizer.display(heard, maxLength: Self.maxLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        text = clean
    }

    package var description: String { "<user words: \(text.count) chars>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}

// MARK: - The action

/// The arguments of a proposed write reduced to what identifies its target.
/// Long texts (message bodies) travel as their length only: they are the
/// main vector for injecting the judge (D2).
package struct ActionSummary: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    package enum Value: Sendable, Equatable {
        case text(String)
        case number(Double)
        case bool(Bool)
        case list([String])
    }

    package let values: [String: Value]
    package let isComplete: Bool

    init(values: [String: Value], isComplete: Bool = true) {
        self.values = values
        self.isComplete = isComplete
    }

    package var description: String { "<action summary: \(values.count) keys>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}

/// SHA256 over the length-prefixed tool name and the canonical arguments. The
/// digest is the identity of "this exact action": one changed character is
/// another version. Length-prefixing the name (not a separator byte) is what
/// keeps a name that contains the separator from eating the arguments.
///
/// The tool name is hashed as it arrived, never as the judge is shown it: two
/// names that render alike are two actions.
package struct ActionVersion: Sendable, Hashable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    private static let canonicalMarker: UInt8 = 0x01
    private static let rawMarker: UInt8 = 0x00

    package let hex: String

    package init(toolName: String, argumentsJSON: String) {
        let name = Array(toolName.utf8)
        var bytes = Data()
        withUnsafeBytes(of: UInt64(name.count).bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: name)
        let raw = Data(argumentsJSON.utf8)
        // The marker keeps a canonical encoding and raw bytes from colliding.
        // When the text is not (strict) JSON the raw bytes stand in: the
        // stricter direction, since any byte then changes the version. Over
        // the byte cap it is never parsed, same as the summary.
        if raw.count <= ActionSummary.maxArgumentBytes, let parsed = JSONValue.parse(raw) {
            bytes.append(Self.canonicalMarker)
            bytes.append(contentsOf: parsed.canonicalBytes())
        } else {
            bytes.append(Self.rawMarker)
            bytes.append(raw)
        }
        hex = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    package var description: String { "<action version>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}

package struct ProposedAction: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    package enum Kind: String, Sendable { case app, mcp }
    package enum Effect: String, Sendable { case change, delete, unknown }

    package static let maxLabel = 80
    package static let maxTool = 80

    package let kind: Kind
    package let tool: String
    package let label: String
    package let effect: Effect
    package let arguments: ActionSummary
    package let version: ActionVersion

    package var isComplete: Bool { arguments.isComplete }

    init(kind: Kind, tool: String, label: String, effect: Effect,
                arguments: ActionSummary, version: ActionVersion) {
        self.kind = kind
        self.tool = tool
        self.label = label
        self.effect = effect
        self.arguments = arguments
        self.version = version
    }

    /// nil for a read: only writes are judged.
    package static func app(toolName: String, label: String, group: AppAction.Group,
                           argumentsJSON: String) -> ProposedAction? {
        let effect: Effect
        switch group {
        case .leer: return nil
        case .crearYCambiar: effect = .change
        case .borrar: effect = .delete
        }
        return ProposedAction(
            kind: .app, tool: shownTool(toolName),
            label: TextSanitizer.display(label, maxLength: maxLabel), effect: effect,
            arguments: ActionSummary.make(argumentsJSON: argumentsJSON),
            version: ActionVersion(toolName: toolName, argumentsJSON: argumentsJSON))
    }

    /// The request's own summary is text from a third party's server, so the
    /// label is the tool name and nothing else. That name is from the server
    /// too: it travels sanitised and capped, and only the version sees it raw.
    package static func mcp(_ request: ApprovalRequest) -> ProposedAction {
        let tool = shownTool(request.toolName)
        return ProposedAction(
            kind: .mcp, tool: tool, label: tool, effect: .unknown,
            arguments: ActionSummary.make(argumentsJSON: request.inputJSON),
            version: ActionVersion(toolName: request.toolName, argumentsJSON: request.inputJSON))
    }

    private static func shownTool(_ raw: String) -> String {
        ActionSummary.bounded(raw, limit: maxTool, label: "tool")
    }

    /// The tool name stays out on purpose (D8): only class and effect.
    package var description: String { "<proposed action: \(kind.rawValue), \(effect.rawValue)>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}

// MARK: - Request

/// No free `String` field: the only text that reaches the judge is the
/// user's words and the structured summary of each action.
package struct ActionJudgeRequest: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    package let words: UserWords
    package let actions: [ProposedAction]
    package let pipeline: VoicePipeline

    /// nil when there is nothing to judge or the batch is over the cap.
    package init?(words: UserWords, actions: [ProposedAction], pipeline: VoicePipeline,
                 maxActions: Int = ActionJudgeSettings.defaultMaxActions) {
        guard !actions.isEmpty, actions.count <= maxActions else { return nil }
        self.words = words
        self.actions = actions
        self.pipeline = pipeline
    }

    package var description: String { "<judge request: \(actions.count) actions>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}

// MARK: - Verdicts

/// Closed on purpose: a reason that is an enum can be logged without leaking
/// anything the model wrote.
package enum JudgeReason: String, Sendable, Equatable, CaseIterable {
    case asked
    case notAsked = "not_asked"
    case otherTarget = "other_target"
    case broaderEffect = "broader_effect"
    case unclear
}

package enum JudgeFailure: String, Sendable, Equatable, CaseIterable {
    case timeout, http, invalid
    case noProvider = "no_provider"
    case noWords = "no_words"
    case tooMany = "too_many"
    case cancelled
}

package enum JudgeVerdict: Sendable, Equatable, CustomStringConvertible {
    /// The reason is always `.asked`.
    case covered
    case notCovered(JudgeReason)
    /// Never counted as covered, anywhere.
    case failed(JudgeFailure)

    package var description: String {
        switch self {
        case .covered: "covered"
        case .notCovered(let reason): "not_covered:\(reason.rawValue)"
        case .failed(let failure): "failed:\(failure.rawValue)"
        }
    }
}

/// What the user decided on the sheet, to compare against the verdict.
package enum ApprovalDecision: String, Sendable, Equatable {
    case approved, denied, expired, cancelled, voiceResolved
}
