import SwiftUI

/// Incredible's light palette (16l), measured in its CSS. The light side of
/// every Semantic role resolves to one of these; dark keeps the Neutral ramp.
package enum Palette {
    package static let canvas = Swatch("FCFCFC")
    package static let surface = Swatch("FFFFFF")
    package static let surfaceSecondary = Swatch("F9F9F9")
    package static let surfaceInset = Swatch("E5E5EA")
    package static let textPrimary = Swatch("1C1C1E")
    package static let textSecondary = Swatch("6C6C70")
    package static let textMuted = Swatch("727276")
    package static let textFaint = Swatch("8E8E93")
    package static let borderDefault = Swatch("E5E5EA")
    package static let borderInput = Swatch("E0E0E5")
    package static let borderChrome = Swatch("EEEEEE")
    package static let statusGreen = Swatch("34C759")
    package static let statusOrange = Swatch("FF9500")
    package static let statusRed = Swatch("FF3B30")
    package static let danger = Swatch("DC2626")
    package static let dangerHover = Swatch("B91C1C")
    /// The island's live/success green and the dark switch's "on".
    package static let signalGreen = Swatch("78D6A8")
    /// Links and focus only: Incredible's buttons are black.
    package static let link = Swatch("007AFF")
}

/// Incredible's translucent states, as black-over-light alphas.
package enum StateAlpha {
    package static let hover = 0.02
    package static let active = 0.05
    package static let row = 0.05
    package static let statusMuted = 0.12
    package static let dangerWash = 0.10
    package static let dangerWashHover = 0.15
    package static let disabled = 0.5
}
