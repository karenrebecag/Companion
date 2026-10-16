import Foundation

/// The coverage judge. Before the sheets of one model step, it reads what the
/// user said this turn and the actions the step wants, and answers per action
/// what it does and whether her own words already ask for it. It can only
/// lower a sheet (see `JudgeBand`); it never sees an action it cannot shape.
package protocol ActionJudging: Sendable {
    /// One opinion per candidate, in order. nil is a failed judgement, and a
    /// failed judgement never lowers anything.
    func judge(_ request: ActionJudgeRequest) async -> [JudgeOpinion?]
}

// MARK: - The user's words

/// What the user said in the turn, from the trusted channel (the mic or the
/// keyboard). A type of its own so that no other string can reach the judge as
/// "the user's words", and so that printing anything that holds it never prints them.
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

// MARK: - Candidates and opinions

/// One action of the step that would open a sheet. The arguments are redacted
/// before they are summarised, and long texts travel as their length only.
package struct JudgeCandidate: Sendable, Equatable {
    package static let maxTool = 80

    package let id: String
    package let tool: String
    package let arguments: ActionSummary

    package init(id: String, tool: String, argumentsJSON: String) {
        self.id = id
        self.tool = String(tool.prefix(Self.maxTool))
        arguments = ActionSummary.make(argumentsJSON: TurnRedaction.redact(argumentsJSON))
    }
}

/// What the action does, in the three cases that decide a sheet. `undoable`
/// can be taken back from the trash or a version; `irreversible` cannot;
/// `reaches_someone` leaves the Mac for a person or a service.
package enum JudgeEffect: String, Sendable, Equatable, CaseIterable {
    case undoable
    case irreversible
    case reachesSomeone = "reaches_someone"
}

package struct JudgeOpinion: Sendable, Equatable {
    package let effect: JudgeEffect
    /// Her own words already ask for this action with this scope. For
    /// `reaches_someone` that includes the recipient she named.
    package let covered: Bool

    package init(effect: JudgeEffect, covered: Bool) {
        self.effect = effect
        self.covered = covered
    }
}

// MARK: - Request

/// Nil when there is nothing to judge, the batch is over the cap, or a summary
/// is incomplete: a judge shown half of a destination can only guess, and a
/// guess must never come out covered, so the whole batch stays on its sheets.
package struct ActionJudgeRequest: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    package let words: UserWords
    package let candidates: [JudgeCandidate]

    package init?(words: UserWords, candidates: [JudgeCandidate],
                  maxCandidates: Int = ActionJudgeSettings.defaultMaxCandidates) {
        guard !candidates.isEmpty, candidates.count <= maxCandidates,
              candidates.allSatisfy({ $0.arguments.isComplete })
        else { return nil }
        self.words = words
        self.candidates = candidates
    }

    package var description: String { "<judge request: \(candidates.count) actions>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}

// MARK: - Action summary

/// The arguments of a proposed action reduced to what identifies its target.
/// Long texts (message bodies) travel as their length only: they are the main
/// vector for injecting the judge (D2).
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

    /// The summary as the judge reads it: one JSON object, keys sorted so the
    /// same arguments always read the same way. Throws rather than returning
    /// a stand-in: a judge shown no arguments would be guessing.
    package func jsonText() throws -> String {
        let object: [String: Any] = values.mapValues { value in
            switch value {
            case .text(let text): text
            case .number(let number): number
            case .bool(let flag): flag
            case .list(let items): items
            }
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    package var description: String { "<action summary: \(values.count) keys>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}
