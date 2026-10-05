import CompanionCore
import Foundation
import SwiftUI

/// Run card measures, read off firstRun-BOTAwJJ8.css. The reference defines no
/// max height; the island's own column caps it.
enum RunCardMetrics {
    static let minWidth: CGFloat = 320
    static let maxWidth: CGFloat = 420
    static let padTop: CGFloat = 14
    static let padSide: CGFloat = 16
    static let padBottom: CGFloat = 12
    static let radius: CGFloat = 20
    static let riseOffset: CGFloat = 6
    static let fadeSeconds: Double = 0.2
    /// firstRun-BOTAwJJ8.css @395492
    static let headGap: CGFloat = 10
    static let headBottom: CGFloat = 8
    /// firstRun-BOTAwJJ8.css @395573
    static let titleSize: CGFloat = 13
    static let titleWeight = Font.Weight.semibold
    /// firstRun-BOTAwJJ8.css @395683
    static let metaSize: CGFloat = 11.5
    static let metaOpacity: Double = 0.55
    static let rowPadV: CGFloat = 5
    static let rowPadH: CGFloat = 2
    static let rowGap: CGFloat = 2
    static let mainGap: CGFloat = 10
    static let glyphSide: CGFloat = 18
    static let glyphTop: CGFloat = 1
    static let glyphFont: CGFloat = 11
    static let glyphWeight = Font.Weight.bold
    static let spinnerSide: CGFloat = 14
    static let spinnerStroke: CGFloat = 2
    static let spinnerPeriod: Double = 0.9
    /// A quarter of the ring is the lit arc, as a one-sided CSS border draws it.
    static let spinnerArcFraction: CGFloat = 0.25
    static let stepTitleSize: CGFloat = 12.5
    static let durationSize: CGFloat = 11.5
    static let durationLead: CGFloat = 10
    /// firstRun-BOTAwJJ8.css @394242
    static let shadowNearY: CGFloat = 1
    static let shadowNearBlur: CGFloat = 2
    static let shadowFarY: CGFloat = 18
    static let shadowFarBlur: CGFloat = 48
    /// A CSS blur is twice SwiftUI's shadow radius.
    static let cssBlurToRadius: CGFloat = 0.5
}

enum RunCardDuration {
    /// "12s" under a minute, "1m 05s" after.
    static func step(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        guard whole >= 60 else { return "\(whole)s" }
        return "\(whole / 60)m " + String(format: "%02d", whole % 60) + "s"
    }

    /// "m:ss"; minutes do not roll into hours.
    static func total(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}

struct RunCardRow: Equatable, Identifiable {
    enum State: Equatable { case done, failed, live }
    let id: String
    let title: String
    let state: State
    let duration: String?
    let durationIsLive: Bool
}

enum RunCardModel {
    /// Thinking is dropped because the reference card has no thinking rows.
    /// Time comes in as `now` so durations replay deterministically.
    static func rows(steps: [JobStepInfo], now: Date) -> [RunCardRow] {
        steps.filter { $0.tool != JobSteps.Thinking.tool }.map { step in
            let state: RunCardRow.State =
                step.failed ? .failed : step.done ? .done : .live
            // A finished step with no end time has no honest duration.
            let end = state == .live ? now : step.finishedAt
            let duration = end.map {
                RunCardDuration.step($0.timeIntervalSince(step.startedAt))
            }
            return RunCardRow(
                id: step.id, title: text(step.label), state: state,
                duration: duration,
                durationIsLive: state == .live)
        }
    }

    static func meta(jobStartedAt: Date, now: Date) -> String {
        RunCardDuration.total(now.timeIntervalSince(jobStartedAt))
    }

    enum Glyph: Equatable { case symbol(String), spinner }

    /// The one decision of which glyph a state wears; the view only draws it.
    static func glyph(for state: RunCardRow.State) -> Glyph {
        switch state {
        case .done: .symbol("checkmark")
        case .failed: .symbol("xmark")
        case .live: .spinner
        }
    }

    static func stateKey(_ state: RunCardRow.State) -> String {
        switch state {
        case .done: "island.runcard.state.done"
        case .failed: "island.runcard.state.failed"
        case .live: "island.runcard.state.running"
        }
    }

    /// The header goal passes the same cleaner as the step titles.
    static func goal(_ raw: String) -> String { text(raw) }

    /// Titles are model-chosen text: control and format characters (bidi
    /// overrides and isolates among them) could reorder or hide what the
    /// user reads, and breaks would grow the row. The joiners stay: Persian,
    /// Indic scripts and emoji sequences are not written without them.
    private static func text(_ raw: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .lineSeparator, .paragraphSeparator: kept.append(" ")
            case .control where scalar.properties.isWhitespace: kept.append(" ")
            case .control: continue
            case .format where scalar == "\u{200C}" || scalar == "\u{200D}": kept.append(scalar)
            case .format: continue
            default: kept.append(scalar)
            }
        }
        return String(kept).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The island's column caps the card with its siblings; anchored at the
    /// bottom, the live step (the newest) stays in view when it scrolls.
    static func anchorsColumnBottom(cardVisible: Bool) -> Bool { cardVisible }

    /// The hover target is the island's own content root, present in every
    /// size that shows content, so a bare job (no transcript, reel, agents
    /// or reply) still has somewhere for the pointer to land.
    static func hoverRegionExists(size: IslandState.Size) -> Bool {
        switch size {
        case .hidden, .pebble: false
        case .nudge, .bar, .card, .wideCard: true
        }
    }

    /// The hover modifier leaves with the region and may never report the
    /// pointer leaving, so a resize to a size without one forgets the hover.
    static func hoverAfterResize(raw: Bool, newSize: IslandState.Size) -> Bool {
        raw && hoverRegionExists(size: newSize)
    }

    /// Keyboard focus counts so the card stays reachable without a pointer.
    static func visible(hovering: Bool, focused: Bool) -> Bool {
        hovering || focused
    }

    /// The raw pointer state is kept as the pointer left it; whether the
    /// island has a hover region NOW is decided here, so a hover that began
    /// at another size never goes stale.
    static func showsCard(rawHover: Bool, size: IslandState.Size, focused: Bool) -> Bool {
        visible(hovering: rawHover && hoverRegionExists(size: size), focused: focused)
    }

    /// Only the spinner stops under Reduce Motion; the timer keeps ticking.
    static func spins(reduceMotion: Bool) -> Bool { !reduceMotion }
}
