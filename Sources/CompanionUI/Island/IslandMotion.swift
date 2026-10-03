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
        case timing([Double], Double)
        case fade(Double)

        var animation: Animation {
            switch self {
            case .timing(let points, let seconds): MotionCurve.animation(points, seconds)
            case .fade(let seconds): .expoOut(seconds)
            }
        }

        var duration: Double {
            switch self {
            case .timing(_, let seconds), .fade(let seconds): seconds
            }
        }
    }

    struct Step: Equatable {
        let stage: Stage
        let delay: Double
        let curve: Curve
    }

    // Incredible 0.2.36 moves the shape with plain curves, not springs (Karen, D5b: the literal curve).
    /// Opening, and growing while open: one --ease-island curve per step.
    static let shapeOpen = Curve.timing(MotionCurve.island, 0.33)
    /// Back to the notch, without overshoot.
    static let shapeClose = Curve.timing(MotionCurve.standard, 0.28)
    /// Shrinking while open, without overshoot.
    static let shapeShrink = Curve.timing(MotionCurve.standard, 0.26)
    /// The pill holds ~25 ms before phase 2 starts (Karen's recording).
    static let secondPhase = 0.16
    /// Content fades in this long after opening starts, clipped by the growing shape,
    /// so the panel is never seen open and empty (spec 16i §5).
    static let contentDelay = 0.06
    /// Leaving, the content fades as long as it took to enter, while the shape already closes.
    static let closeFade = IslandMotionBudget.contentOut.duration

    /// A resize of the open island that follows its content.
    static func resize(growing: Bool) -> Curve {
        growing ? shapeOpen : shapeShrink
    }

    /// Only a larger area overshoots: a narrower or equal shape must not bounce.
    static func grows(from current: CGSize, to target: CGSize) -> Bool {
        target.width * target.height > current.width * current.height
    }

    enum Event: Equatable {
        case shape(Stage)
        case content
    }

    struct Beat: Equatable {
        let at: Double
        let event: Event
        let curve: Curve?
    }

    /// Shape steps and the content's entrance on one clock from the moment the size
    /// changed, so the content can start under a shape that is still growing.
    static func timeline(
        from: IslandState.Size, to: IslandState.Size, reduceMotion: Bool, growing: Bool = true
    ) -> [Beat] {
        let shape = steps(from: from, to: to, reduceMotion: reduceMotion, growing: growing)
            .map { Beat(at: $0.delay, event: .shape($0.stage), curve: $0.curve) }
        guard !rests(to) else { return shape }
        let content = Beat(at: contentStart(from: from, to: to, reduceMotion: reduceMotion), event: .content, curve: nil)
        // Stable order: on a tie the shape moves first.
        return (shape + [content]).enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }
    /// NotchNook's peek: the pointer has to stay this long before it opens,
    /// so crossing the notch on the way to the menu bar opens nothing.
    static let peekDwell = 0.15

    static func steps(
        from: IslandState.Size, to: IslandState.Size, reduceMotion: Bool, growing: Bool = true
    ) -> [Step] {
        let target: Stage = rests(to) ? .notch : .full
        if reduceMotion { return [Step(stage: target, delay: 0, curve: .fade(MotionTime.fast))] }
        switch (rests(from), rests(to)) {
        case (true, false):
            return [Step(stage: .pill, delay: 0, curve: shapeOpen),
                    Step(stage: .full, delay: secondPhase, curve: shapeOpen)]
        case (false, true), (true, true):
            return [Step(stage: .notch, delay: 0, curve: shapeClose)]
        case (false, false):
            return [Step(stage: .full, delay: 0, curve: resize(growing: growing))]
        }
    }

    /// When the content starts to fade in, from the moment the size changed.
    static func contentStart(from: IslandState.Size, to: IslandState.Size, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : contentDelay
    }

    /// How long the panel is open with its content invisible: opening, from
    /// the moment it grows past the pill until the content starts; closing,
    /// from the content leaving until the shape starts to close.
    static func emptyPanel(from: IslandState.Size, to: IslandState.Size) -> Double {
        switch (rests(from), rests(to)) {
        case (true, false): max(0, contentStart(from: from, to: to, reduceMotion: false) - secondPhase)
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

    /// 0 unsaid, 1 said. A said word's color settles from its own moment, as Incredible's
    /// CSS color transition does, so the light travels along the line instead of stepping.
    static func brightness(word: Int, elapsed: Double, speaking: Bool, reduceMotion: Bool = false) -> Double {
        guard speaking else { return 1 }
        let since = elapsed - Double(word) / wordsPerSecond
        // Incredible drops the transition under reduce motion: the word turns at once.
        if reduceMotion { return since > 0 ? 1 : 0 }
        let spoken = IslandMotionBudget.spokenWord
        return MotionCurve.value(spoken.curve, at: min(max(since / spoken.duration, 0), 1))
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
        var reduced: Move { Move(duration: min(duration, MotionTime.fast), blur: 0, offset: 0, curve: curve) }

        /// The curve it enters with; most moves use the one entry curve (M3).
        var curve: [Double] = MotionCurve.enter

        func animation(reduceMotion: Bool) -> Animation {
            MotionCurve.animation(curve, reduceMotion ? reduced.duration : duration)
        }

        func resolved(reduceMotion: Bool) -> Move { reduceMotion ? reduced : self }
    }

    /// Panel reveal: the content under the shape, a plain fade as Incredible's.
    static let contentIn = Move(duration: 0.13, blur: 0, offset: 0, curve: MotionCurve.ease)
    /// Closing: the same fade back out, at the same time as the shape.
    static let contentOut = Move(duration: 0.13, blur: 0, offset: 0, curve: MotionCurve.ease)
    /// Texts reveal: result cards, one after another.
    static let line = Move(duration: 0.45, blur: 3, offset: 12)
    static let moves: [(String, Move)] = [
        ("contentIn", contentIn), ("line", line),
    ]

    /// Incredible's cards (`.ov-card`): they settle up into place and leave faster, down.
    struct Card: Equatable {
        enum Phase: Equatable { case entering, shown, leaving }

        struct State: Equatable {
            let opacity: Double
            /// Points on Y, positive is down.
            let offset: CGFloat
            let scale: CGFloat
        }

        let enter: IslandMotion.Curve
        let exit: IslandMotion.Curve
        let enterOffset: CGFloat
        let exitOffset: CGFloat
        let fromScale: CGFloat
        /// A confirmation grows from its bottom centre, toward the notch it hangs from.
        let anchor: UnitPoint
        /// Reduce motion: Incredible keeps a short linear fade in and drops the exit.
        let reducedFade: IslandMotion.Curve

        func state(_ phase: Phase) -> State {
            switch phase {
            case .entering: State(opacity: 0, offset: enterOffset, scale: fromScale)
            case .shown: State(opacity: 1, offset: 0, scale: 1)
            case .leaving: State(opacity: 0, offset: exitOffset, scale: fromScale)
            }
        }

        /// Where each direction starts or ends and on which clock; nil removal leaves at once.
        struct Plan: Equatable {
            let from: State
            let insertion: IslandMotion.Curve
            let to: State?
            let removal: IslandMotion.Curve?
        }

        /// Incredible's reduce motion keeps a short fade in and drops the exit.
        func plan(reduceMotion: Bool) -> Plan {
            reduceMotion
                ? Plan(from: State(opacity: 0, offset: 0, scale: 1), insertion: reducedFade, to: nil, removal: nil)
                : Plan(from: state(.entering), insertion: enter, to: state(.leaving), removal: exit)
        }
    }

    static let card = Card(
        enter: .timing(MotionCurve.settle, 0.26), exit: .timing(MotionCurve.settle, 0.2),
        enterOffset: 6, exitOffset: 4, fromScale: 0.98, anchor: .bottom,
        reducedFade: .timing(MotionCurve.linear, 0.12))

    /// Incredible's header swap: the new line rises from 120 % of its own height below,
    /// the old one leaves to 120 % above, each property on its own clock.
    struct HeaderSwap: Equatable {
        enum Phase: Equatable {
            case entering, shown, leaving

            init(_ phase: TransitionPhase) {
                switch phase {
                case .willAppear: self = .entering
                case .didDisappear: self = .leaving
                default: self = .shown
                }
            }
        }

        struct State: Equatable {
            /// Fractions of the line's own height; positive is down.
            let travel: CGFloat
            let opacity: Double
            let blur: CGFloat
        }

        let travel: CGFloat
        let blur: CGFloat
        let rise: IslandMotion.Curve
        let leave: IslandMotion.Curve
        let fade: IslandMotion.Curve
        let focus: IslandMotion.Curve

        func state(_ phase: Phase) -> State {
            switch phase {
            case .entering: State(travel: travel, opacity: 0, blur: blur)
            case .shown: State(travel: 0, opacity: 1, blur: 0)
            case .leaving: State(travel: -travel, opacity: 0, blur: blur)
            }
        }

        /// The old line leaves faster than the new one rises.
        func move(leaving: Bool) -> IslandMotion.Curve { leaving ? leave : rise }

        /// How long the swap is on screen: its slowest property.
        var longest: Double { [rise, leave, fade, focus].map(\.duration).max() ?? 0 }

        /// The animation that keeps the leaving line alive until its slowest property ends.
        func lifetime(reduceMotion: Bool) -> IslandMotion.Curve {
            reduceMotion ? .fade(MotionTime.fast) : .timing(MotionCurve.standard, longest)
        }

        /// Reduce motion swaps the line with a fade only: travel and blur are motion.
        func travels(reduceMotion: Bool) -> Bool { !reduceMotion }
    }

    static let headerSwap = HeaderSwap(
        travel: 1.2, blur: 2,
        rise: .timing(MotionCurve.island, 0.36), leave: .timing(MotionCurve.standard, 0.22),
        fade: .timing(MotionCurve.standard, 0.15), focus: .timing(MotionCurve.standard, 0.22))

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

    /// Incredible's spoken reply: the muted ink until a word is said, the primary one after.
    struct SpokenWord: Equatable {
        /// White alphas on the black island.
        let unsaid: Double
        let said: Double
        let curve: [Double]
        let duration: Double

        func alpha(brightness: Double) -> Double { unsaid + (said - unsaid) * brightness }
    }

    static let spokenWord = SpokenWord(unsaid: 0.48, said: 0.94, curve: MotionCurve.settle, duration: 0.22)
    static let lineStep = 0.04
    /// Past the fifth line the rest arrive together: a list must not crawl.
    static let maxStaggered = 5

    static func delay(line index: Int) -> Double {
        Double(min(index, maxStaggered - 1)) * lineStep
    }
}
