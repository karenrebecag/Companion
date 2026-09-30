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

/// The reply as the panel shows it (16f): large plain words, no bubble, the
/// part that was said. The rest lives in the window.
enum IslandReplyText {
    static let maxLength = 240

    static func spoken(from reply: String) -> String {
        // The panel shows what the voice may say: the same filter, so a JSON
        // object or an instruction meant for the model never paints here.
        let paragraph = SpeechFilter.clean(MarkdownSplitter.islandProse(reply))
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        // Model text is unbounded and this runs on every streamed token: cut
        // first, so the cost never depends on the reply (security review 16f).
        var text = String(paragraph.prefix(maxLength * 4))
        // [label](url) reads as its label; a "[" that opens no link is
        // skipped, not the end of the search.
        var from = text.startIndex
        while let open = text.range(of: "[", range: from..<text.endIndex) {
            guard let mid = text.range(of: "](", range: open.upperBound..<text.endIndex),
                  let close = text.range(of: ")", range: mid.upperBound..<text.endIndex),
                  !text[open.upperBound..<mid.lowerBound].contains("[")
            else {
                from = open.upperBound
                continue
            }
            let label = String(text[open.upperBound..<mid.lowerBound])
            // Indices do not survive a mutation; the offset does.
            let resume = text.distance(from: text.startIndex, to: open.lowerBound) + label.count
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: label)
            from = text.index(text.startIndex, offsetBy: resume)
        }
        text = text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*- ").union(.whitespaces))
        return text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
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
