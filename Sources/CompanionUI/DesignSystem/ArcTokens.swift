import SwiftUI

/// Arc's motion presets (uiarc.dev `lib/motion-tokens.ts`). A motion spring
/// with `visualDuration` d and `bounce` b is SwiftUI's spring with response d
/// and damping 1 - b, so they live as `MotionSpring` and the M4 checks apply.
/// Named by use, not by Arc's names: `.smooth` and `.snappy` read as SwiftUI's
/// own soft springs, which the conformance contract keeps out of views.
package enum ArcMotion {
    /// Arc's `smooth`: panels, heights, progress, layout. Reports state, so it never overshoots.
    package static let panel = MotionSpring(response: 0.4, damping: 1)
    /// Arc's `snappy`: presses, small indicators, icon swaps.
    package static let press = MotionSpring(response: 0.26, damping: 1 - 0.12)

    package enum Duration {
        package static let fast = 0.16
        /// Exits run faster than entrances.
        package static let exit = 0.18
        package static let standard = 0.24
    }

    package enum Curve {
        package static let enter: [Double] = [0.16, 1, 0.3, 1]
        package static let exit: [Double] = [0.7, 0, 0.84, 0]
        package static let standard: [Double] = [0.22, 1, 0.36, 1]
    }

    /// Blur radii for brief crossfades only.
    package enum Blur {
        package static let soft: CGFloat = 4
    }

    package static func enter(_ duration: Double = Duration.standard) -> Animation {
        MotionCurve.animation(Curve.enter, duration)
    }

    package static func exit(_ duration: Double = Duration.exit) -> Animation {
        MotionCurve.animation(Curve.exit, duration)
    }

    /// Color and opacity changes on something already on screen.
    package static func fade(_ duration: Double = Duration.standard) -> Animation {
        MotionCurve.animation(Curve.standard, duration)
    }
}

extension MotionSpring {
    /// Reduce Motion keeps the final state and drops the travel.
    package func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Arc's dark-theme tones (foundation.css, `[data-theme="dark"]`), resolved
/// from OKLCH to sRGB. The island is always dark, so it takes only these:
/// one tone per meaning instead of a hex per view.
package enum ArcTone {
    package static let success = Swatch("4CD676")
    package static let warning = Swatch("FFB90E")
    package static let danger = Swatch("FF736D")
    /// The blue accent's dark value.
    package static let accent = Swatch("6BA3FF")
    package static let surface = Swatch("191919")
    package static let surfaceRaised = Swatch("1F1F1F")
    package static let surfaceMuted = Swatch("242424")
    package static let border = Swatch("2B2B2B")
    package static let borderSubtle = Swatch("222222")
    package static let foreground = Swatch("F2F2F2")
    package static let textSecondary = Swatch("B4B4B4")
    package static let textMuted = Swatch("8C8C8C")
    /// Arc's dark chart series, in order.
    package static let chartSeries = [Swatch("55ADFF"), Swatch("9C37BE"), Swatch("E66E00"), Swatch("00A861")]
    /// A tone washed over a surface, as `color-mix(in oklab, tone 12%, transparent)`.
    package static func wash(_ tone: Swatch, _ amount: Double = 0.12) -> Color { tone.color.opacity(amount) }

    /// `color-mix(tone amount, base)` as an opaque swatch. A wash over the
    /// black island would darken toward black; Arc mixes into the surface the
    /// control sits on, so the result has to be solid.
    package static func mix(_ tone: Swatch, _ amount: Double, over base: Swatch) -> Swatch {
        let share = min(1, max(0, amount))
        let mixed = zip(channels(tone), channels(base)).map { top, bottom in
            Int((Double(top) * share + Double(bottom) * (1 - share)).rounded())
        }
        return Swatch(mixed.map { String(format: "%02X", $0) }.joined())
    }

    private static func channels(_ swatch: Swatch) -> [Int] {
        let value = Int(swatch.hex, radix: 16) ?? 0
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
    }
}
