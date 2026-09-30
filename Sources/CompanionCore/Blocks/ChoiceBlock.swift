import Foundation

/// A question whose answer decides the next step (16m-6): Incredible's
/// `answer-card`. The model writes it in a `companion:choice` fence; picking
/// an option only ever sends its label as the user's next message, so nothing
/// runs from a click that a typed reply could not have started.
package struct ChoiceBlock: Sendable, Equatable {
    package struct Option: Sendable, Equatable {
        package var label: String
        package var detail: String?

        package init(label: String, detail: String? = nil) {
            self.label = label
            self.detail = detail
        }
    }

    /// Where the question stands, read off the transcript (never stored): a
    /// card that outlives a restart still knows what was picked.
    package enum Resolution: Sendable, Equatable {
        case open
        case chosen(Int)
        /// A multiple-choice card answered with several options.
        case chosenMany([Int])
        /// Answered some other way (she typed something else).
        case passed
    }

    package static let minOptions = 2
    /// Every option is a one-key shortcut (1-9) and the card lives in a panel
    /// 620 tall: past six it is a list, not a question.
    package static let maxOptions = 6
    package static let maxQuestion = 200
    /// The label is also the message that gets sent, so it stays a phrase.
    package static let maxLabel = 80
    package static let maxDetail = 160

    /// The free answer is a message too: capped so it stays a reply.
    package static let maxAnswer = 500

    package var question: String
    package var options: [Option]
    /// The fence asked for several picks (`"multiple": true`).
    package var multiple: Bool
    /// The fence allows an answer in her own words (`"allowText": true`).
    package var allowText: Bool

    package init(question: String, options: [Option], multiple: Bool = false, allowText: Bool = false) {
        self.question = question
        self.options = options
        self.multiple = multiple
        self.allowText = allowText
    }

    /// The message a set of picks sends: labels in option order.
    package func reply(for picked: [Int]) -> String {
        options.indices.filter(picked.contains).map { options[$0].label }.joined(separator: Self.separator)
    }

    static let separator = ", "

    /// `reply` is the user's next message after the question, if any.
    package func resolution(reply: String?) -> Resolution {
        let said = Self.oneLine(reply ?? "", maxLength: max(Self.maxLabel, Self.maxAnswer) * 4)
        guard !said.isEmpty else { return .open }
        if let sent = options.firstIndex(where: { $0.label == said }) { return .chosen(sent) }
        if multiple, let picked = pickedSet(matching: said) { return .chosenMany(picked) }
        return .passed
    }

    /// The subset of options whose labels, in option order, read exactly as
    /// `said`. Tried by subsets rather than split on the separator: a label
    /// may contain a comma, and at most six options make 63 candidates.
    private func pickedSet(matching said: String) -> [Int]? {
        let count = options.count
        guard count >= 2 else { return nil }
        for mask in 1 ..< (1 << count) where mask.nonzeroBitCount >= 2 {
            let picked = (0 ..< count).filter { mask & (1 << $0) != 0 }
            if reply(for: picked) == said { return picked }
        }
        return nil
    }

    /// Sanitized, one line, trimmed: a newline in a label would send two lines.
    package static func oneLine(_ text: String, maxLength: Int) -> String {
        TextSanitizer.display(text, maxLength: maxLength)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

extension CompanionBlocks {
    package static let choiceLanguage = "companion:choice"

    /// Nil sends the fence back to a code block, visible: a question the
    /// client cannot draw honestly is never drawn half-way (no options are
    /// dropped in silence, no label is left empty or ambiguous).
    package static func choice(_ body: String) -> ChoiceBlock? {
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
        // A flag of another type is a model slip, not a broken question.
        return ChoiceBlock(
            question: question, options: options,
            multiple: dict["multiple"] as? Bool ?? false,
            allowText: dict["allowText"] as? Bool ?? false)
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
package enum ChoiceOrigin {
    package static func marker(_ language: AppLanguage) -> String {
        language == .es ? "[elección en tarjeta]" : "[card choice]"
    }

    package static func mark(_ text: String, language: AppLanguage) -> String {
        marker(language) + " " + text
    }
}
