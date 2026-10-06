import SwiftUI

// Wave 16l: the measured sizes of Incredible's small controls and the views
// that draw them. Values from docs/research/incredible-componentes.md.

package enum ButtonMetrics {
    package static let height: CGFloat = 40
    package static let padding: CGFloat = Space.x5
    package static let ghostPadding: CGFloat = Space.x4
    package static let heroPaddingX: CGFloat = Space.x6
    package static let heroPaddingY: CGFloat = Space.x3
    package static let hoverScale: CGFloat = 1.03
    package static let welcomeHeight: CGFloat = 46
    package static let welcomePadding: CGFloat = 30
    /// Hover and state changes ride Incredible's settle curve.
    package static let duration = 0.2
}

package struct IconButtonSize: Sendable, Equatable {
    package let side: CGFloat
    /// The icon's box, as Incredible measures it.
    package let glyph: CGFloat
    /// A close button always sits on its wash; the others only on hover.
    package var filled = false
    /// Window icons are SVG-sized boxes drawn with SF Symbols, so they shrink
    /// by `opticalScale`; the island's tool icons are measured at their
    /// drawn size (18 in a 31 button) and do not.
    package var optical = true

    /// The point size the glyph is drawn at.
    package var point: CGFloat { optical ? glyph * Self.opticalScale : glyph }

    package static let small = IconButtonSize(side: 28, glyph: 16)
    package static let medium = IconButtonSize(side: 34, glyph: 18)
    /// `ui-close`: a 32 circle on the 5 % wash.
    package static let close = IconButtonSize(side: 32, glyph: 14, filled: true)
    /// The island's tool buttons: icon 18 as measured, in the field's tool
    /// slot. Their CSS says 31 wide but the capture measured 30 (16n), and
    /// where the two disagree the capture wins — a 31 button would overflow
    /// the slot it sits in.
    package static let island = IconButtonSize(side: IslandFieldMetrics.tool, glyph: 18, optical: false)
    /// The island's close: the 22 slot every island mark sits in.
    package static let islandClose = IconButtonSize(side: IslandInk.slotSide, glyph: 14, filled: true)
    /// `ci-att-card`'s remove: a 24 circle over the card (16m-3).
    package static let attachmentRemove = IconButtonSize(side: 24, glyph: 14, filled: true)

    /// An SF Symbol fills more of its point size than an SVG icon fills its
    /// box; at 80 % the two read the same.
    package static let opticalScale: CGFloat = 0.8
}

/// Which surface an icon button sits on. The island is black in both
/// appearances, and a close over a thumbnail needs its own dark disc and rim
/// to stay visible on any picture.
package enum IconButtonTone: Sendable {
    case window, island, onMedia
}

package struct KeycapSize: Sendable, Equatable {
    package let radius: CGFloat
    package let paddingX: CGFloat
    package let paddingY: CGFloat
    package let fontSize: CGFloat
    /// A square face of this side; nil hugs the label.
    package var side: CGFloat? = nil
    package var mono = false

    package static let small = KeycapSize(radius: 4, paddingX: 6, paddingY: 2, fontSize: 10)
    package static let large = KeycapSize(radius: 12, paddingX: 16, paddingY: 8, fontSize: 16)
    /// The welcome's fn key: the large cap as a square, in mono.
    package static let hero = KeycapSize(
        radius: large.radius, paddingX: Space.none, paddingY: Space.none,
        fontSize: TypeSize.title, side: 72, mono: true)

    /// Incredible's small cap has a hard 1 px drop and no blur: that is a lip,
    /// not an elevation. The large one lifts off the page as well.
    package var elevation: Elevation { self == .small ? .rest : .hover }
    package var lip: CGFloat { self == .small ? Stroke.hairline : Stroke.medium }
    package static let lipAlpha = 0.08
}

/// Round icon-only button: secondary grey, a wash and primary ink on hover.
/// The one icon button for every surface (16p-2); the tone picks the ink.
package struct IconButton: View {
    let symbol: String
    let label: String
    var size: IconButtonSize = .small
    var tone: IconButtonTone = .window
    var danger = false
    /// `chip` corners instead of a circle.
    var chip = false
    /// Lit while the thing it opens is open.
    var active = false
    /// Gives under the finger like the window's other controls.
    var pressable = false
    /// The attachment remove reads this: focus only updates a binding that
    /// sits on the button itself.
    var onFocus: ((Bool) -> Void)? = nil
    /// False draws nothing but keeps the button hittable, focusable and in
    /// the accessibility tree: only the drawing carries the opacity.
    var revealed = true
    /// For renders only: Tab reaches a SwiftUI button only when the Mac has
    /// full keyboard access on, so a test cannot rely on it to focus one.
    /// This makes it focusable and takes the focus, which exercises the
    /// focus-to-reveal path but not Tab reachability.
    var focusOnAppear = false
    /// A confirmed state's own ink (copied: success), over the tone's.
    var tint: Color?
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    package init(_ symbol: String, label: String, size: IconButtonSize = .small,
                tone: IconButtonTone = .window, danger: Bool = false, chip: Bool = false,
                active: Bool = false, pressable: Bool = false,
                onFocus: ((Bool) -> Void)? = nil, revealed: Bool = true,
                focusOnAppear: Bool = false, tint: Color? = nil,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.size = size
        self.tone = tone
        self.danger = danger
        self.chip = chip
        self.active = active
        self.pressable = pressable
        self.onFocus = onFocus
        self.revealed = revealed
        self.focusOnAppear = focusOnAppear
        self.tint = tint
        self.action = action
    }

    package var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(glyphFont)
                .frame(width: size.side, height: size.side)
                .foregroundStyle(ink)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(rim, lineWidth: Stroke.hairline))
                .opacity(revealed ? 1 : 0)
                // After the opacity, so the unseen disc still takes the click.
                .contentShape(shape)
        }
        .modifier(IconButtonPress(pressable: pressable))
        .modifier(IconButtonFocus(track: onFocus != nil, force: focusOnAppear, focused: $focused))
        .onChange(of: focused) { _, value in onFocus?(value) }
        .onAppear { if focusOnAppear, onFocus != nil { focused = true } }
        .onHover { hovering = $0 }
        .animation(MotionCurve.animation(MotionCurve.standard, MotionTime.fast), value: hovering)
        .modifier(IconButtonHint(label: label, island: tone != .window))
        .accessibilityLabel(label)
    }

    /// SF Symbols take their weight reliably only from the system font, so
    /// the glyph never rides Geist even on the island.
    private var glyphFont: Font { Fonts.symbol(size.point, weight: .medium) }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: chip ? Radius.chip : size.side / 2)
    }

    private var lit: Bool { hovering || active }

    private var ink: Color {
        if let tint { return tint }
        switch tone {
        case .window:
            guard lit else { return Semantic.mutedForeground }
            return danger ? Semantic.danger : Semantic.foreground
        case .island:
            return lit ? IslandInk.text : IslandInk.secondary
        case .onMedia:
            return Self.onMediaInk(hovering: hovering)
        }
    }

    private var fill: Color {
        switch tone {
        case .window:
            if size.filled { return lit ? Semantic.hover : Semantic.wash }
            return lit ? Semantic.hoverSubtle : Color.clear
        case .island:
            // Arc's plain icon button: it fills only under the pointer.
            if active || hovering { return IslandInk.chipPressed }
            return size.filled ? IslandInk.chip : Color.clear
        case .onMedia:
            return Self.onMediaFill(hovering: hovering)
        }
    }

    /// The pointer on the disc itself darkens it: black 85 % under pure white.
    /// FeedbackModal's close also uses this tone and takes the same look.
    static func onMediaFill(hovering: Bool) -> Color {
        hovering
            ? IslandAttachMetrics.removeHoverFill.color.opacity(IslandAttachMetrics.removeHoverFillAlpha)
            : IslandAttachMetrics.removeFill.color.opacity(IslandAttachMetrics.removeFillAlpha)
    }

    static func onMediaInk(hovering: Bool) -> Color {
        Neutral.white.color.opacity(hovering ? 1 : IslandAttachMetrics.removeInkAlpha)
    }

    /// Only the disc over a picture draws a rim: on a photo its edge is the
    /// one thing that separates it from what is under it.
    private var rim: Color {
        tone == .onMedia ? Neutral.white.color.opacity(IslandAttachMetrics.removeBorder) : .clear
    }
}

private struct IconButtonPress: ViewModifier {
    let pressable: Bool

    func body(content: Content) -> some View {
        if pressable { content.buttonStyle(PressableStyle()) } else { content.buttonStyle(.plain) }
    }
}

/// Focus applied only when a caller asked to hear it, so the other icon
/// buttons keep the focus they already had.
private struct IconButtonFocus: ViewModifier {
    let track: Bool
    let force: Bool
    var focused: FocusState<Bool>.Binding

    @ViewBuilder
    func body(content: Content) -> some View {
        if track && force {
            content.focusable().focused(focused)
        } else if track {
            content.focused(focused)
        } else {
            content
        }
    }
}

/// The island never shows the system tooltip: it has its own pill.
private struct IconButtonHint: ViewModifier {
    let label: String
    let island: Bool

    func body(content: Content) -> some View {
        if island { content.islandTooltip(label) } else { content.help(label) }
    }
}

/// A key drawn as a key: the small one sits inside rows, the large one in
/// the welcome and shortcut screens.
package struct Keycap: View {
    let text: String
    var size: KeycapSize = .small

    package init(_ text: String, size: KeycapSize = .small) {
        self.text = text
        self.size = size
    }

    package var body: some View {
        Text(verbatim: text)
            .font(size.mono ? Fonts.mono(size.fontSize, bold: true) : Fonts.sans(size.fontSize).weight(.medium))
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, size.paddingX)
            .padding(.vertical, size.paddingY)
            .frame(width: size.side, height: size.side)
            .background(RoundedRectangle(cornerRadius: size.radius).fill(Semantic.surface))
            .overlay {
                if size != .small {
                    RoundedRectangle(cornerRadius: size.radius)
                        .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline)
                }
            }
            .overlay(alignment: .bottom) {
                // The inset bottom edge: a key has a lip.
                RoundedRectangle(cornerRadius: size.radius)
                    .strokeBorder(Neutral.black.color.opacity(KeycapSize.lipAlpha), lineWidth: size.lip)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size.lip)
                    }
            }
            .elevation(size.elevation)
    }
}
