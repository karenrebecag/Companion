import CompanionCore
import SwiftUI

// Wave 16m-2: the working states — the live transcript's two inks, the reel
// of touched apps and the shared work surface. The run itself is Arc's agent
// run (AgentRunTimeline.swift); its pure model is in AgentRunModel.swift.

package enum WorkStateMetrics {
    /// The reel of touched apps is a 26-pt band.
    package static let reelHeight: CGFloat = 26
    /// The reel's item is model-chosen text: past this many characters it
    /// is cut, so the chip and VoiceOver carry the same bounded string.
    package static let reelItemMax = 60
    /// Live transcription: 14/500 at 72 %, settling to 94 % once fixed.
    package static let transcriptSize: CGFloat = 14
    package static let transcriptLeading: CGFloat = 1.5
    package static let transcriptLive = 0.72
    package static let transcriptFixed = 0.94
}

/// The app this turn touched last: a quiet band under the status line with
/// one item, as Incredible's reel (K8). A row of every app crowded the band,
/// and an empty target painted an empty chip.
struct IslandReel: View {
    static func item(_ touched: [String]) -> String? {
        touched.lazy.map(shown).last { !$0.isEmpty }
    }

    /// Invisible characters (bidi overrides, zero-width, blank glyphs) can
    /// hide part of a model-chosen name from the eye and from VoiceOver, so
    /// they go; breaks become spaces so words stay apart. The scalar budget
    /// bounds combining marks, which a grapheme count alone lets through
    /// (security and QA review #212).
    private static func shown(_ target: String) -> String {
        var kept = String.UnicodeScalarView()
        var budget = WorkStateMetrics.reelItemMax * 4
        for scalar in target.unicodeScalars {
            guard let next = Self.kept(scalar) else { continue }
            kept.append(next)
            budget -= 1
            if budget == 0 { break }
        }
        let visible = String(kept).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard visible.count > WorkStateMetrics.reelItemMax else { return visible }
        let cut = String(visible.prefix(WorkStateMetrics.reelItemMax - 1))
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func kept(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let properties = scalar.properties
        switch properties.generalCategory {
        case .lineSeparator, .paragraphSeparator: return " "
        case .control: return properties.isWhitespace ? " " : nil
        case .format: return nil
        default:
            // U+2800 renders blank but is not default-ignorable.
            return properties.isDefaultIgnorableCodePoint || scalar == "\u{2800}" ? nil : scalar
        }
    }

    /// What VoiceOver reads: the band's name, then the app. Since K9 the
    /// status line says "Pensando", so the reel is the only place that names
    /// the app the agent is acting in (security review K9).
    static func spoken(_ item: String) -> (label: String, value: String) {
        (Localized.string("island.reel"), item)
    }

    let item: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.x1) {
            ReferentChip(text: item)
                .id(item)
                .transition(.opacity)
            Spacer(minLength: Space.none)
        }
        .animation(reduceMotion ? nil : .expoOut(MotionTime.reelSwap), value: item)
        .frame(height: WorkStateMetrics.reelHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(item).label)
        .accessibilityValue(Self.spoken(item).value)
    }
}
