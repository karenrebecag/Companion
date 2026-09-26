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

    /// Choice is a header panel: the root hit-sink covers the rest of the
    /// window. History is a centered overlay; its blur is the sink.
    public var blocksRoot: Bool {
        session.isOpen && menu == .choice
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
    /// 16l-2: Incredible's menu fades and settles from 0.97, no blur.
    static var dropdown: AnyTransition {
        .modifier(
            active: DropdownChrome(blur: 0, scale: MenuMetrics.enterScale, opacity: 0),
            identity: DropdownChrome(blur: 0, scale: 1, opacity: 1))
        .animation(MotionCurve.animation(MotionCurve.standard, MenuMetrics.duration))
    }
}

struct DropdownPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MenuMetrics.gap) {
            content
        }
        .padding(MenuMetrics.padding)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: MenuMetrics.radius)
                .fill(Semantic.surfaceOverlay)
                .elevation(.sheet)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MenuMetrics.radius)
                .stroke(Semantic.popupBorder, lineWidth: Stroke.hairline)
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
    var titleMaxWidth: CGFloat = 240
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuMetrics.itemGap) {
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
                        .font(Fonts.sans(TypeSize.body).weight(.medium))
                        .foregroundStyle(Semantic.foreground)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.uiMicro)
                            .foregroundStyle(Semantic.mutedForeground)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: titleMaxWidth, alignment: .leading)
                Spacer(minLength: Space.x3)
                if selected {
                    IconGlyph(icon: .check, size: 12)
                        .foregroundStyle(Semantic.foreground)
                }
            }
            .padding(.horizontal, MenuMetrics.itemPaddingX)
            .padding(.vertical, MenuMetrics.itemPaddingY)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: MenuMetrics.itemRadius))
            .background(
                RoundedRectangle(cornerRadius: MenuMetrics.itemRadius)
                    .fill(hovering || highlighted ? Semantic.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .animation(.expoOut(MotionTime.fast), value: hovering)
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
                                VStack(alignment: .leading, spacing: MenuMetrics.gap) {
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
    /// Which menu this is. Rows show their own title and leave this one
    /// blank, so two blank titles on a page would share an anchor (16g).
    var id: String? = nil
    let onChange: (T) -> Void

    @Environment(DropdownHost.self) private var host

    var menu: OpenMenu { .settingsPick(id ?? title) }

    var body: some View {
        HStack {
            if !title.isEmpty {
                Text(title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Spacer()
            }
            Button {
                withAnimation(.springSheet) {
                    host.present(
                        menu,
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
                // 16l-2: Incredible's select trigger.
                HStack(spacing: SelectMetrics.gap) {
                    Text(value)
                        .font(Fonts.sans(TypeSize.body).weight(.medium))
                        .foregroundStyle(Semantic.foreground)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.uiMicro)
                        .foregroundStyle(Semantic.faintForeground)
                }
                .padding(.horizontal, SelectMetrics.paddingX)
                .frame(height: SelectMetrics.height)
                .background(Semantic.wash)
                .clipShape(RoundedRectangle(cornerRadius: SelectMetrics.radius))
                .contentShape(RoundedRectangle(cornerRadius: SelectMetrics.radius))
            }
            .buttonStyle(.plain)
            .dropdownAnchor(
                host.menu == menu && host.session.isOpen)
        }
    }
}
