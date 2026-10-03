import CompanionCore
import SwiftUI

// WIN-5 of the Incredible audit: Settings is a floating panel, not a modal.
// Incredible's `.fr-dev`: 336 px, bottom-right, radius 14, rgb(22 24 30 / .94),
// in three states (normal, docked, folded into a pill).

package enum SettingsPanelMetrics {
    package static let width: CGFloat = 336
    package static let inset: CGFloat = Space.x4
    package static let radius: CGFloat = Radius.control
    package static let paddingX: CGFloat = Space.x3_5
    package static let paddingY: CGFloat = Space.x3
    package static let maxHeight: CGFloat = 560
    package static let pillHeight: CGFloat = Space.x10
    package static let pillWidth: CGFloat = 148
    package static let ink = Swatch("16181E")
    package static let inkAlpha = 0.94
    package static let duration = 0.22
}

package enum SettingsPanelState: Sendable, Equatable {
    case normal, docked, folded

    var cornerRadius: CGFloat {
        switch self {
        case .normal: SettingsPanelMetrics.radius
        case .docked: 0
        case .folded: Radius.full
        }
    }
}

/// Where the panel is and where it goes back to; pure, so the three states
/// and their geometry are tested without a window.
package struct SettingsPanelModel: Equatable {
    package private(set) var state: SettingsPanelState = .normal
    private var resting: SettingsPanelState = .normal

    package init() {}

    /// Floating over the window, never a scrim: the window stays usable.
    package var blocksWindow: Bool { false }

    package mutating func toggleDock() {
        switch state {
        case .normal: state = .docked; resting = .docked
        case .docked: state = .normal; resting = .normal
        case .folded: break
        }
    }

    package mutating func fold() {
        guard state != .folded else { return }
        resting = state
        state = .folded
    }

    package mutating func unfold() {
        guard state == .folded else { return }
        state = resting
    }

    package func frame(in window: CGSize) -> CGRect {
        let inset = SettingsPanelMetrics.inset
        switch state {
        case .normal:
            let width = min(SettingsPanelMetrics.width, max(0, window.width - 2 * inset))
            let height = min(SettingsPanelMetrics.maxHeight, max(0, window.height - 2 * inset))
            return CGRect(x: window.width - width - inset, y: window.height - height - inset,
                          width: width, height: height)
        case .docked:
            let width = min(SettingsPanelMetrics.width, window.width)
            return CGRect(x: window.width - width, y: 0, width: width, height: window.height)
        case .folded:
            let width = min(SettingsPanelMetrics.pillWidth, max(0, window.width - 2 * inset))
            let height = SettingsPanelMetrics.pillHeight
            return CGRect(x: window.width - width - inset, y: window.height - height - inset,
                          width: width, height: height)
        }
    }
}

/// The compact panel has no room for the sheet's sidebar.
package enum SettingsLayout: Sendable {
    case sheet, compact

    var showsSidebar: Bool { self == .sheet }
    /// The sheet searches from its sidebar, the panel from its top.
    var showsSearch: Bool { true }
    var pagePadding: CGFloat { self == .sheet ? Space.x6 : Space.x3 }
}

struct SettingsPanelHeader: View {
    let title: String
    let state: SettingsPanelState
    let onDock: () -> Void
    let onFold: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Space.x1) {
            Text(title)
                .font(Fonts.sans(TypeSize.rowTitle).weight(.semibold))
                .foregroundStyle(Semantic.foreground)
            Spacer(minLength: Space.x2)
            IconButton(state == .docked ? "macwindow" : "sidebar.right",
                       label: Localized.string(state == .docked ? "settings.panel.undock" : "settings.panel.dock"),
                       action: onDock)
            IconButton("chevron.down", label: Localized.string("settings.panel.fold"), action: onFold)
            CloseButton(action: onClose)
        }
        .padding(.horizontal, SettingsPanelMetrics.paddingX)
        .padding(.vertical, SettingsPanelMetrics.paddingY)
    }
}

struct SettingsPanelPill: View {
    let title: String
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: Space.x2) {
                Image(systemName: "gearshape").accessibilityHidden(true)
                Text(title)
                Spacer(minLength: Space.none)
                Image(systemName: "chevron.up").accessibilityHidden(true)
            }
            .font(Fonts.sans(TypeSize.body).weight(.medium))
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, SettingsPanelMetrics.paddingX)
            .frame(maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localized.string("settings.panel.unfold"))
    }
}

/// The panel itself, dark like Incredible's whatever the app's appearance.
struct SettingsPanelHost: View {
    @Binding var model: SettingsPanelModel
    @Binding var tab: SettingsTab
    let preview: VoicePreview?
    let chat: ChatViewModel?
    let updates: UpdateState?
    let welcome: WelcomeModel?
    let memory: (any MemoryBrowsing)?
    let browser: BrowserSettingsModel?
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let frame = model.frame(in: geo.size)
            let shape = UnevenRoundedRectangle(cornerRadii: corners(model.state))
            content
                .frame(width: frame.width, height: frame.height)
                .background(shape.fill(SettingsPanelMetrics.ink.color.opacity(SettingsPanelMetrics.inkAlpha)))
                .clipShape(shape)
                .overlay(shape.stroke(Semantic.border, lineWidth: Stroke.hairline))
                .environment(\.colorScheme, .dark)
                .position(x: frame.midX, y: frame.midY)
                .animation(ChromeMotion.animation(
                    MotionCurve.animation(MotionCurve.standard, SettingsPanelMetrics.duration),
                    reduceMotion: reduceMotion), value: model)
        }
    }

    /// Docked: flush on the right edge, rounded only where it faces the window.
    private func corners(_ state: SettingsPanelState) -> RectangleCornerRadii {
        let r = state.cornerRadius
        return state == .docked
            ? RectangleCornerRadii(topLeading: SettingsPanelMetrics.radius, bottomLeading: SettingsPanelMetrics.radius)
            : RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
    }

    @ViewBuilder private var content: some View {
        if model.state == .folded {
            SettingsPanelPill(title: Localized.string("settings.title")) { model.unfold() }
        } else {
            VStack(spacing: Space.none) {
                SettingsPanelHeader(
                    title: Localized.string("settings.title"), state: model.state,
                    onDock: { model.toggleDock() }, onFold: { model.fold() }, onClose: onClose)
                SettingsView(
                    preview: preview, chat: chat, updates: updates, welcome: welcome,
                    memory: memory, browser: browser, tab: $tab, layout: .compact, onClose: onClose)
            }
        }
    }
}
