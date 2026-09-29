import SwiftUI

/// The one decision the window chrome makes about movement (16p-1): with
/// Reduce Motion on, state changes are instant and transitions fall back to
/// a plain fade.
enum ChromeMotion {
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }

    static func transition(
        _ base: AnyTransition, reduceMotion: Bool, animation: Animation? = nil
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return animation.map { base.animation($0) } ?? base
    }
}
