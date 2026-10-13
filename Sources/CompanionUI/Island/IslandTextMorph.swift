import SwiftUI

/// Arc's text-morph for the island's status words: letters the two labels
/// share glide to their new place, new ones sharpen in with a stagger, the
/// rest blur away, and the width follows. Only for short one-line labels.
/// Reduce Motion swaps the label at once.
struct IslandTextMorph: View {
    let text: String
    /// Offscreen renders pin the morph to one instant: the label it left and the seconds since.
    var frozen: (from: String, elapsed: TimeInterval)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previous: String?
    @State private var changedAt: Date?
    @State private var settled = true

    var body: some View {
        Group {
            if let frozen {
                TextMorphFrame(plan: TextMorphPlan.plan(from: frozen.from, to: text), elapsed: frozen.elapsed)
            } else if reduceMotion || settled || previous == nil {
                TextMorphFrame(plan: TextMorphPlan.plan(from: text, to: text), elapsed: .infinity)
            } else {
                let plan = TextMorphPlan.plan(from: previous ?? text, to: text)
                TimelineView(.animation) { timeline in
                    TextMorphFrame(plan: plan, elapsed: timeline.date.timeIntervalSince(changedAt ?? timeline.date))
                }
            }
        }
        .onChange(of: text) { old, _ in
            guard !reduceMotion else { return }
            previous = old
            changedAt = Date()
            settled = false
        }
        .task(id: changedAt) {
            guard let changedAt, !settled else { return }
            let plan = TextMorphPlan.plan(from: previous ?? text, to: text)
            let wait = TextMorphTiming.total(plan) - Date().timeIntervalSince(changedAt)
            do {
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            } catch {
                // A newer change cancelled this wait; its own task settles the label.
                return
            }
            settled = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// One instant of a morph: every letter of both labels with its own look.
struct TextMorphFrame: View {
    let plan: [TextMorphGlyph]
    let elapsed: TimeInterval

    private var em: CGFloat { TypeScale.apply(TypeSize.base) }

    var body: some View {
        TextMorphRow(progress: TextMorphTiming.layoutProgress(elapsed)) {
            ForEach(plan, id: \.key) { glyph in
                letter(glyph)
                    .layoutValue(key: TextMorphSlot.self, value: TextMorphSlot.Value(from: glyph.from, to: glyph.to))
            }
        }
    }

    private func letter(_ glyph: TextMorphGlyph) -> some View {
        let look = TextMorphLook(glyph: glyph, elapsed: elapsed)
        return Text(String(glyph.character))
            .font(GeistFont.uiLabel)
            .foregroundStyle(IslandInk.text)
            .fixedSize()
            .scaleEffect(look.scale, anchor: UnitPoint(x: 0.5, y: 0.6))
            .offset(y: look.rise * em)
            .blur(radius: look.blur * ArcMotion.Blur.soft)
            .opacity(look.opacity)
    }
}

/// How one letter looks at one instant, from Arc's enter and exit keyframes.
struct TextMorphLook: Equatable {
    var opacity = 1.0
    var scale = 1.0
    /// Vertical offset in ems.
    var rise = 0.0
    /// Share of the soft blur.
    var blur = 0.0

    init(glyph: TextMorphGlyph, elapsed: TimeInterval) {
        if glyph.to == nil {
            let q = TextMorphTiming.exitProgress(elapsed, order: glyph.exitOrder ?? 0)
            opacity = 1 - q
            scale = 1 - 0.14 * q
            rise = -0.1 * q
            blur = q
        } else if let order = glyph.enterOrder {
            let p = TextMorphTiming.enterProgress(elapsed, order: order)
            opacity = p
            scale = 0.8 + 0.2 * p
            rise = 0.14 * (1 - p)
            blur = 1 - p
        }
    }
}

nonisolated struct TextMorphSlot: LayoutValueKey {
    struct Value: Equatable {
        var from: Int?
        var to: Int?
    }

    static let defaultValue = Value()
}

/// Lays the letters out twice, as the old label and as the new one, and puts
/// each where the morph has it: shared letters between the two, new letters
/// at their new place, leaving letters where they were.
struct TextMorphRow: Layout {
    var progress: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let slots = positions(subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: slots.oldWidth + (slots.newWidth - slots.oldWidth) * progress, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let slots = positions(subviews)
        for (index, subview) in subviews.enumerated() {
            let x: CGFloat = switch (slots.old[index], slots.new[index]) {
            case let (from?, to?): from + (to - from) * progress
            case let (nil, to?): to
            case let (from?, nil): from
            case (nil, nil): 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY), anchor: .topLeading,
                          proposal: .unspecified)
        }
    }

    private func positions(_ subviews: Subviews) -> (old: [CGFloat?], new: [CGFloat?], oldWidth: CGFloat, newWidth: CGFloat) {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        func place(_ slot: (TextMorphSlot.Value) -> Int?) -> ([CGFloat?], CGFloat) {
            var xs = [CGFloat?](repeating: nil, count: subviews.count)
            var cursor: CGFloat = 0
            let ordered = subviews.indices.compactMap { i in slot(subviews[i][TextMorphSlot.self]).map { (i, $0) } }
            for (i, _) in ordered.sorted(by: { $0.1 < $1.1 }) {
                xs[i] = cursor
                cursor += widths[i]
            }
            return (xs, cursor)
        }
        let (old, oldWidth) = place(\.from)
        let (new, newWidth) = place(\.to)
        return (old, new, oldWidth, newWidth)
    }
}
