import CoreGraphics

/// What the island needs to know about a display (Wave 16f), read by the
/// app from `NSScreen` so the measuring stays pure and testable.
public struct ScreenShape: Sendable, Equatable {
    public let frame: CGRect
    public let visibleMaxY: CGFloat
    /// `safeAreaInsets.top`: zero on a screen without a notch.
    public let safeTop: CGFloat
    /// Widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, the menu
    /// bar on each side of the notch; nil where the system has none.
    public let leftAuxWidth: CGFloat?
    public let rightAuxWidth: CGFloat?

    public init(frame: CGRect, visibleMaxY: CGFloat, safeTop: CGFloat,
                leftAuxWidth: CGFloat?, rightAuxWidth: CGFloat?) {
        self.frame = frame
        self.visibleMaxY = visibleMaxY
        self.safeTop = safeTop
        self.leftAuxWidth = leftAuxWidth
        self.rightAuxWidth = rightAuxWidth
    }
}

/// The notch the island grows from, in screen coordinates (origin bottom-left).
public struct Notch: Sendable, Equatable {
    public let width: CGFloat
    public let height: CGFloat
    public let midX: CGFloat
    /// The screen's top edge: the island hangs from here, over the menu bar.
    public let top: CGFloat
    /// False on a screen without one: the island is then a pill as tall as
    /// the menu bar, so it still reads as part of the top edge.
    public let isHardware: Bool
}

public enum NotchGeometry {
    /// About the size of a notch, so the island looks the same on a screen
    /// that has none.
    public static let pillWidth: CGFloat = 190
    public static let minHeight: CGFloat = 24

    /// Measured, not assumed: notch sizes differ per model and scaling.
    public static func notch(on screen: ScreenShape) -> Notch {
        let top = screen.frame.maxY
        // A notch is always centred; the midpoint never comes from the aux
        // areas, which can be uneven while the menu bar is being laid out.
        let midX = screen.frame.midX
        if screen.safeTop > 0, let left = screen.leftAuxWidth, let right = screen.rightAuxWidth {
            let width = screen.frame.width - left - right
            if width > 0 {
                return Notch(width: width, height: screen.safeTop, midX: midX, top: top, isHardware: true)
            }
        }
        let menuBar = top - screen.visibleMaxY
        return Notch(width: pillWidth, height: max(menuBar, minHeight), midX: midX, top: top, isHardware: false)
    }

    /// The island lives on the screen with a notch; without one, on the
    /// first screen, which is the one with the menu bar.
    public static func pick(_ screens: [ScreenShape]) -> Int? {
        guard !screens.isEmpty else { return nil }
        return screens.firstIndex { $0.safeTop > 0 } ?? 0
    }
}
