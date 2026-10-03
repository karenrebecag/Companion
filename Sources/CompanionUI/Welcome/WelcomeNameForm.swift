import SwiftUI

/// The name page's form width: what is left of the window after the margin,
/// never past the cap, and 0 for anything that is not a usable length.
enum NameFormLayout {
    static func width(available: CGFloat) -> CGFloat {
        guard !available.isNaN else { return 0 }
        return min(Container.nameForm, max(0, available))
    }
}

/// How the name field looks for the state it is in.
struct NameFieldLook: Equatable {
    enum Fill: Equatable { case rest, hover, focused }

    /// The quiet border at rest; ink on focus so the state clears 3:1
    /// non-text contrast (the 10 % halo alone does not).
    enum Border: Equatable { case quiet, ink }

    let fill: Fill
    let halo: CGFloat
    let border: Border

    static func resolve(focused: Bool, hovering: Bool) -> NameFieldLook {
        if focused { return NameFieldLook(fill: .focused, halo: Stroke.ring, border: .ink) }
        return NameFieldLook(fill: hovering ? .hover : .rest, halo: 0, border: .quiet)
    }

    static func animation(reduceMotion: Bool) -> Animation? {
        ChromeMotion.animation(.expoOut(MotionTime.base), reduceMotion: reduceMotion)
    }
}

/// Where a screen's measurable pieces sit, in window space. Inert in
/// production (nothing reads it); the layout tests do.
enum WelcomeFrameRole: Hashable { case nameField, heading, continueButton }

struct WelcomeFrames: PreferenceKey {
    static let defaultValue: [WelcomeFrameRole: CGRect] = [:]
    static func reduce(value: inout [WelcomeFrameRole: CGRect], nextValue: () -> [WelcomeFrameRole: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func reportsFrame(_ role: WelcomeFrameRole) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: WelcomeFrames.self, value: [role: proxy.frame(in: .global)])
        })
    }
}

/// The welcome's "what should I call you" page: title, one line, and the
/// tall field. The Continue pill stays the container's.
struct WelcomeNameForm: View {
    @Binding var name: String

    var body: some View {
        VStack(spacing: Space.x6) {
            VStack(spacing: Space.x3) {
                Text(Localized.string("welcome.hello.title"))
                    .font(GeistFont.uiTitle.weight(.semibold))
                    .tracking(Tracking.title, at: TypeSize.bannerTitle)
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("welcome.hello.body"))
                    .font(GeistFont.uiSubtitle)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .reportsFrame(.heading)
            WelcomeNameField(placeholder: Localized.string("welcome.hello.name"), text: $name)
                // The window's width, not the column's: Incredible's min(340, 100vw - 64).
                .containerRelativeFrame(.horizontal) { window, _ in
                    NameFormLayout.width(available: window - Container.nameFormMargin)
                }
                .reportsFrame(.nameField)
        }
    }
}

struct WelcomeNameField: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var focused: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let look = NameFieldLook.resolve(focused: focused, hovering: hovering)
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Fonts.geist(TypeSize.heroBody).weight(.medium))
            .tracking(Tracking.input, at: TypeSize.heroBody)
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, ControlMetrics.nameFieldInset)
            .frame(maxWidth: .infinity)
            .frame(height: ControlMetrics.nameFieldHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(fill(look.fill)))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(look.border == .ink ? Semantic.foreground : Semantic.border,
                                  lineWidth: Stroke.hairline))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .inset(by: -look.halo / 2)
                    .stroke(Semantic.fieldHalo, lineWidth: look.halo))
            .focused($focused)
            .onHover { hovering = $0 }
            .animation(NameFieldLook.animation(reduceMotion: reduceMotion), value: look)
    }

    private func fill(_ fill: NameFieldLook.Fill) -> Color {
        switch fill {
        case .rest: Semantic.fieldWash
        case .hover: Semantic.fieldWashHover
        case .focused: Semantic.surface
        }
    }
}
