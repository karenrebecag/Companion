import CompanionCore
import SwiftUI

/// Text-only page used by the new sidebar modules until each has its own
/// wave. Styled as an empty state: a leading icon in a soft round tile,
/// the page's title and description, and a muted "not in Companion yet"
/// line. No controls: the spec is explicit that placeholders must not
/// pretend to do something they cannot.
struct ModulePlaceholderPage: View {
    let placeholder: ModulePlaceholder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.x6) {
            icon(placeholder.symbol)
            copy()
        }
        // Filling the pane lets the VStack center the block on both axes
        // without an extra wrapper; the content's natural height changes
        // drive the height animation below.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.x6)
        .animation(ModulePlaceholderPage.pageAnimation(reduceMotion: reduceMotion), value: placeholder.page)
    }

    /// Decorative: hidden from the accessibility tree. The id is the
    /// symbol so a sidebar change crossfades the tile instead of
    /// morphing it.
    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(Fonts.sans(TypeSize.dialogTitle).weight(.medium))
            .foregroundStyle(Semantic.mutedForeground)
            .frame(width: ModulePlaceholderMetrics.tile, height: ModulePlaceholderMetrics.tile)
            .background(Circle().fill(Semantic.surface))
            .overlay(Circle().strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
            .id(symbol)
            .transition(Self.iconTransition(reduceMotion: reduceMotion))
            .accessibilityHidden(true)
    }

    /// Each line gets its own id so the copy transition fires per line,
    /// not for the whole group.
    private func copy() -> some View {
        VStack(spacing: Space.x2) {
            Text(Localized.string(placeholder.titleKey))
                .typeRole(.dialogTitle)
                .fontWeight(.semibold)
                .tracking(Tracking.title, at: TypeSize.dialogTitle)
                .foregroundStyle(Semantic.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(Self.lineID(page: placeholder.page, role: "title"))
                .transition(Self.copyTransition(reduceMotion: reduceMotion))
                .accessibilityAddTraits(.isHeader)
            Text(Localized.string(placeholder.bodyKey))
                .typeRole(.body)
                .foregroundStyle(Semantic.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(Self.lineID(page: placeholder.page, role: "body"))
                .transition(Self.copyTransition(reduceMotion: reduceMotion))
            Text(Localized.string("placeholder.notYet"))
                .typeRole(.micro)
                .foregroundStyle(Semantic.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(Self.lineID(page: placeholder.page, role: "notYet"))
                .transition(Self.copyTransition(reduceMotion: reduceMotion))
        }
        // Cap the line width so a long description never runs across the
        // pane; the VStack passes the width down so each Text wraps there.
        .frame(maxWidth: ModulePlaceholderMetrics.textWidth)
        .accessibilityElement(children: .combine)
    }

    private static func lineID(page: MainPage, role: String) -> String {
        "placeholder-\(role)-\(page)"
    }

    /// Title and body rise in while the old copy blurs out, the same
    /// shape `ChromeMotion.transition` already routes through `Reduce
    /// Motion` as a plain opacity.
    static func copyTransition(reduceMotion: Bool) -> AnyTransition {
        ChromeMotion.transition(
            .asymmetric(
                insertion: .modifier(
                    active: CopyChrome(
                        offset: ModulePlaceholderMetrics.copyRise,
                        blur: 0,
                        opacity: 0),
                    identity: CopyChrome(offset: 0, blur: 0, opacity: 1)),
                removal: .modifier(
                    active: CopyChrome(
                        offset: 0,
                        blur: ModulePlaceholderMetrics.copyBlur,
                        opacity: 0),
                    identity: CopyChrome(offset: 0, blur: 0, opacity: 1))),
            reduceMotion: reduceMotion)
    }

    /// The icon crossfades with a short blur pop: scale from 0.9 with a
    /// blur, settling to identity. Symmetric so the two tiles overlap.
    static func iconTransition(reduceMotion: Bool) -> AnyTransition {
        ChromeMotion.transition(
            .modifier(
                active: IconChrome(
                    scale: ModulePlaceholderMetrics.iconEntryScale,
                    blur: ModulePlaceholderMetrics.iconBlur,
                    opacity: 0),
                identity: IconChrome(scale: 1, blur: 0, opacity: 1)),
            reduceMotion: reduceMotion)
    }

    /// The animation that fires when `page` changes. Reduce Motion must
    /// still crossfade, so the value is non-nil: a plain linear `fast`
    /// curve is gentler than the spring and is the reduced-motion path
    /// every other window change uses.
    static func pageAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? MotionCurve.animation(MotionCurve.linear, MotionTime.fast)
            : .springSelect
    }
}

/// Private to the file: nothing outside `copyTransition` builds one.
private struct CopyChrome: ViewModifier {
    var offset: CGFloat
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// Private to the file: nothing outside `iconTransition` builds one.
private struct IconChrome: ViewModifier {
    var scale: CGFloat
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// Measures that have no token in the design system. Kept here, next to
/// the only view that uses them, with a WHY for each.
private enum ModulePlaceholderMetrics {
    /// The round tile behind the icon: a quiet dot, not a card.
    static let tile: CGFloat = Space.x12
    /// 288 pt is 18 rem at the app's 16 px text size: the body wraps
    /// there so lines never run across the full window.
    static let textWidth: CGFloat = 288
    /// The new copy rises one Space step (8 pt) before settling. Larger
    /// would read as a navigation push instead of a quiet swap.
    static let copyRise: CGFloat = Space.x2
    /// Matches `AppsSetupMetrics.blur` (4 pt) so the leaving copy and
    /// the apps-setup messages leave at the same softness.
    static let copyBlur: CGFloat = 4
    /// The icon enters from 90 % of its size with a blur. 0.9 keeps the
    /// crossfade visible without reading as a pop.
    static let iconEntryScale: CGFloat = 0.9
    /// The icon's blur during the crossfade; matches the copy blur so
    /// the two effects feel like one swap, not two.
    static let iconBlur: CGFloat = 4
}
