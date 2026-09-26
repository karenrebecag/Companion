import SwiftUI

/// Incredible's light palette (16l), measured in its CSS. The light side of
/// every Semantic role resolves to one of these; dark keeps the Neutral ramp.
public enum Palette {
    public static let canvas = Swatch("FCFCFC")
    public static let surface = Swatch("FFFFFF")
    public static let surfaceSecondary = Swatch("F9F9F9")
    public static let surfaceInset = Swatch("E5E5EA")
    public static let textPrimary = Swatch("1C1C1E")
    public static let textSecondary = Swatch("6C6C70")
    public static let textMuted = Swatch("727276")
    public static let textFaint = Swatch("8E8E93")
    public static let borderDefault = Swatch("E5E5EA")
    public static let borderInput = Swatch("E0E0E5")
    public static let borderChrome = Swatch("EEEEEE")
    public static let statusGreen = Swatch("34C759")
    public static let statusOrange = Swatch("FF9500")
    public static let statusRed = Swatch("FF3B30")
    public static let danger = Swatch("DC2626")
    public static let dangerHover = Swatch("B91C1C")
    /// The island's live/success green and the dark switch's "on".
    public static let signalGreen = Swatch("78D6A8")
    /// Links and focus only: Incredible's buttons are black.
    public static let link = Swatch("007AFF")
}

/// Incredible's translucent states, as black-over-light alphas.
public enum StateAlpha {
    public static let hover = 0.02
    public static let active = 0.05
    public static let row = 0.05
    public static let statusMuted = 0.12
    public static let dangerWash = 0.10
    public static let dangerWashHover = 0.15
    public static let disabled = 0.5
}
