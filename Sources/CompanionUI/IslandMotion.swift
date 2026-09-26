import CompanionCore
import SwiftUI

/// How the island moves (Wave 16f), in numbers taken frame by frame from
/// Karen's recording of Incredible (spec 16f §4), not invented. The shape
/// moves first and the content follows; closing is the reverse.
enum IslandMotion {
    /// Where the shape is heading on one step.
    enum Stage: Equatable {
        /// The size of the notch: at rest it is indistinguishable from it.
        case notch
        /// Wide and low, the first half of opening.
        case pill
        /// The size the content asks for.
        case full
    }

    enum Curve: Equatable {
        case spring(response: Double, damping: Double)
        case fade(Double)

        var animation: Animation {
            switch self {
            case .spring(let response, let damping): .spring(response: response, dampingFraction: damping)
            case .fade(let seconds): .expoOut(seconds)
            }
        }
    }

    struct Step: Equatable {
        let stage: Stage
        let delay: Double
        let curve: Curve
    }

    /// Phase 1: 51 % of the way in 17 ms, 90 % in 67 ms, no overshoot.
    static let firstSpring = curve(MotionSpring.islandPill)
    /// Phase 2 and every resize while open: overshoots ~1.6 %, settles ~150 ms.
    static let secondSpring = curve(MotionSpring.islandPanel)
    static let closeSpring = curve(MotionSpring.islandClose)

    private static func curve(_ spring: MotionSpring) -> Curve {
        .spring(response: spring.response, damping: spring.damping)
    }
    /// The pill holds ~25 ms before phase 2 starts.
    static let secondPhase = 0.16
    /// Content rides the growing panel, clipped by it, so the panel is
    /// never seen open and empty (spec 16i §5, Karen's 18:01 recording).
    static let contentLead = 0.04
    /// Leaving, the content fades while the shape already closes.
    static let closeFade = 0.08
    /// NotchNook's peek: the pointer has to stay this long before it opens,
    /// so crossing the notch on the way to the menu bar opens nothing.
    static let peekDwell = 0.15

    static func steps(from: IslandState.Size, to: IslandState.Size, reduceMotion: Bool) -> [Step] {
        let target: Stage = rests(to) ? .notch : .full
        if reduceMotion { return [Step(stage: target, delay: 0, curve: .fade(MotionTime.fast))] }
        switch (rests(from), rests(to)) {
        case (true, false):
            return [Step(stage: .pill, delay: 0, curve: firstSpring),
                    Step(stage: .full, delay: secondPhase, curve: secondSpring)]
        case (false, true):
            return [Step(stage: .notch, delay: 0, curve: closeSpring)]
        case (false, false):
            return [Step(stage: .full, delay: 0, curve: secondSpring)]
        case (true, true):
            return [Step(stage: .notch, delay: 0, curve: closeSpring)]
        }
    }

    /// When the content starts to fade in, from the moment the size changed.
    static func contentStart(from: IslandState.Size, to: IslandState.Size, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        return (steps(from: from, to: to, reduceMotion: false).last?.delay ?? 0) + contentLead
    }

    /// How long the panel is open with its content invisible: opening, from
    /// the moment it grows past the pill until the content starts; closing,
    /// from the content leaving until the shape starts to close.
    static func emptyPanel(from: IslandState.Size, to: IslandState.Size) -> Double {
        switch (rests(from), rests(to)) {
        case (true, false): contentStart(from: from, to: to, reduceMotion: false) - secondPhase
        case (false, true): steps(from: from, to: to, reduceMotion: false).first?.delay ?? 0
        default: 0
        }
    }

    static func rests(_ size: IslandState.Size) -> Bool {
        size == .hidden || size == .pebble
    }
}

/// The reply as it is said (16f): every word is on screen from the start,
/// dim, and brightens at the pace of the voice. Without a voice, all at once.
enum IslandReveal {
    static let wordsPerSecond: Double = 3

    static func shown(words: Int, elapsed: Double, speaking: Bool) -> Int {
        guard speaking else { return words }
        return min(words, 1 + Int(max(elapsed, 0) * wordsPerSecond))
    }

    /// 0 dim, 1 bright. Each word fades in over `wordFade` from its own
    /// moment, so the light travels along the line instead of stepping (M1).
    static func brightness(word: Int, elapsed: Double, speaking: Bool) -> Double {
        guard speaking else { return 1 }
        let start = Double(word) / wordsPerSecond
        return min(max((elapsed - start) / IslandMotionBudget.wordFade, 0), 1)
    }
}

/// Every move in the island besides the shape (spec 16f §9), as numbers
/// the rules are checked on. Views read these; they never write a curve.
enum IslandMotionBudget {
    struct Move: Equatable {
        let duration: Double
        let blur: CGFloat
        /// Points on Y the element travels as it enters.
        let offset: CGFloat

        /// Reduce motion: a short fade, nothing travels or blurs (M8).
        var reduced: Move { Move(duration: min(duration, MotionTime.fast), blur: 0, offset: 0) }

        func animation(reduceMotion: Bool) -> Animation {
            .expoOut(reduceMotion ? reduced.duration : duration)
        }

        func resolved(reduceMotion: Bool) -> Move { reduceMotion ? reduced : self }
    }

    /// Panel reveal: the content under the shape.
    static let contentIn = Move(duration: 0.13, blur: 3, offset: 4)
    /// Text states swap: the status line.
    static let textSwap = Move(duration: 0.15, blur: 2, offset: 4)
    /// Texts reveal: result cards, one after another.
    static let line = Move(duration: 0.45, blur: 3, offset: 12)
    /// Panel reveal, small: the approval sheet.
    static let approval = Move(duration: 0.3, blur: 2, offset: 8)

    static let moves: [(String, Move)] = [
        ("contentIn", contentIn), ("textSwap", textSwap), ("line", line), ("approval", approval),
    ]

    /// transitions.dev menu dropdown: grows from its trigger, leaves faster.
    struct Popover: Equatable {
        let openDuration: Double
        let closeDuration: Double
        let fromScale: CGFloat
    }

    /// transitions.dev tooltip: a beat before it shows, gone at once.
    struct Tooltip: Equatable {
        let delay: Double
        let inDuration: Double
        let outDuration: Double
    }

    struct IconSwap: Equatable {
        let duration: Double
        let fromScale: CGFloat
        let blur: CGFloat
    }

    static let popover = Popover(openDuration: 0.25, closeDuration: 0.15, fromScale: 0.97)
    static let tooltip = Tooltip(delay: 0.08, inDuration: 0.15, outDuration: 0.05)
    /// The orb turning into the stop button while it speaks.
    static let iconSwap = IconSwap(duration: 0.2, fromScale: 0.25, blur: 2)

    static let wordFade = 0.15
    static let lineStep = 0.04
    /// Past the fifth line the rest arrive together: a list must not crawl.
    static let maxStaggered = 5

    static func delay(line index: Int) -> Double {
        Double(min(index, maxStaggered - 1)) * lineStep
    }
}
