import SwiftUI

/// The one type scale and vertical rhythm every rendered reply shares (popup,
/// result document, chat). Sizes follow Arc's 12/14/16/18 steps; hierarchy
/// comes from size and ink, never from weight beyond regular and medium, and
/// no heading is set in capitals.
package enum AnswerType {
    package static let title: CGFloat = 18
    package static let section: CGFloat = 16
    package static let subheading: CGFloat = 14
    package static let body: CGFloat = 14
    package static let caption: CGFloat = 12

    /// Arc's body leading; the old 1.62/1.7 made two replies read at two densities.
    package static let leading: CGFloat = 1.4

    package static let regular = Font.Weight.regular
    package static let medium = Font.Weight.medium

    /// Every weight a reply token may use.
    package static let weights: [Font.Weight] = [regular, medium]

    // Rhythm on a 4-point grid. A heading owns more air above than below so it
    // reads as the head of what follows, not the tail of what precedes.
    package static let blockGap: CGFloat = Space.x3
    package static let paragraphGap: CGFloat = Space.x3
    package static let listItemGap: CGFloat = Space.x2
    package static let headingBefore: CGFloat = Space.x6
    package static let headingAfter: CGFloat = Space.x2
    package static let calloutPadY: CGFloat = Space.x3
    package static let calloutPadX: CGFloat = Space.x4
    package static let quotePadY: CGFloat = Space.x2
    package static let quotePadX: CGFloat = Space.x4

    /// Every spacing value above, for the grid check.
    package static let gaps: [CGFloat] = [
        blockGap, paragraphGap, listItemGap, headingBefore, headingAfter,
        calloutPadY, calloutPadX, quotePadY, quotePadX,
    ]
}
