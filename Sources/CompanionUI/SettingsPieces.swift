import CompanionCore
import SwiftUI

/// The pieces every Settings page is built from (Wave 16g): white cards of
/// rows on a sunken sheet, a control at the end of each row, and the pill
/// buttons. One vocabulary, so a page cannot drift into its own look.

/// A group of rows with a hairline between them; the label sits above.
struct SettingsCard<Content: View>: View {
    var label: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if let label {
                Text(label)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.mutedForeground)
                    .padding(.horizontal, Space.x1)
            }
            VStack(alignment: .leading, spacing: Space.none) {
                Group(subviews: content()) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(Semantic.border)
                                .frame(height: Stroke.hairline)
                                .padding(.horizontal, Space.x4)
                        }
                        row
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.card).fill(Semantic.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline))
        }
    }
}

/// Title, grey subtitle, and whatever control ends the row. `key` is the
/// inventory key, so a search result can light the row it jumped to.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var key: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.settingsHighlight) private var highlight

    var body: some View {
        HStack(alignment: .center, spacing: Space.x4) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.x3)
            trailing()
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
        .background(key != nil && key == highlight ? Semantic.hover : Color.clear)
        .animation(.expoOut(MotionTime.panel), value: highlight)
    }
}

/// A row with nothing at the end.
extension SettingsRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, key: String? = nil) {
        self.init(title: title, subtitle: subtitle, key: key) { EmptyView() }
    }
}

/// 16l: Incredible's Button variants. `neutral` is the ghost (5 % wash),
/// `primary` the black solid, `destructive` the red ghost.
enum SettingsPillKind {
    /// Grey "Cambiar": the everyday action.
    case neutral
    /// Black "+ Añadir": the one thing a page is for.
    case primary
    /// Red: removes something that does not come back.
    case destructive
}

struct SettingsPill: View {
    let title: String
    var kind: SettingsPillKind = .neutral
    var symbol: String? = nil
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.x1_5) {
                if let symbol {
                    Image(systemName: symbol).font(Fonts.sans(fontSize).weight(.semibold))
                }
                Text(title).font(Fonts.sans(fontSize).weight(.semibold))
            }
            .lineLimit(1)
            .padding(.horizontal, kind == .primary ? ButtonMetrics.padding : ButtonMetrics.ghostPadding)
            .frame(height: ButtonMetrics.height)
            .foregroundStyle(ink)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : StateAlpha.disabled)
        .scaleEffect(grows ? ButtonMetrics.hoverScale : 1)
        .onHover { hovering = $0 }
        .animation(MotionCurve.animation(MotionCurve.settle, ButtonMetrics.duration), value: hovering)
    }

    private var fontSize: CGFloat { kind == .primary ? TypeSize.rowTitle : TypeSize.body }

    private var grows: Bool { enabled && hovering && kind != .destructive }

    private var ink: Color {
        switch kind {
        case .neutral: Semantic.foreground
        case .primary: Semantic.primaryForeground
        case .destructive: Semantic.dangerHover
        }
    }

    private var fill: Color {
        switch kind {
        case .neutral: Semantic.wash
        case .primary: Semantic.primary
        case .destructive: hovering ? Semantic.dangerWashHover : Semantic.dangerWash
        }
    }
}

/// Incredible's drawn switch (16l-2), not the native Toggle.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        IncredibleSwitch(label, isOn: $isOn)
    }
}

/// A key drawn as a key, for rows that name one.
struct SettingsKeycap: View {
    let text: String

    var body: some View {
        Keycap(text, size: .small)
    }
}

/// A list page with nothing in it yet: a symbol, one line, and the way out.
struct SettingsEmptyState<Action: View>: View {
    let symbol: String
    let text: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: Space.x3) {
            Image(systemName: symbol)
                .font(Fonts.sans(TypeSize.display))
                .foregroundStyle(Semantic.mutedForeground)
                .accessibilityHidden(true)
            Text(text)
                .font(.uiBody)
                .foregroundStyle(Semantic.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.x8)
    }
}

/// The page title and its one-line reason, above the cards.
struct SettingsPageHeader: View {
    let title: String
    var blurb: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title)
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
            if let blurb {
                Text(blurb)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The inventory key a search just jumped to; its row lights briefly.
    var settingsHighlight: String? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}
