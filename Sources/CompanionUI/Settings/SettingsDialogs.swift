import CompanionCore
import SwiftUI

// Sizes, which entry uses which width, and the alert cap:
// local reference; brief ajustes-hoja-incredible S4.

package enum SettingsPopupWidth: String, CaseIterable, Equatable, Sendable {
    case normal, wide, tall
}

package struct SettingsPopupMeasure: Equatable, Sendable {
    package let maxWidth: CGFloat
    /// Tall is the only width with a floor. Nil means the card hugs its content.
    package let minHeight: CGFloat?
}

package enum SettingsDialogMetrics {
    package static let inset = Space.x7
    package static let closeInset = Space.indent
    /// Tall's floor is the smaller of this share of the viewport and `minHeight`.
    package static let tallShare: CGFloat = 0.56
    /// The scrolling body stops here so the title and the close stay on screen.
    package static let bodyShare: CGFloat = 0.68

    package static func popup(_ variant: SettingsPopupWidth) -> SettingsPopupMeasure {
        switch variant {
        case .normal: SettingsPopupMeasure(maxWidth: 620, minHeight: nil)
        case .wide: SettingsPopupMeasure(maxWidth: 780, minHeight: nil)
        case .tall: SettingsPopupMeasure(maxWidth: 520, minHeight: 520)
        }
    }

    package static func minimumHeight(_ variant: SettingsPopupWidth, viewport: CGFloat) -> CGFloat {
        guard let cap = popup(variant).minHeight else { return 0 }
        return min(viewport * tallShare, cap)
    }

    package static func bodyCap(viewport: CGFloat) -> CGFloat {
        max(0, viewport * bodyShare)
    }

    /// Nil for a popup: only an alert has a cap of its own.
    package static func alertCap(_ id: SettingsDialogID) -> CGFloat? {
        switch id {
        case .purgeAttachments: 440
        case .shortcuts, .permissions: nil
        }
    }

    package static func width(_ id: SettingsDialogID) -> CGFloat {
        if let variant = id.popupWidth { return popup(variant).maxWidth }
        return alertCap(id) ?? popup(.normal).maxWidth
    }
}

/// Which control takes the keyboard when a dialog appears.
package enum SettingsDialogFocus: Equatable, Sendable {
    case close, cancel
}

package enum SettingsDialogID: String, CaseIterable, Equatable, Sendable {
    case shortcuts, permissions
    case purgeAttachments

    package var popupWidth: SettingsPopupWidth? {
        switch self {
        case .shortcuts, .permissions: .normal
        case .purgeAttachments: nil
        }
    }

    package var isAlert: Bool { popupWidth == nil }

    /// A destructive alert starts on its safe button, so Return cannot delete by accident.
    package var initialFocus: SettingsDialogFocus { isAlert ? .cancel : .close }

    package var titleKey: String {
        switch self {
        case .shortcuts: "settings.dialog.shortcuts.title"
        case .permissions: "settings.permissions"
        case .purgeAttachments: "settings.purge.title"
        }
    }

    package var sublineKey: String {
        switch self {
        case .shortcuts: "settings.dialog.shortcuts.subline"
        case .permissions: "settings.dialog.permissions.subline"
        case .purgeAttachments: "settings.dialog.purge.subline"
        }
    }

    /// The confirm label of an alert. A popup has none and says so by saying "close".
    package var confirmKey: String {
        self == .purgeAttachments ? "settings.purge.confirm" : "action.close"
    }

    /// Search rows and deep links name the same dialog by more than one id.
    package static func opened(by entryID: String) -> SettingsDialogID? {
        if let id = SettingsDialogID(rawValue: entryID) { return id }
        if entryID == "settings.permissions" { return .permissions }
        return nil
    }
}

/// What Esc should do, in the order the window actually stacks its layers.
package enum SettingsExitTarget: Equatable, Sendable {
    case approval, dropdown, dialog, clearSearch, closeSheet, voice, none
}

package enum SettingsExitChain {
    package static func target(
        approval: Bool,
        settingsOpen: Bool,
        canCloseSheet: Bool,
        dropdown: Bool,
        dialog: Bool,
        searchEmpty: Bool,
        voice: Bool
    ) -> SettingsExitTarget {
        if approval { return .approval }
        if settingsOpen, dropdown { return .dropdown }
        if settingsOpen, dialog { return .dialog }
        if settingsOpen, canCloseSheet {
            return searchEmpty ? .closeSheet : .clearSearch
        }
        if settingsOpen { return .none }
        if dropdown { return .dropdown }
        if voice { return .voice }
        return .none
    }
}

/// Paint order of the open dialogs. The alert is above the popup, and one
/// scrim sits under the topmost card so a stacked pair is not dimmed twice.
package struct SettingsDialogLayerPlan: Equatable, Sendable {
    package struct Card: Equatable, Sendable {
        package let id: SettingsDialogID
        package let layer: Double
    }

    package let scrim: Double?
    package let cards: [Card]

    private static let popupLayer = 1.0
    private static let alertLayer = 2.0
    private static let scrimGap = 0.5

    package static func make(popup: SettingsDialogID?, alert: SettingsDialogID?) -> SettingsDialogLayerPlan {
        var cards: [Card] = []
        if let popup { cards.append(Card(id: popup, layer: popupLayer)) }
        if let alert { cards.append(Card(id: alert, layer: alertLayer)) }
        return SettingsDialogLayerPlan(
            scrim: cards.last.map { $0.layer - scrimGap }, cards: cards)
    }
}

package struct SettingsDialogStack: Equatable, Sendable {
    package var popup: SettingsDialogID?
    package var alert: SettingsDialogID?

    package init() {}

    package var isPresented: Bool { popup != nil || alert != nil }

    package mutating func present(_ id: SettingsDialogID) {
        if id.isAlert {
            alert = id
        } else {
            popup = id
        }
    }

    /// The alert is above the popup, so it leaves first. False when nothing is open.
    @discardableResult
    package mutating func dismissTop() -> Bool {
        if alert != nil {
            alert = nil
            return true
        }
        if popup != nil {
            popup = nil
            return true
        }
        return false
    }

    /// Runs the purge only for the open purge alert, then closes it. The view
    /// calls this and nothing else, so a cancel or Esc cannot reach the purge.
    @discardableResult
    package mutating func confirm(purge: () -> Void) -> Bool {
        guard alert == .purgeAttachments else { return false }
        purge()
        alert = nil
        return true
    }
}

private struct SettingsDialogOpenKey: EnvironmentKey {
    static let defaultValue: (SettingsDialogID) -> Void = { _ in }
}

extension EnvironmentValues {
    var openSettingsDialog: (SettingsDialogID) -> Void {
        get { self[SettingsDialogOpenKey.self] }
        set { self[SettingsDialogOpenKey.self] = newValue }
    }
}

struct SettingsDialogLinks: View {
    let ids: [SettingsDialogID]
    let open: (SettingsDialogID) -> Void

    var body: some View {
        SettingsCard {
            ForEach(ids, id: \.self) { id in
                SettingsRow(
                    title: Localized.string(id.titleKey),
                    subtitle: Localized.string(id.sublineKey),
                    key: id.rawValue
                ) {
                    SettingsPill(title: Localized.string("settings.dialog.open")) { open(id) }
                }
            }
        }
    }
}

struct SettingsDialogLayer: View {
    @Binding var stack: SettingsDialogStack
    var permissions: [PermissionRowModel]
    var onConfirm: () -> Void

    var body: some View {
        if stack.isPresented {
            let plan = SettingsDialogLayerPlan.make(popup: stack.popup, alert: stack.alert)
            GeometryReader { geo in
                ZStack {
                    if let scrim = plan.scrim {
                        Color.black.opacity(SettingsSheetMetrics.scrimAlpha)
                            .contentShape(Rectangle())
                            .onTapGesture { _ = stack.dismissTop() }
                            .zIndex(scrim)
                            .accessibilityHidden(true)
                    }
                    ForEach(plan.cards, id: \.id) { card in
                        SettingsDialogCard(
                            id: card.id, permissions: permissions, viewport: geo.size.height,
                            onClose: { _ = stack.dismissTop() }, onConfirm: onConfirm)
                            .zIndex(card.layer)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct SettingsDialogCard: View {
    let id: SettingsDialogID
    var permissions: [PermissionRowModel]
    var viewport: CGFloat
    let onClose: () -> Void
    let onConfirm: () -> Void
    @FocusState private var focus: SettingsDialogFocus?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.dialog, style: .continuous)
        card
            .padding(SettingsDialogMetrics.inset)
            .frame(maxWidth: SettingsDialogMetrics.width(id))
            .frame(minHeight: minHeight)
            .background(shape.fill(Semantic.surfaceSecondary).elevation(.popover))
            .overlay(shape.stroke(Semantic.borderChrome, lineWidth: Stroke.hairline))
            .overlay(alignment: .topTrailing) {
                CloseButton(label: Localized.string("action.close"), action: onClose)
                    .focused($focus, equals: .close)
                    .padding(SettingsDialogMetrics.closeInset)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Localized.string(id.titleKey))
            .accessibilityAddTraits(.isModal)
            .onAppear { focus = id.initialFocus }
    }

    private var minHeight: CGFloat {
        guard let variant = id.popupWidth else { return 0 }
        return SettingsDialogMetrics.minimumHeight(variant, viewport: viewport)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(Localized.string(id.titleKey))
                .font(Fonts.sans(TypeSize.dialogTitle).weight(.semibold))
                .tracking(Tracking.title, at: TypeSize.dialogTitle)
                .foregroundStyle(Semantic.foreground)
                .padding(.trailing, Space.x8)
            Text(Localized.string(id.sublineKey))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if !id.isAlert {
                ScrollView {
                    bodyContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: SettingsDialogMetrics.bodyCap(viewport: viewport))
            }
            if id.isAlert { alertActions }
        }
    }

    @ViewBuilder private var bodyContent: some View {
        switch id {
        case .shortcuts: SettingsDialogShortcuts()
        case .permissions:
            VStack(alignment: .leading, spacing: Space.none) {
                ForEach(permissions, id: \.kind) { SettingsPermissionRow(model: $0) }
            }
        case .purgeAttachments: EmptyView()
        }
    }

    private var alertActions: some View {
        HStack(spacing: Space.x2) {
            Spacer(minLength: Space.none)
            SettingsPill(title: Localized.string("settings.dialog.cancel"), action: onClose)
                .focused($focus, equals: .cancel)
            SettingsPill(title: Localized.string(id.confirmKey), kind: .destructive, action: onConfirm)
        }
    }
}

/// Read-only: the bindings are edited elsewhere, and this list only shows them.
private struct SettingsDialogShortcuts: View {
    @State private var set: ShortcutSet?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                HStack(spacing: Space.x3) {
                    Text(action.label)
                        .font(.uiLabel)
                        .foregroundStyle(Semantic.foreground)
                    Spacer(minLength: Space.x3)
                    Text(set?.shortcut(for: action)?.displayKey()
                        ?? Localized.string("settings.dialog.shortcuts.unset"))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
        }
        .padding(.top, Space.x2)
        .onAppear { set = ShortcutSet.load() }
    }
}
