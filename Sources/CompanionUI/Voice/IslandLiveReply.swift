import CompanionCore
import SwiftUI

/// The island's reply, lit by the realtime voice's caption while one is live
/// (gap 2). It reads the caption itself, so the caption's ticks re-render
/// this reply and not the whole island.
struct IslandLiveReply: View {
    let voice: VoiceViewModel
    let text: String
    let startedAt: Date
    let speaking: Bool

    var body: some View {
        if let live = Self.painting(voice.caption) {
            IslandReply(text: live.text, startedAt: startedAt, speaking: true, said: live.said)
        } else if !text.isEmpty {
            IslandReply(text: text, startedAt: startedAt, speaking: speaking)
        }
    }

    /// The live text through the panel's own shaping, with each shown word's
    /// moment; computed once per caption, not per frame. Nil hands the reply
    /// back to the clock: no caption, or one already settled.
    static func painting(_ caption: CaptionSnapshot) -> (text: String, said: [Double?])? {
        guard caption.isLive else { return nil }
        let text = IslandReplyText.spoken(from: caption.text)
        return (text, caption.saidAt(for: IslandReply.words(text)))
    }
}
