import SwiftUI

// The result document the island opens when a turn ends: one dark card with a
// title, prose, a table, source chips, and for a receipt a ledger of what was
// done. Values are measured from the local reference app and named here by
// use; nothing in the views below the design system carries a loose number.

package enum DocCardMetrics {
    /// The card's width; the island's shape adds its own margin on each side.
    package static let width: CGFloat = 589
    package static let radius: CGFloat = 20
    package static let padX: CGFloat = 20
    package static let padTop: CGFloat = 18
    package static let padBottom: CGFloat = 16
    /// Between the title, the blocks and the footer chips.
    package static let blockGap: CGFloat = 18

    package static let titleSize: CGFloat = 18
    package static let titleLeading: CGFloat = 1.2
    package static let titleTracking: CGFloat = -0.015

    package static let proseSize: CGFloat = 14.5
    package static let proseLeading: CGFloat = 1.7
    package static let proseMeasure: CGFloat = 504
    package static let paragraphGap: CGFloat = 14
    package static let listGapBefore: CGFloat = 10
    package static let listGapAfter: CGFloat = 16
    package static let listItemGap: CGFloat = 8
    /// The bullet column: the marker, then the text.
    package static let listIndent: CGFloat = 24
    package static let bulletSize: CGFloat = 5
    package static let bulletInset: CGFloat = 8
    /// The disc sits on the text's x-height, a little under the baseline guide.
    package static let bulletDrop: CGFloat = 1.5
    /// Where a table cell's line sits in its box (CSS 1.45).
    package static let tableLeading: CGFloat = 1.45

    package static let tableSize: CGFloat = 13.5
    package static let tableHeadSize: CGFloat = 11.5
    package static let tablePadX: CGFloat = 14
    package static let tablePadY: CGFloat = 10
    package static let tableRadius: CGFloat = 12
    package static let tableGapBefore: CGFloat = 8
    package static let tableGapAfter: CGFloat = 12
    /// A heading inside the prose; margins collapse with the blocks around it.
    package static let headingSize: CGFloat = 17
    package static let headingGapBefore: CGFloat = 22
    package static let headingGapAfter: CGFloat = 10

    /// Source chips: outlined pills under a hairline.
    package static let sourceHeight: CGFloat = 28
    package static let sourcePadX: CGFloat = 12
    package static let sourceSize: CGFloat = 12
    package static let sourceIcon: CGFloat = 12
    package static let sourcesTopPad: CGFloat = 10
    /// The sources block sits this much below where the blocks' own gap would put it.
    package static let sourcesLift: CGFloat = 4
    package static let chipGap: CGFloat = 8

    /// Action chips (the smaller outlined pill).
    package static let chipHeight: CGFloat = 26
    package static let chipPadX: CGFloat = 9
    package static let chipSize: CGFloat = 11.5

    /// The close button that fades in on hover.
    package static let toolSide: CGFloat = 32
    package static let toolInset: CGFloat = 16
    /// The title leaves this much room on the trailing side for the button.
    package static let toolReserve: CGFloat = 76

    /// A corner glow in the card's own accent; it never reaches the middle.
    package static let glowRadius: CGFloat = 190
    package static let glowStrong = 0.17
    package static let glowSoft = 0.05
    package static let glowMidStop: CGFloat = 0.45
    package static let glowEndStop: CGFloat = 0.7

    /// SwiftUI lays a line of Geist out at about this multiple of its size
    /// (measured; AppKit's own box for the face reads taller, so
    /// `Leading.spacing` over-trims it by a couple of points).
    package static let geistLine: CGFloat = 1.19

    /// What each line needs on top of its natural height to fill `leading`
    /// times its size, the way a CSS line box does.
    package static func lineExtra(size: CGFloat, leading: CGFloat) -> CGFloat {
        max(0, TypeScale.apply(size) * (leading - geistLine))
    }
    package static let shadowTight: CGFloat = 1
    package static let shadowDrop: CGFloat = 22
    package static let shadowBlur: CGFloat = 30
}

/// The receipt's ledger layout.
package enum DocReceiptMetrics {
    package static let tile: CGFloat = 48
    package static let tileRadius: CGFloat = 12
    package static let tileMark: CGFloat = 28
    package static let headGap: CGFloat = 16
    package static let titleSize: CGFloat = 16
    package static let titleTracking: CGFloat = -0.01
    package static let subSize: CGFloat = 12.5
    package static let subGap: CGFloat = 5
    package static let check: CGFloat = 20
    package static let checkOffset: CGFloat = 5
    package static let checkRing: CGFloat = 2
    package static let checkMark: CGFloat = 11
    package static let checkDraw = 0.42
    /// The ledger's lines sit under the title, past the tile.
    package static let ledgerIndent: CGFloat = 64
    package static let ledgerTop: CGFloat = 24
    package static let rowPadY: CGFloat = 9
    package static let rowGap: CGFloat = 14
    package static let valueSize: CGFloat = 13.5
    package static let valueLeading: CGFloat = 1.35
    /// The grid's row gap plus the rule's own pixel between two rows.
    package static let rowSpacing: CGFloat = 2
    package static let pillSize: CGFloat = 10.5
    package static let pillPadX: CGFloat = 8
    package static let pillPadY: CGFloat = 2
}

package enum DocCardInk {
    /// The card's fill and the colour the bottom fade ends in.
    package static let surface = Swatch("121317")
    package static let narrative = Swatch("8E97AE")
    package static let receipt = Swatch("5CC48B")
    package static let toolFill = Swatch("2C2E36")
    package static let toolFillHover = Swatch("3A3D47")
    package static let checkFill = Swatch("171C1A")
    package static let checkMark = Swatch("6ED69E")
    package static let pillDone = Swatch("74D6A8")
    package static let pillNeutral = Swatch("FFFFFF")

    package static let title = 1.0
    package static let prose = 0.84
    package static let proseStrong = 1.0
    package static let bullet = 0.46
    package static let secondary = 0.5
    package static let label = 0.46
    package static let value = 0.9
    package static let tableHead = 0.46
    package static let tableCell = 0.82
    package static let tableHeadFill = 0.05
    package static let line = 0.07
    package static let lineStrong = 0.14
    package static let rowLine = 0.04
    package static let sourcesLine = 0.05
    package static let sourceText = 0.78
    package static let sourceRing = 0.14
    package static let chipText = 0.7
    package static let chipRing = 0.16
    package static let tileFill = 0.07
    package static let pillFill = 0.16
    package static let pillNeutralFill = 0.08
    package static let shadowTight = 0.4
    package static let shadowDrop = 0.72
}

/// The stagger the document's blocks fade in with, after the card lands.
package enum DocCardMotion {
    package static let enter = 0.32
    package static let enterLift: CGFloat = 8
    package static let enterScale: CGFloat = 0.99
    package static let fade = 0.26
    package static let firstDelay = 0.08
    /// The second block and on start these much later; past the list, the last holds.
    package static let delays: [Double] = [0.11, 0.14, 0.17, 0.2]

    package static func delay(at index: Int) -> Double {
        index == 0 ? firstDelay : delays[min(index - 1, delays.count - 1)]
    }
}

/// The chat on the result document's paper: Arc ai-chat's sizes, set on the
/// card's own prose scale so a reply reads the same here as in the document.
package enum DocChatMetrics {
    package static let bodySize: CGFloat = DocCardMetrics.proseSize
    package static let captionSize: CGFloat = 12.5
    package static let headingSize: CGFloat = 16
    /// The field's words, one step over the prose: what she types is read back first.
    package static let fieldSize: CGFloat = 14.5
    package static let fieldLine: CGFloat = 21
    /// The thread lines up with the document's text column.
    package static let inset: CGFloat = DocCardMetrics.padX
    /// The thread's first turn starts where the document's title does; its
    /// last one sits close over the composer, which brings its own air.
    package static let threadTop: CGFloat = DocCardMetrics.padTop + 2
    package static let threadBottom: CGFloat = 2
    /// The composer stands this far from the card's sides and bottom.
    package static let composerInset: CGFloat = 12
    /// Between the thread, the rows under it and the composer.
    package static let gap: CGFloat = 10
    /// The conversations the panel keeps; older ones are the window's.
    package static let turns = 4
}

package extension DocCardInk {
    /// The composer's surface, a step over the paper (Arc's surface-raised).
    static let raised = Swatch("1B1D23")
    /// A focused composer's edge.
    static let edgeFocus = 0.26
    static let edge = 0.11
}
