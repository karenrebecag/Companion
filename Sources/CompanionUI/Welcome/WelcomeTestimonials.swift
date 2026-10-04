import CompanionCore
import SwiftUI

// WIN-4: Incredible 0.2.36 shows a testimonials carousel beside the signup
// page. Behaviour: createFirstRunIO-Dv00aAyF.js @29900-31500 and
// firstRun-CdIWn2zA.js @1211631 (interval aoe = 1e4). Layout:
// styles-CTdsYdwA.css @16428-22380. The quotes are Companion placeholders.

/// The carousel's rules, apart from the view so they can be checked.
nonisolated package enum TestimonialCarousel {
    package static let count = 4
    package static let interval: Duration = .seconds(10)
    /// styles-CTdsYdwA.css @container max-width:719px hides the aside.
    package static let asideMinWidth: CGFloat = 720
    /// The signup grid is 9fr / 11fr.
    static let formShare: CGFloat = 9.0 / 20.0
    /// A leaving slide is quick; the entering one waits for it.
    static let leaveDuration = 0.22
    static let enterDelay = 0.1
    static let revealDelay = 0.08
    static let revealDuration = 0.5
    static let slideShift: CGFloat = 4
    static let slideBlur: CGFloat = 4
    static let pressScale: CGFloat = 0.96
    static let quoteLeading: CGFloat = 1.4
    static let avatar: CGFloat = 48
    static let dotHit = CGSize(width: 32, height: 24)
    static let dotBar = CGSize(width: 20, height: 4)
    static let restAlpha = 0.16
    static let hoverAlpha = 0.4
    static let ringAlpha = 0.08
    /// shadow-card's tight first layer (0 1 2 #00000008); the second is Elevation.hover.
    static let tightShadowAlpha = 0.03
    /// The card's frosted tint over the material, so text keeps contrast on any wallpaper.
    static let cardTintAlpha = 0.42
    /// The card's 1 px outline, fainter than the aside ring.
    static let cardRingAlpha = 0.05

    /// The slide after `index`; the last wraps to the first.
    package static func next(after index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    /// Incredible pauses on hover, on focus inside, while the window is
    /// hidden, and never runs under Reduce Motion.
    package static func advances(hovering: Bool, focused: Bool, active: Bool, reduceMotion: Bool) -> Bool {
        !hovering && !focused && active && !reduceMotion
    }

    /// The flag is the gate that keeps placeholder quotes from ever shipping
    /// visible; the step and width are Incredible's layout rules.
    package static func showsAside(step: WelcomeStep, width: CGFloat, enabled: Bool) -> Bool {
        enabled && step == .keys && width >= asideMinWidth
    }

    /// Content flag in Localizable.strings, flipped only with real quotes.
    @MainActor package static var enabled: Bool {
        Localized.string("welcome.testimonials.enabled") == "1"
    }
}

/// Which slide shows, plus a counter so re-choosing the current dot still
/// restarts the 10 s.
nonisolated struct CarouselState: Hashable {
    private(set) var selected = 0
    private(set) var restart = 0

    mutating func select(_ index: Int, count: Int) {
        guard (0..<count).contains(index) else { return }
        selected = index
        restart += 1
    }

    mutating func advance(count: Int) {
        selected = TestimonialCarousel.next(after: selected, count: count)
    }
}

package struct WelcomeTestimonial: Identifiable, Equatable {
    package let id: Int
    let quote: String
    let ending: String
    let name: String
    let role: String
    let initials: String

    /// Placeholders from Localizable.strings; Karen swaps the text there.
    @MainActor static var all: [WelcomeTestimonial] {
        (1...TestimonialCarousel.count).map { n in
            let name = Localized.string("welcome.testimonial.\(n).name")
            return WelcomeTestimonial(
                id: n,
                quote: Localized.string("welcome.testimonial.\(n).quote"),
                ending: Localized.string("welcome.testimonial.\(n).ending"),
                name: name,
                role: Localized.string("welcome.testimonial.\(n).role"),
                initials: initials(of: name))
        }
    }

    /// The portrait placeholder: first letters of the first two words.
    static func initials(of name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).prefix(2)
            .compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

/// The right-hand column of the signup page: a soft surface with the
/// carousel card at its foot.
struct WelcomeTestimonialsAside: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        // .fr-signup-aside centres the card vertically (styles-CTdsYdwA.css @17794).
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(LinearGradient(
                    colors: [Semantic.surfaceSecondary, Semantic.surface],
                    startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Semantic.foreground, lineWidth: Stroke.hairline)
                .opacity(TestimonialCarousel.ringAlpha)
            WelcomeTestimonialsCarousel()
                .frame(maxWidth: .infinity)
                .padding(Space.x8)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : TestimonialCarousel.slideShift)
        .onAppear {
            guard !reduceMotion else { revealed = true; return }
            // fr-reveal: .5 s after an 80 ms delay
            withAnimation(MotionCurve.animation(MotionCurve.glide, TestimonialCarousel.revealDuration)
                .delay(TestimonialCarousel.revealDelay)) { revealed = true }
        }
    }
}

struct WelcomeTestimonialsCarousel: View {
    private struct Tick: Hashable {
        let state: CarouselState
        let running: Bool
    }

    // State so a parent re-render does not rebuild the localized slides.
    @State private var slides = WelcomeTestimonial.all
    @State private var state = CarouselState()
    @State private var hovering = false
    @FocusState private var focusedDot: Int?
    @Environment(\.controlActiveState) private var controlActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var running: Bool {
        TestimonialCarousel.advances(
            hovering: hovering, focused: focusedDot != nil,
            active: controlActive != .inactive, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: Space.x6) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                    TestimonialSlide(slide: slide, active: index == state.selected, animated: !reduceMotion, selected: state.selected)
                }
            }
            HStack(spacing: Space.x1) {
                ForEach(slides.indices, id: \.self) { index in
                    TestimonialDot(index: index, selected: index == state.selected) {
                        state.select(index, count: slides.count)
                    }
                    .focused($focusedDot, equals: index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Space.x7)
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.card)
            shape.fill(.ultraThinMaterial)
            shape.fill(Semantic.surface).opacity(TestimonialCarousel.cardTintAlpha)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(Color.black, lineWidth: Stroke.hairline).opacity(TestimonialCarousel.cardRingAlpha))
        // shadow-card: 0 1 2 #00000008, 0 4 10 -2 #0000000a
        .shadow(color: .black.opacity(TestimonialCarousel.tightShadowAlpha), radius: 1, y: 1)
        .elevation(.hover)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localized.string("welcome.testimonials.label"))
        .task(id: Tick(state: state, running: running)) {
            guard running else { return }
            do { try await Task.sleep(for: TestimonialCarousel.interval) } catch { return }
            state.advance(count: slides.count)
        }
    }
}

private struct TestimonialSlide: View {
    let slide: WelcomeTestimonial
    let active: Bool
    let animated: Bool
    /// Only here so the animation modifiers have a value to watch.
    let selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x7) {
            avatar
            quote
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(verbatim: slide.name)
                    .font(Fonts.geist(TypeSize.rowTitle).weight(.medium))
                    .foregroundStyle(Semantic.foreground)
                Text(verbatim: slide.role)
                    .font(Fonts.geist(TypeSize.caption))
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The shift is innermost so it takes the glide curve while the fade
        // and blur outside it take ease-standard.
        .offset(y: active ? 0 : -TestimonialCarousel.slideShift)
        .animation(animated ? curve(MotionCurve.glide) : nil, value: selected)
        .opacity(active ? 1 : 0)
        .blur(radius: active ? 0 : TestimonialCarousel.slideBlur)
        .animation(animated ? curve(MotionCurve.standard) : nil, value: selected)
        .allowsHitTesting(active)
        .accessibilityHidden(!active)
    }

    private func curve(_ curve: [Double]) -> Animation {
        active
            ? MotionCurve.animation(curve, MotionTime.land).delay(TestimonialCarousel.enterDelay)
            : MotionCurve.animation(curve, TestimonialCarousel.leaveDuration)
    }

    private var avatar: some View {
        Circle()
            .fill(Semantic.muted)
            .overlay(Circle().strokeBorder(Semantic.foreground, lineWidth: Stroke.hairline)
                .opacity(TestimonialCarousel.ringAlpha))
            .overlay(Text(verbatim: slide.initials)
                .font(Fonts.geist(TypeSize.rowTitle).weight(.medium))
                .foregroundStyle(Semantic.mutedForeground))
            .frame(width: TestimonialCarousel.avatar, height: TestimonialCarousel.avatar)
            .accessibilityHidden(true)
    }

    private var quote: some View {
        let size = TypeScale.apply(TypeSize.bannerTitle)
        let font = Fonts.geist(TypeSize.bannerTitle).weight(.medium)
        let em = Tracking.title * size
        return (Text(verbatim: "\u{201C}" + slide.quote + " ").font(font).tracking(em)
            .foregroundColor(Semantic.foreground)
            + Text(verbatim: slide.ending + "\u{201D}").font(font).tracking(em)
            .foregroundColor(Semantic.mutedForeground))
            .lineSpacing(Leading.spacing(TestimonialCarousel.quoteLeading, at: TypeSize.bannerTitle, face: .geist))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TestimonialDot: View {
    let index: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(Semantic.foreground)
                .opacity(selected ? 1 : hovering ? TestimonialCarousel.hoverAlpha : TestimonialCarousel.restAlpha)
                .frame(width: TestimonialCarousel.dotBar.width, height: TestimonialCarousel.dotBar.height)
                .frame(width: TestimonialCarousel.dotHit.width, height: TestimonialCarousel.dotHit.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(DotPressStyle())
        .onHover { hovering = $0 }
        .animation(.expoOut(MotionTime.fast), value: hovering)
        .animation(.expoOut(MotionTime.fast), value: selected)
        .accessibilityLabel(String(format: Localized.string("welcome.testimonials.dot"), index + 1))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DotPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? TestimonialCarousel.pressScale : 1)
            .animation(.springPress, value: configuration.isPressed)
    }
}
