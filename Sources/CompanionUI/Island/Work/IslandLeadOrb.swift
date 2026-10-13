import CompanionCore
import SwiftUI

/// What the lead column's orb shows. The voice orb keeps the states it has a
/// meter for (listening, speaking); work without a meter gets Space UI's
/// thinking orb, whose mode says which kind of work it is.
package enum IslandLeadMark: Equatable, Sendable {
    case voice(IslandOrbState)
    case thinking(ThinkingOrbMode)

    /// Nil leaves the column to the run's loader (a finished job) or the status light.
    package static func of(meter: IslandState.Meter, line: IslandState.Line, jobRunning: Bool) -> IslandLeadMark? {
        // A job owns the column whatever the voice does: it is the longest-lived work.
        // Strands braiding read as steps woven together, and stay legible at 32 pt where
        // the source's orbits and web thin out to scattered dots.
        if case .job = line { return jobRunning ? .thinking(.braid) : nil }
        switch meter {
        case .mic: return .voice(.listening)
        case .agent: return .voice(.speaking)
        case .none: break
        }
        switch line {
        // Sent and waiting, or pasting: the quietest state, a ring that only breathes.
        case .pending, .pasting: return .thinking(.ring)
        // The model reasoning: a point sphere turning its slices like a puzzle being solved.
        case .thinking: return .thinking(.rubik)
        // A tool looking through apps and files: a globe under a scan band.
        case .acting: return .thinking(.globe)
        default: return nil
        }
    }
}

enum IslandLeadOrbMetrics {
    /// The incoming orb grows from this share of its side, so the handoff reads as one mark changing.
    static let handoffScale: CGFloat = 0.6
    static let handoff: TimeInterval = MotionTime.panel
    /// Fills the 32 pt slot a little more than the source's 0.72 so the dots read at notch size.
    static let fill = 0.86
}

/// The lead column's orb: the package voice orb or the thinking orb,
/// crossfading in place so listening into thinking, or one kind of work into
/// another, never pops.
struct IslandLeadOrb: View {
    let mark: IslandLeadMark
    let levels: VoiceLevels
    let side: CGFloat
    var paused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if case .voice(let state) = mark {
                IslandVoiceOrb(state: state, levels: levels, size: side, active: !paused)
                    .transition(Self.handoff(reduceMotion: reduceMotion))
            }
            if case .thinking(let mode) = mark {
                // Keyed on the mode: a new kind of work is a new orb fading in over the old one.
                ThinkingOrb(mode: mode, surface: .ink, scale: IslandLeadOrbMetrics.fill, size: side, paused: paused)
                    .id(mode)
                    .transition(Self.handoff(reduceMotion: reduceMotion))
            }
        }
        .frame(width: side, height: side)
        .animation(ArcMotion.fade(IslandLeadOrbMetrics.handoff), value: mark)
    }

    static func handoff(reduceMotion: Bool) -> AnyTransition {
        .opacity.combined(with: .scale(scale: handoffScale(reduceMotion: reduceMotion)))
    }

    /// Reduce Motion keeps the crossfade and drops the growth.
    static func handoffScale(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : IslandLeadOrbMetrics.handoffScale
    }
}
