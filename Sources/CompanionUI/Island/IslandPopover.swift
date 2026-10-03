import CompanionCore
import SwiftUI

/// Incredible's dropdowns (spec 16i §2): one dark surface anchored under its
/// button, drawn inside the island. A native `Menu` opens a system window in
/// the system's colors, outside the shape and outside its motion.
package enum IslandPopoverKind: Equatable, Sendable {
    case menu
    case volume
    /// The clip's "Add files" (16i-2).
    case attach
}

/// A header icon opens its popover, a second click closes it, another icon
/// switches to its own.
package enum IslandPopoverToggle {
    package static func next(current: IslandPopoverKind?, tapped: IslandPopoverKind) -> IslandPopoverKind? {
        current == tapped ? nil : tapped
    }

    /// The header that opens it exists only in `.nudge`: any other size
    /// closes it at once, so its click area never outlives it (security
    /// review 16o).
    package static func survives(size: IslandState.Size) -> Bool {
        size == .nudge
    }
}

/// Escape closes the popover first, as a menu does; then it lets go of the field.
package enum IslandEscape: Equatable, Sendable {
    case closePopover, dismissField

    package static func action(popoverOpen: Bool) -> IslandEscape {
        popoverOpen ? .closePopover : .dismissField
    }
}

struct IslandPopover<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // 16l-2: Incredible's island menu — 230 wide, radius 16, padding 6, gap 4.
        VStack(alignment: .leading, spacing: MenuMetrics.islandGap) {
            content()
        }
        .padding(MenuMetrics.padding)
        .frame(width: MenuMetrics.islandWidth)
        .background(RoundedRectangle(cornerRadius: MenuMetrics.islandRadius).fill(IslandInk.popover))
        .overlay(RoundedRectangle(cornerRadius: MenuMetrics.islandRadius)
            .stroke(IslandInk.hairline, lineWidth: Stroke.hairline))
    }
}

extension AnyTransition {
    /// Menu dropdown: grows from its trigger's corner, leaves faster.
    static func islandPopover(anchor: UnitPoint, reduceMotion: Bool) -> AnyTransition {
        let budget = IslandMotionBudget.popover
        guard !reduceMotion else { return .opacity.animation(.expoOut(MotionTime.fast)) }
        let shape = AnyTransition.scale(scale: budget.fromScale, anchor: anchor).combined(with: .opacity)
        return .asymmetric(insertion: shape.animation(.expoOut(budget.openDuration)),
                           removal: shape.animation(.expoOut(budget.closeDuration)))
    }
}

/// The five entries of "…", as rows that light under the pointer.
struct IslandMenuList: View {
    let onPick: (IslandMenuItem) -> Void

    var body: some View {
        ForEach(IslandMenuItem.allCases, id: \.self) { item in
            if item.destructive {
                Rectangle()
                    .fill(IslandInk.hairline)
                    .frame(height: Stroke.hairline)
                    .padding(.vertical, Space.x1)
            }
            IslandPopoverRow(title: Localized.string("island.menu." + item.rawValue),
                             tint: item.destructive ? IslandInk.destructive : IslandInk.text) {
                onPick(item)
            }
        }
    }
}

/// The clip's three ways in (spec 16i §2). No shortcut column: the island
/// never activates the app, so ⌥C/⌥X would reach the app in front (the same
/// call 16i-1 made for the "…" menu).
struct IslandAttachList: View {
    let onPick: (IslandAttachItem) -> Void

    var body: some View {
        ForEach(IslandAttachItem.allCases, id: \.self) { item in
            IslandPopoverRow(title: Localized.string("island.attach." + item.rawValue)) {
                onPick(item)
            }
        }
    }
}

struct IslandPopoverRow: View {
    let title: String
    var tint: Color = IslandInk.text
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.geist(TypeSize.body).weight(.medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MenuMetrics.itemPaddingX)
                .padding(.vertical, MenuMetrics.itemPaddingY)
                .background(RoundedRectangle(cornerRadius: MenuMetrics.itemRadius)
                    .fill(hovering ? IslandInk.chipPressed : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "Volume 70 %" and its slider: the voice's volume, saved with the rest
/// of the voice preferences so the next session opens at the same level.
struct IslandVolumeControl: View {
    let onChange: (Double) -> Void
    @State private var volume = IslandVolume.clamped(VoiceProfile.settings.volume)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(String(format: Localized.string("island.volume"), IslandVolume.percent(volume)))
                .font(GeistFont.uiCaption)
                .foregroundStyle(IslandInk.secondary)
            // The voice follows the drag; the preference is written once, on
            // release: its setter rewrites every voice field (code review 16i-1).
            TrackSlider(
                value: $volume, in: IslandVolume.floor...1, label: Localized.string("island.tip.volume")
            ) { editing in
                guard !editing else { return }
                var settings = VoiceProfile.settings
                settings.volume = IslandVolume.clamped(volume)
                VoiceProfile.settings = settings
            }
        }
        .padding(Space.x2)
        .onChange(of: volume) { _, value in onChange(IslandVolume.clamped(value)) }
    }
}

/// transitions.dev tooltip: shows a beat after the pointer arrives, goes
/// at once when it leaves. Placed by `PortalPlacement`.
private struct IslandTooltip: ViewModifier {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                guard inside else {
                    withAnimation(.expoOut(IslandMotionBudget.tooltip.outDuration)) { shown = false }
                    return
                }
                pending = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(IslandMotionBudget.tooltip.delay)) } catch { return }
                    withAnimation(.expoOut(IslandMotionBudget.tooltip.inDuration)) { shown = true }
                }
            }
            // Drawn by the portal over the clip (16o-1), not inside the shape.
            .portal(shown ? .tooltip(text) : nil)
            .onDisappear { pending?.cancel() }
    }
}

extension View {
    func islandTooltip(_ text: String) -> some View {
        modifier(IslandTooltip(text: text))
    }
}
