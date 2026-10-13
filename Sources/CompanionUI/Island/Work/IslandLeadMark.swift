import CompanionCore
import SwiftUI

/// What the lead column shows while the voice or the work runs. A static
/// glyph per state: Karen chose performance over the animated sphere
/// (2026-10-13), so nothing here draws per frame; the status line beside it
/// says which kind of work it is.
package enum IslandLeadMark: Equatable, Sendable {
    case listening
    case speaking
    case working

    /// Nil leaves the column to the run's loader (a finished job) or the status light.
    package static func of(meter: IslandState.Meter, line: IslandState.Line, jobRunning: Bool) -> IslandLeadMark? {
        // A job owns the column whatever the voice does: it is the longest-lived work.
        if case .job = line { return jobRunning ? .working : nil }
        switch meter {
        case .mic: return .listening
        case .agent: return .speaking
        case .none: break
        }
        switch line {
        case .pending, .pasting, .thinking, .acting: return .working
        default: return nil
        }
    }

    /// Nil draws the plain dot: work has no glyph of its own, its words say it.
    var symbol: String? {
        switch self {
        case .listening: "mic.fill"
        case .speaking: "waveform"
        case .working: nil
        }
    }
}

enum IslandLeadMarkMetrics {
    static let handoff: TimeInterval = MotionTime.panel
    /// The glyph inside the 32 pt slot, the size of the island's other icons.
    static let glyph: CGFloat = 15
    static let dot: CGFloat = 6
}

/// The lead column's glyph, crossfading when the state changes so listening
/// into working never pops. One fade per change, nothing in between.
struct IslandLeadGlyph: View {
    let mark: IslandLeadMark
    let side: CGFloat

    var body: some View {
        ZStack {
            Group {
                if let symbol = mark.symbol {
                    Image(systemName: symbol)
                        .font(Fonts.symbol(IslandLeadMarkMetrics.glyph, weight: .medium))
                        .foregroundStyle(IslandInk.text)
                } else {
                    Circle()
                        .fill(IslandInk.secondary)
                        .frame(width: IslandLeadMarkMetrics.dot, height: IslandLeadMarkMetrics.dot)
                }
            }
            .id(mark)
            .transition(.opacity)
        }
        .frame(width: side, height: side)
        .animation(ArcMotion.fade(IslandLeadMarkMetrics.handoff), value: mark)
        // The status line beside it carries the state for VoiceOver.
        .accessibilityHidden(true)
    }
}
