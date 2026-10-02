import CompanionCore
import SwiftUI

/// One reply as a card: a title, one line, "View →" for the rest.
struct IslandResultCard: View {
    let result: IslandResult
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(result.title)
                    .font(Fonts.geist(TypeSize.base).weight(.medium))
                    .foregroundStyle(IslandInk.text)
                    .lineLimit(1)
                if let line = result.line {
                    Text(line)
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(IslandInk.secondary)
                        .lineLimit(1)
                }
                Text(Localized.string("island.result.open"))
                    .font(GeistFont.uiCaption)
                    .foregroundStyle(IslandInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.x3)
            .background(RoundedRectangle(cornerRadius: IslandInk.cardRadius).fill(IslandInk.field))
            .contentShape(RoundedRectangle(cornerRadius: IslandInk.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

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
    let text: String
    let startedAt: Date
    let speaking: Bool

    /// Smooth enough for a 150 ms fade per word, a fraction of a display's rate.
    private static let frameInterval = 1.0 / 30

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !speaking)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            Text(Self.painted(words, elapsed: elapsed, speaking: speaking))
                .font(Fonts.geist(TypeSize.strong))
                .lineSpacing(Space.x1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(text)
    }

    /// Dim words read as the secondary ink on black; each brightens to full
    /// over its own fade, so the light glides along the line.
    private static func painted(_ words: [String], elapsed: Double, speaking: Bool) -> AttributedString {
        var out = AttributedString()
        for (index, word) in words.enumerated() {
            let light = IslandReveal.brightness(word: index, elapsed: elapsed, speaking: speaking)
            var piece = AttributedString(index == 0 ? word : " " + word)
            piece.foregroundColor = IslandInk.text.opacity(IslandInk.dimWord + (1 - IslandInk.dimWord) * light)
            out += piece
        }
        return out
    }
}
