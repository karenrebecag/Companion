import Foundation

/// A question whose answer decides the next step (16m-6): Incredible's
/// `answer-card`. The model writes it in a `companion:choice` fence; picking
/// an option only ever sends its label as the user's next message, so nothing
/// runs from a click that a typed reply could not have started.
public struct ChoiceBlock: Sendable, Equatable {
    public struct Option: Sendable, Equatable {
        public var label: String
        public var detail: String?

        public init(label: String, detail: String? = nil) {
            self.label = label
            self.detail = detail
        }
    }

    /// Where the question stands, read off the transcript (never stored): a
    /// card that outlives a restart still knows what was picked.
    public enum Resolution: Sendable, Equatable {
        case open
        case chosen(Int)
        /// Answered some other way (she typed something else).
        case passed
    }

    public static let minOptions = 2
    /// Every option is a one-key shortcut (1-9) and the card lives in a panel
    /// 620 tall: past six it is a list, not a question.
    public static let maxOptions = 6
    public static let maxQuestion = 200
    /// The label is also the message that gets sent, so it stays a phrase.
    public static let maxLabel = 80
    public static let maxDetail = 160

    public var question: String
    public var options: [Option]

    public init(question: String, options: [Option]) {
        self.question = question
        self.options = options
    }

    /// `reply` is the user's next message after the question, if any.
    public func resolution(reply: String?) -> Resolution {
        let said = Self.oneLine(reply ?? "", maxLength: Self.maxLabel * 4)
        guard !said.isEmpty else { return .open }
        let sent = options.firstIndex { $0.label == said }
        return sent.map(Resolution.chosen) ?? .passed
    }

    /// Sanitized, one line, trimmed: a newline in a label would send two lines.
    static func oneLine(_ text: String, maxLength: Int) -> String {
        TextSanitizer.display(text, maxLength: maxLength)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

extension CompanionBlocks {
    public static let choiceLanguage = "companion:choice"

    /// Nil sends the fence back to a code block, visible: a question the
    /// client cannot draw honestly is never drawn half-way (no options are
    /// dropped in silence, no label is left empty or ambiguous).
    public static func choice(_ body: String) -> ChoiceBlock? {
        guard let dict = fenceObject(body),
              let rawQuestion = dict["question"] as? String,
              let rawOptions = dict["options"] as? [Any],
              (ChoiceBlock.minOptions ... ChoiceBlock.maxOptions).contains(rawOptions.count)
        else { return nil }
        let question = ChoiceBlock.oneLine(rawQuestion, maxLength: ChoiceBlock.maxQuestion)
        guard !question.isEmpty else { return nil }
        var options: [ChoiceBlock.Option] = []
        var seen = Set<String>()
        for raw in rawOptions {
            guard let option = choiceOption(from: raw),
                  seen.insert(option.label.lowercased()).inserted
            else { return nil }
            options.append(option)
        }
        return ChoiceBlock(question: question, options: options)
    }

    private static func choiceOption(from raw: Any) -> ChoiceBlock.Option? {
        let rawLabel: String
        var rawDetail: String?
        if let text = raw as? String {
            rawLabel = text
        } else if let dict = raw as? [String: Any], let text = dict["label"] as? String {
            rawLabel = text
            rawDetail = dict["detail"] as? String
        } else {
            return nil
        }
        let label = ChoiceBlock.oneLine(rawLabel, maxLength: ChoiceBlock.maxLabel)
        guard !label.isEmpty else { return nil }
        let detail = rawDetail.map { ChoiceBlock.oneLine($0, maxLength: ChoiceBlock.maxDetail) }
        return ChoiceBlock.Option(label: label, detail: detail?.isEmpty == false ? detail : nil)
    }
}

/// What the model is told about a message that came from a question card.
public enum ChoiceOrigin {
    public static func marker(_ language: AppLanguage) -> String {
        language == .es ? "[elección en tarjeta]" : "[card choice]"
    }

    public static func mark(_ text: String, language: AppLanguage) -> String {
        marker(language) + " " + text
    }
}
