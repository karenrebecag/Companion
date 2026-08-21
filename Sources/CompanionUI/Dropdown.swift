import SwiftUI

public enum OpenMenu: Equatable, Sendable {
    case choice, history, settingsPick(String)
}

public struct DropdownItem {
    public var title: String
    public var subtitle: String? = nil
    public var symbol: String? = nil
    public var rainbow = false
    public var swatch: Color? = nil

    public init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        rainbow: Bool = false,
        swatch: Color? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.rainbow = rainbow
        self.swatch = swatch
    }
}

/// Hosts the one open panel. Preference-key portal draws it on the root so
/// ScrollView clipping cannot eat it — the prototype's reason for not using Menu.
@Observable
@MainActor
public final class DropdownHost {
    public var session = DropdownSession(count: 0)
    public var items: [DropdownItem] = []
    public var selectedTitle = ""
    public var menu: OpenMenu?
    var onChoose: ((Int) -> Void)?

    public init() {}

    /// Choice/history live on the root. Settings picks must not cover the window
    /// under the sheet — leftover isOpen after dismiss would freeze clicks.
    public var blocksRoot: Bool {
        session.isOpen && (menu == .choice || menu == .history)
    }

    public func toggle(_ menu: OpenMenu) {
        if self.menu == menu, session.isOpen {
            dismiss()
            return
        }
        self.menu = menu
        items = []
        onChoose = nil
        session = DropdownSession(count: 1)
        session.handle(.toggle)
    }

    public func present(
        _ menu: OpenMenu,
        items: [DropdownItem],
        selectedTitle: String,
        onChoose: @escaping (Int) -> Void
    ) {
        if self.menu == menu, session.isOpen {
            dismiss()
            return
        }
        self.menu = menu
        self.items = items
        self.selectedTitle = selectedTitle
        self.onChoose = onChoose
        session = DropdownSession(count: items.count)
        session.handle(.toggle)
        if let i = items.firstIndex(where: { $0.title == selectedTitle }) {
            session.highlight = i
        }
    }

    public func dismiss() {
        session.handle(.escape)
        menu = nil
    }

    func pickHighlight() {
        session.handle(.choose)
        if let i = session.lastChosen {
            onChoose?(i)
        }
        menu = nil
    }

    func pick(_ index: Int) {
        session.highlight = index
        pickHighlight()
    }
}

/// Disco arcoiris del Predeterminado: un tinte solo no es "el de siempre".
struct RainbowDot: View {
    var size: CGFloat = IconGlyph.defaultSize

    var body: some View {
        Circle()
            .fill(AngularGradient(
                colors: [
                    Accent.pink.color,
                    Accent.orange.color,
                    Accent.yellow.color,
                    Accent.green.color,
                    Accent.blue.color,
                    Accent.purple.color,
                    Accent.pink.color,
                ],
                center: .center
            ))
            .frame(width: size, height: size)
    }
}

struct DropdownAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?,
                       nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct DropdownChrome: ViewModifier {
    var blur: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .top)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var dropdown: AnyTransition {
        .modifier(
            active: DropdownChrome(blur: 12, scale: 0.94, opacity: 0),
            identity: DropdownChrome(blur: 0, scale: 1, opacity: 1))
    }
}

struct DropdownPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            content
        }
        .padding(Space.x2)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Semantic.surfaceOverlay)
                .elevation(.popover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Semantic.border, lineWidth: Stroke.hairline)
        )
        .transition(.dropdown)
    }
}

struct DropdownRow: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var selected = false
    var highlighted = false
    var index = 0
    var swatch: Color? = nil
    var rainbow = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.x2) {
                if rainbow {
                    RainbowDot()
                } else if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: IconGlyph.defaultSize, height: IconGlyph.defaultSize)
                        .overlay(Circle().stroke(Semantic.border, lineWidth: Stroke.hairline))
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .frame(width: Space.x3 + Space.x1)
                }
                VStack(alignment: .leading, spacing: Space.x1 / 2) {
                    Text(title)
                        .font(.uiLabel)
                        .foregroundStyle(Semantic.foreground)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.uiMicro)
                            .foregroundStyle(Semantic.mutedForeground)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 240, alignment: .leading)
                Spacer(minLength: Space.x3)
                if selected {
                    IconGlyph(icon: .check, size: 12)
                        .foregroundStyle(Semantic.foreground)
                }
            }
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(hovering || highlighted ? Semantic.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .animation(.easeOut(duration: MotionTime.fast), value: hovering)
        .staggered(index)
    }
}

extension View {
    func dropdownAnchor(_ active: Bool) -> some View {
        anchorPreference(
            key: DropdownAnchorKey.self, value: .bounds
        ) { active ? $0 : nil }
    }

    func dropdownPortal(host: DropdownHost) -> some View {
        overlayPreferenceValue(DropdownAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if host.session.isOpen, let anchor {
                    let rect = proxy[anchor]
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                        DropdownPanel {
                            ScrollView {
                                VStack(alignment: .leading, spacing: Space.x1) {
                                    ForEach(Array(host.items.enumerated()), id: \.offset) { i, item in
                                        DropdownRow(
                                            title: item.title,
                                            subtitle: item.subtitle,
                                            symbol: item.symbol,
                                            selected: item.title == host.selectedTitle,
                                            highlighted: i == host.session.highlight,
                                            index: i,
                                            swatch: item.swatch,
                                            rainbow: item.rainbow
                                        ) {
                                            withAnimation(.springSheet) { host.pick(i) }
                                        }
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .frame(maxHeight: Space.x1 * 65)
                        }
                        .offset(
                            x: -(proxy.size.width - rect.maxX),
                            y: rect.maxY + Space.x1)
                        .focusable()
                        .onKeyPress(.escape) {
                            withAnimation(.springSheet) { host.dismiss() }
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            host.session.handle(.arrowUp)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            host.session.handle(.arrowDown)
                            return .handled
                        }
                        .onKeyPress(.return) {
                            withAnimation(.springSheet) { host.pickHighlight() }
                            return .handled
                        }
                    }
                }
            }
            .allowsHitTesting(anchor != nil)
        }
    }
}

struct SettingsItem<T: Hashable>: View {
    let title: String
    let value: String
    let options: [(T, String)]
    var rainbow: ((T) -> Bool)? = nil
    var swatch: ((T) -> Color?)? = nil
    let onChange: (T) -> Void

    @Environment(DropdownHost.self) private var host

    var body: some View {
        HStack {
            Text(title)
                .font(.uiLabel)
                .foregroundStyle(Semantic.foreground)
            Spacer()
            Button {
                withAnimation(.springSheet) {
                    host.present(
                        .settingsPick(title),
                        items: options.map { opt in
                            DropdownItem(
                                title: opt.1,
                                rainbow: rainbow?(opt.0) ?? false,
                                swatch: swatch?(opt.0))
                        },
                        selectedTitle: value
                    ) { index in
                        onChange(options[index].0)
                    }
                }
            } label: {
                HStack(spacing: Space.x2) {
                    Text(value)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.accentText)
                    Image(systemName: "chevron.down")
                        .font(.uiMicro)
                        .foregroundStyle(Semantic.mutedForeground)
                }
                .padding(.horizontal, Space.x3)
                .padding(.vertical, Space.x2)
                .background(Semantic.muted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .dropdownAnchor(
                host.menu == .settingsPick(title) && host.session.isOpen)
        }
    }
}
