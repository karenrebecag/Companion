import SwiftUI

// Arc's VoiceTranscript on the island: what the ear hears, two lines tall and
// anchored to the bottom so older lines lift away under a fade, with each new
// word settling in from a soft blur. Quieter while it can still change, full
// ink the moment it is fixed (16m-2).

enum TranscriptArrivals {
    /// Arc: a word takes 0.34 s to settle.
    static let duration = 0.34
    /// Arc: a word rises 3 pt as it settles.
    static let rise: CGFloat = 3
    /// The clock stops this long after the last word settles, so it lands on its final frame.
    static let slack = 0.05

    struct Look: Equatable {
        let opacity: Double
        let blur: CGFloat
        let rise: CGFloat
    }

    /// When each word arrived. A word keeps its time while it and every word
    /// before it are unchanged; a word the ear rewrote arrives again.
    static func update(previous: [String], births: [Double], next: [String], now: Double) -> [Double] {
        var out: [Double] = []
        var same = true
        for (index, word) in next.enumerated() {
            same = same && index < previous.count && index < births.count && previous[index] == word
            out.append(same ? births[index] : now)
        }
        return out
    }

    static func look(age: Double, reduceMotion: Bool) -> Look {
        guard !reduceMotion else { return Look(opacity: 1, blur: 0, rise: 0) }
        let t = min(1, max(0, age.isFinite ? age / duration : 1))
        let p = MotionCurve.value(ArcMotion.Curve.enter, at: t)
        return Look(opacity: p, blur: ArcMotion.Blur.soft * (1 - p), rise: rise * (1 - p))
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

/// Tags a word's run with its arrival time so the renderer can settle it.
private struct WordBirth: TextAttribute {
    let at: Double
}

/// Draws each word as it settles: faded, blurred and a little low while new.
private struct WordArrivalRenderer: TextRenderer {
    let now: Double
    let reduceMotion: Bool

    var animatableData: Double {
        get { now }
        set { _ = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let birth = run[WordBirth.self]?.at ?? -.infinity
                let look = TranscriptArrivals.look(age: now - birth, reduceMotion: reduceMotion)
                var copy = context
                copy.opacity = look.opacity
                if look.blur > 0.05 { copy.addFilter(.blur(radius: look.blur)) }
                copy.translateBy(x: 0, y: look.rise)
                copy.draw(run)
            }
        }
    }
}

struct IslandTranscript: View {
    let text: String
    let fixed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var words: [String]
    @State private var births: [Double]
    @State private var settling = false
    @State private var overflows = false

    /// The first frame already holds the words, settled: only what arrives
    /// after the transcript appears settles in.
    init(text: String, fixed: Bool) {
        self.text = text
        self.fixed = fixed
        let first = TranscriptArrivals.words(text)
        _words = State(initialValue: first)
        _births = State(initialValue: Array(repeating: 0, count: first.count))
    }

    private var lineHeight: CGFloat { WorkStateMetrics.transcriptSize * WorkStateMetrics.transcriptLeading }
    private var cap: CGFloat { lineHeight * TranscriptFade.lines }

    var body: some View {
        TimelineView(.animation(paused: !settling || reduceMotion)) { timeline in
            composed
                .textRenderer(WordArrivalRenderer(now: timeline.date.timeIntervalSince1970, reduceMotion: reduceMotion))
        }
        .font(Fonts.geist(WorkStateMetrics.transcriptSize).weight(.medium))
        .lineSpacing(AnswerBlockMetrics.lineSpacing(
            size: WorkStateMetrics.transcriptSize, leading: WorkStateMetrics.transcriptLeading))
        .foregroundStyle(.white.opacity(fixed ? WorkStateMetrics.transcriptFixed : WorkStateMetrics.transcriptLive))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: Bool.self, of: { TranscriptFade.fadesTop(content: $0.size.height, cap: cap) }) {
            overflows = $0
        }
        .modifier(BottomCapped(cap: cap))
        // Older lines lift away under the top edge instead of a "…".
        .mask(TranscriptFade.mask(overflows: overflows))
        .animation(.expoOut(MotionTime.fast), value: fixed)
        .onChange(of: text) { _, next in arrive(next) }
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    /// The text as one Text of runs, one per word, each tagged with its arrival.
    private var composed: Text {
        words.enumerated().reduce(Text(verbatim: "")) { sum, item in
            let (index, word) = item
            let birth = index < births.count ? births[index] : 0
            return sum + Text(verbatim: index == 0 ? word : " " + word).customAttribute(WordBirth(at: birth))
        }
    }

    private func arrive(_ next: String) {
        let nextWords = TranscriptArrivals.words(next)
        births = TranscriptArrivals.update(previous: words, births: births, next: nextWords,
                                           now: Date().timeIntervalSince1970)
        words = nextWords
        guard !reduceMotion else { return }
        settling = true
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(TranscriptArrivals.duration + TranscriptArrivals.slack)) } catch { return }
            if let last = births.max(), Date().timeIntervalSince1970 - last >= TranscriptArrivals.duration {
                settling = false
            }
        }
    }
}

/// Hugs its content up to `cap`, then keeps the bottom: Arc's two-line
/// transcript without reserving the second line before it is needed.
/// The top fade is for lines lifting away past the cap: text that fits is
/// drawn whole, never dimmed for an overflow that is not there.
enum TranscriptFade {
    static let lines: CGFloat = 2
    /// Where the fade reaches full ink, as a share of the capped height.
    static let reach = 0.4
    /// Layout rounds; half a point over the cap is still the cap.
    static let slack: CGFloat = 0.5

    static func fadesTop(content: CGFloat, cap: CGFloat) -> Bool {
        content > cap + slack
    }

    static func mask(overflows: Bool) -> LinearGradient {
        LinearGradient(stops: [.init(color: overflows ? .clear : .black, location: 0),
                               .init(color: .black, location: reach)],
                       startPoint: .top, endPoint: .bottom)
    }
}

private struct BottomCapped: ViewModifier {
    let cap: CGFloat

    func body(content: Content) -> some View {
        BottomCapLayout(cap: cap) { content }.clipped()
    }
}

private struct BottomCapLayout: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: min(size.height, cap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}
