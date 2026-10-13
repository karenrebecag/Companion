import Foundation

// Arc's text-morph and text-shimmer (uiarc.dev, free tier) as pure numbers:
// which letters a label change keeps, when each letter moves, and where the
// shimmer's light sits. The views only draw what these compute, so a frame at
// any instant can be rendered offscreen.

/// One letter in a morph. `from` and `to` are its slots in the old and the new label.
package struct TextMorphGlyph: Equatable, Sendable {
    package let key: String
    package let character: Character
    package let from: Int?
    package let to: Int?
    /// Reading-order rank among the letters that are new; only they stagger.
    package let enterOrder: Int?
}

package enum TextMorphPlan {
    /// Letters match by character and occurrence: the second "n" pairs with the second "n".
    package static func keyed(_ text: String) -> [(character: Character, key: String)] {
        var seen: [Character: Int] = [:]
        return text.map { character in
            let count = seen[character, default: 0]
            seen[character] = count + 1
            return (character, "\(character)-\(count)")
        }
    }

    /// The new label's letters in order, then the letters that leave.
    package static func plan(from old: String, to new: String) -> [TextMorphGlyph] {
        let before = keyed(old), after = keyed(new)
        let oldSlots = Dictionary(uniqueKeysWithValues: before.enumerated().map { ($0.element.key, $0.offset) })
        let newKeys = Set(after.map(\.key))
        var entering = 0
        var glyphs = after.enumerated().map { index, glyph -> TextMorphGlyph in
            let from = oldSlots[glyph.key]
            defer { if from == nil { entering += 1 } }
            return TextMorphGlyph(key: glyph.key, character: glyph.character, from: from, to: index,
                                  enterOrder: from == nil ? entering : nil)
        }
        for (index, glyph) in before.enumerated() where !newKeys.contains(glyph.key) {
            glyphs.append(TextMorphGlyph(key: glyph.key, character: glyph.character, from: index, to: nil,
                                         enterOrder: nil))
        }
        return glyphs
    }
}

package enum TextMorphTiming {
    /// Leaving letters start to clear before the first new letter sharpens in.
    package static let handoff: TimeInterval = 0.05
    /// Arc caps the stagger at the ninth new letter so a long word does not trail.
    package static let staggerCap = 8
    package static let enterDuration: TimeInterval = ArcMotion.Duration.standard + 0.04
    package static let layout = ArcMotion.panel

    /// How far shared letters and the width have travelled: a critically damped spring.
    package static func layoutProgress(_ elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        guard elapsed.isFinite else { return 1 }
        let omega = 2 * Double.pi / layout.response
        return 1 - (1 + omega * elapsed) * exp(-omega * elapsed)
    }

    package static func enterDelay(order: Int) -> TimeInterval {
        handoff + Double(min(order, staggerCap)) * Stagger.dense
    }

    package static func enterProgress(_ elapsed: TimeInterval, order: Int) -> Double {
        MotionCurve.value(ArcMotion.Curve.enter, at: (elapsed - enterDelay(order: order)) / enterDuration)
    }

    package static func exitProgress(_ elapsed: TimeInterval) -> Double {
        MotionCurve.value(ArcMotion.Curve.standard, at: elapsed / ArcMotion.Duration.exit)
    }

    /// When the last letter and the width are at rest.
    package static func total(_ plan: [TextMorphGlyph]) -> TimeInterval {
        let lastEnter = plan.compactMap(\.enterOrder).max().map { enterDelay(order: $0) + enterDuration } ?? 0
        return max(layout.settle, lastEnter, ArcMotion.Duration.exit)
    }
}

package enum TextShimmerMotion {
    /// Arc's defaults: one pass in 1.8 s, a rest of a third of that, a short lead-in.
    package static let pass: TimeInterval = 1.8
    package static let restShare = 0.32
    package static let leadIn: TimeInterval = 0.12
    /// The band's half width, in ems.
    package static let bandEms: Double = 2.2
    package static let settleOut: TimeInterval = 0.36
    package static let settleIn: TimeInterval = ArcMotion.Duration.standard
    /// The bell's [offset, strength] stops, offset in band half widths.
    package static let falloff: [(offset: Double, strength: Double)] = [
        (-1, 0), (-0.5, 0.5), (-0.2, 0.9), (0, 1), (0.2, 0.9), (0.5, 0.5), (1, 0),
    ]

    /// 0 sits left of the text, 1 right of it, and it rests at 1 between passes.
    package static func sweep(_ elapsed: TimeInterval) -> Double {
        guard elapsed > leadIn else { return 0 }
        let cycle = pass * (1 + restShare)
        let t = (elapsed - leadIn).truncatingRemainder(dividingBy: cycle)
        return min(1, t / pass)
    }

    /// How solid the base is: 0 shows the muted base under the band, 1 is plain text.
    package static func settle(active: Bool, sinceToggle: TimeInterval) -> Double {
        if active {
            return 1 - MotionCurve.value(ArcMotion.Curve.standard, at: sinceToggle / settleIn)
        }
        return MotionCurve.value(ArcMotion.Curve.standard, at: sinceToggle / settleOut)
    }

    /// The band's ends in the text's unit space for a sweep `t`, a text `width` and an `em`.
    package static func bandEnds(sweep t: Double, width: Double, em: Double) -> (start: Double, end: Double) {
        let half = width > 0 ? bandEms * em / width : 0
        return (t + (2 * t - 2) * half, t + 2 * t * half)
    }
}
