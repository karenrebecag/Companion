import SwiftUI

/// Arc's control values on the island (dropdown-menu, tooltip, badge,
/// confirm-morph), in one place so a chip, a row and a bubble cannot drift
/// apart. The window keeps Incredible's values: these are island-only.
enum IslandArc {
    /// Arc's snappy press: a control gives a little under the finger.
    static let pressScale: CGFloat = 0.97
    /// Arc's border-strong, derived: the border with 12 % foreground in it.
    static let strongMix = 0.12
    static var borderStrong: Swatch { ArcTone.mix(ArcTone.foreground, strongMix, over: ArcTone.border) }

    /// confirm-morph's danger tone: a whisper at rest, louder only on hover.
    enum Danger {
        static let fill = 0.04
        static let edge = 0.18
        static let hover = 0.08
        static var fillSwatch: Swatch { ArcTone.mix(ArcTone.danger, fill, over: ArcTone.surfaceRaised) }
        static var hoverSwatch: Swatch { ArcTone.mix(ArcTone.danger, hover, over: ArcTone.surfaceRaised) }
        static var edgeSwatch: Swatch { ArcTone.mix(ArcTone.danger, edge, over: ArcTone.border) }
    }

    enum Menu {
        static let padding: CGFloat = 5
        static let radius: CGFloat = 26
        /// Concentric with the panel: radius minus the 5 padding and its 1 rim.
        static let itemRadius: CGFloat = radius - 6
        static let itemMinHeight: CGFloat = 36
        static let itemPaddingX: CGFloat = 11
        static let itemGap: CGFloat = 10
        static let dangerHighlight = 0.08
        static var dangerHighlightSwatch: Swatch {
            ArcTone.mix(ArcTone.danger, dangerHighlight, over: ArcTone.surface)
        }
    }

    enum Tooltip {
        static let paddingY: CGFloat = Space.x3
        static let paddingX: CGFloat = Space.x4
        static let radius: CGFloat = 18
        static let maxWidth: CGFloat = 240
        /// The rim: 14 % of the page's black mixed into the bubble.
        static let rimMix = 0.14
        static var rimSwatch: Swatch { ArcTone.mix(Swatch("000000"), rimMix, over: ArcTone.foreground) }
    }
}
