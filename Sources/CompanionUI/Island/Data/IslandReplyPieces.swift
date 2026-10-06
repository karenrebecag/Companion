import CompanionCore
import SwiftUI

/// The reply as the panel shows it: large plain words, no bubble, the whole
/// spoken reply up to its last `wordCap` words, as Incredible does. Cutting
/// at the first paragraph and a fixed length left "aquel p…" on screen
/// (brief isla-maquetacion-incredible, F2).
enum IslandReplyText {
    static let wordCap = 600

    static func spoken(from reply: String) -> String {
        // The panel shows what the voice may say: the same filter, so a JSON
        // object or an instruction meant for the model never paints here.
        // Code is not spoken, so it does not paint either. `islandProse`
        // reads a bounded window, so the cost per streamed token stays
        // bounded (security review 16f).
        let prose = MarkdownSplitter.islandProse(reply)
            .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "\n\n", options: .regularExpression)
        let paragraphs = SpeechFilter.clean(prose)
            .components(separatedBy: "\n\n")
            .map(plain)
            .filter { !$0.isEmpty }
        return lastWords(paragraphs.joined(separator: "\n\n"), cap: wordCap)
    }

    /// Keeps the end of a long reply, where the voice is, and its breaks.
    static func lastWords(_ text: String, cap: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > cap else { return text }
        return String(text[words[words.count - cap].startIndex...])
    }

    private static func plain(_ paragraph: String) -> String {
        // [label](url) reads as its label; a "[" that opens no link is left
        // as is. The label holds no bracket, so each "[" has one candidate
        // "](", and the url is bounded: a stray "[" costs a short scan, not a
        // rescan of the whole window (the paragraph can be the whole window
        // now). A label with a "]" inside stays raw; that is rare.
        let text = paragraph
            .replacingOccurrences(of: #"\[([^\[\]]*)\]\([^)]{0,512}\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*- ").union(.whitespaces))
        return text
    }
}

struct IslandReply: View {
    /// Where the words sit: the bar's answer, Arc's two-line voice
    /// transcript under the orb, or a reply inside the thread.
    enum Look: Equatable {
        case answer, transcript, thread

        var size: CGFloat {
            self == .answer ? TypeSize.strong : TypeSize.base
        }

        var alignment: TextAlignment { self == .transcript ? .center : .leading }

        var frameAlignment: Alignment { self == .transcript ? .center : .leading }
    }

    let text: String
    let startedAt: Date
    let speaking: Bool
    /// When each word was really said (gap 2), from a live caption; nil
    /// keeps the three-words-a-second clock.
    var said: [Double?]?
    var look: Look = .answer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overflows = false

    /// Smooth enough for a 220 ms color settle per word, a fraction of a display's rate.
    private static let frameInterval = 1.0 / 30

    var body: some View {
        let words = Self.words(text)
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !speaking)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            // `said` is wall-clock epoch seconds, the clock this timeline runs on.
            Text(Self.painted(words, elapsed: elapsed, speaking: speaking, reduceMotion: reduceMotion,
                              said: said, now: context.date.timeIntervalSince1970))
                .font(Fonts.geist(look.size))
                .lineSpacing(look == .answer ? Space.x1 : Self.transcriptSpacing)
                .multilineTextAlignment(look.alignment)
                .frame(maxWidth: .infinity, alignment: look.frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(TranscriptCap(enabled: look == .transcript, overflows: $overflows))
        .accessibilityLabel(text)
    }

    /// The transcript look keeps the voice transcript's leading, so its two-line cap holds.
    static let transcriptSpacing = AnswerBlockMetrics.lineSpacing(
        size: TypeSize.base, leading: WorkStateMetrics.transcriptLeading)

    static func words(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }

    private static func painted(
        _ words: [String], elapsed: Double, speaking: Bool, reduceMotion: Bool,
        said: [Double?]?, now: Double
    ) -> AttributedString {
        var out = AttributedString()
        for (index, word) in words.enumerated() {
            let light = said.map {
                IslandReveal.brightness(saidAt: index < $0.count ? $0[index] : nil, now: now, reduceMotion: reduceMotion)
            } ?? IslandReveal.brightness(
                word: index, elapsed: elapsed, speaking: speaking, reduceMotion: reduceMotion)
            var piece = AttributedString(index == 0 ? word : " " + word)
            piece.foregroundColor = Neutral.white.color.opacity(IslandMotionBudget.spokenWord.alpha(brightness: light))
            out += piece
        }
        return out
    }
}
