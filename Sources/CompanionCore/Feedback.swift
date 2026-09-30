import Foundation

/// Five moods, worst to best (16q-2; four before). Own names; the meaning
/// is the usual five-step scale.
public enum FeedbackMood: String, Sendable, CaseIterable, Equatable {
    case upset, bad, meh, good, love
}

/// What the comment is about (16q-2), six chips. Own names for what the
/// product does: talking, working on the screen, connected apps, errands,
/// dictation, and everything else.
public enum FeedbackTopic: String, Sendable, CaseIterable, Equatable {
    case voice, screen, apps, errands, dictation, other
}

/// What the feedback modal composes (16m-7). Delivery is unchanged: the
/// user's own mail app through `mailto:`, no server of ours and no address
/// until she writes it. The message carries her words, the mood she picked
/// and how many screenshots she chose to add; nothing about the machine.
public struct FeedbackDraft: Sendable, Equatable {
    /// Own values: a comment is a few paragraphs, and three screenshots show a
    /// bug. 5000 since 16q-2 (1000 before); past what a mail link holds the
    /// message goes whole through the share service, or is cut and reported.
    public static let maxCharacters = 5000
    public static let maxCaptures = 3
    /// A screenshot added from a file or the clipboard: mail apps refuse
    /// bigger attachments long before a screen needs them.
    public static let maxCaptureBytes = 4 * 1024 * 1024
    /// Own value: mail links past a few thousand characters are cut or
    /// refused by clients (browsers stop near 2000); a thousand emoji encode
    /// to about 28 000. Anything over this goes through the share service or
    /// is cut, and the cut is reported.
    public static let maxMailtoLength = 6000

    public let mood: FeedbackMood?
    public let text: String
    public let captureCount: Int
    /// In `FeedbackTopic` order, no repeats, whatever order they were given.
    public let topics: [FeedbackTopic]

    public init(mood: FeedbackMood?, text: String, captureCount: Int, topics: [FeedbackTopic] = []) {
        self.mood = mood
        self.text = text
        self.captureCount = captureCount
        self.topics = FeedbackTopic.allCases.filter(topics.contains)
    }

    public var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && remaining >= 0
    }

    public var remaining: Int { Self.maxCharacters - text.count }

    /// Characters, not bytes: an emoji family is one.
    public static func clipped(_ text: String) -> String {
        String(text.prefix(maxCharacters))
    }

    public func body(language: AppLanguage) -> String {
        var parts: [String] = []
        if let mood { parts.append(Self.moodLine(mood, language)) }
        if !topics.isEmpty { parts.append(Self.topicsLine(topics, language)) }
        parts.append(TextSanitizer.display(text, maxLength: Self.maxCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines))
        if captureCount > 0 { parts.append((language == .es ? "Capturas: " : "Screenshots: ") + String(captureCount)) }
        return parts.joined(separator: "\n\n")
    }

    /// The whole message as a link, however long.
    public func mailtoURL(subject: String, language: AppLanguage) -> URL? {
        Self.link(subject: subject, body: body(language: language))
    }

    /// The message as a link that fits `maxMailtoLength`: the words are cut
    /// (by character, never inside an emoji) with an ellipsis, and `truncated`
    /// says so. Nil only when even an empty message does not fit.
    public func mailto(subject: String, language: AppLanguage) -> (url: URL, truncated: Bool)? {
        if let whole = mailtoURL(subject: subject, language: language),
           whole.absoluteString.count <= Self.maxMailtoLength { return (whole, false) }
        func cut(_ count: Int) -> URL? {
            let shortened = FeedbackDraft(
                mood: mood, text: String(text.prefix(count)) + "…", captureCount: captureCount, topics: topics)
            return shortened.mailtoURL(subject: subject, language: language)
        }
        var low = 0
        var high = text.count
        var best: URL?
        while low <= high {
            let middle = (low + high) / 2
            if let url = cut(middle), url.absoluteString.count <= Self.maxMailtoLength {
                best = url
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return best.map { ($0, true) }
    }

    private static func link(subject: String, body: String) -> URL? {
        // `&`, `=`, `+` and `#` are legal in a query and would split it, so
        // only unreserved characters are left as they are.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        return URL(string: "mailto:?subject=\(encode(subject))&body=\(encode(body))")
    }

    private static func topicsLine(_ topics: [FeedbackTopic], _ language: AppLanguage) -> String {
        (language == .es ? "Temas: " : "Topics: ") + topics.map { topicName($0, language) }.joined(separator: ", ")
    }

    private static func topicName(_ topic: FeedbackTopic, _ language: AppLanguage) -> String {
        switch (topic, language) {
        case (.voice, .en): "voice and chat"
        case (.screen, .en): "screen and browser"
        case (.apps, .en): "connected apps"
        case (.errands, .en): "errands"
        case (.dictation, .en): "dictation"
        case (.other, .en): "anything else"
        case (.voice, .es): "voz y chat"
        case (.screen, .es): "pantalla y navegador"
        case (.apps, .es): "apps conectadas"
        case (.errands, .es): "encargos"
        case (.dictation, .es): "dictado"
        case (.other, .es): "otra cosa"
        }
    }

    private static func moodLine(_ mood: FeedbackMood, _ language: AppLanguage) -> String {
        switch (mood, language) {
        case (.upset, .en): "Mood: at my limit"
        case (.love, .en): "Mood: loving it"
        case (.good, .en): "Mood: good"
        case (.meh, .en): "Mood: so-so"
        case (.bad, .en): "Mood: not good"
        case (.upset, .es): "Ánimo: al límite"
        case (.love, .es): "Ánimo: me encanta"
        case (.good, .es): "Ánimo: bien"
        case (.meh, .es): "Ánimo: regular"
        case (.bad, .es): "Ánimo: mal"
        }
    }
}
