import CompanionCore
import SwiftUI

// S1 of the Settings brief (ajustes-hoja-incredible): Incredible's Settings is
// a modal sheet centred over a scrim. The WIN-5 floating panel copied its
// first-run dev panel instead. Values come from the local reference
// [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967].

package enum SettingsSheetMetrics {
    package static let maxWidth: CGFloat = 1100
    package static let maxHeight: CGFloat = 900
    package static let heightShare: CGFloat = 0.9
    /// Below this width the sheet keeps the smaller margin, as Incredible's
    /// breakpoint does.
    package static let wideBreak: CGFloat = 768
    package static let wideMargin: CGFloat = 64
    package static let narrowMargin: CGFloat = 32
    package static let radius: CGFloat = Radius.dialog
    package static let elevation: Elevation = .popover
    /// A plain black veil: the dynamic `Semantic.scrim` is the app's, not the sheet's.
    package static let scrimAlpha = 0.34
    package static let duration = 0.2
    package static let curve = MotionCurve.standard
    package static let enterScale: CGFloat = 0.98
    package static let enterLift: CGFloat = 4
    package static let closeInset: CGFloat = 22

    package static func size(in window: CGSize) -> CGSize {
        let margin = window.width >= wideBreak ? wideMargin : narrowMargin
        return CGSize(
            width: max(0, min(maxWidth, window.width - margin)),
            height: max(0, min(maxHeight, window.height * heightShare)))
    }

    /// Callers still pass it through `ChromeMotion`, which drops it under Reduce Motion.
    static var motion: Animation { MotionCurve.animation(curve, duration) }
}

package enum SettingsSheetPhase: Sendable, Equatable {
    case entering, shown, leaving

    var opacity: Double { self == .shown ? 1 : 0 }
    var scale: CGFloat { self == .shown ? 1 : SettingsSheetMetrics.enterScale }
    /// Only the entrance travels: it drops into place, the exit shrinks where it is.
    var offsetY: CGFloat { self == .entering ? -SettingsSheetMetrics.enterLift : 0 }
}

package enum SettingsEscape: Sendable, Equatable {
    case clearedSearch, close, ignored
}

/// Whether the sheet is mounted and where its transition stands. The sheet
/// stays mounted through its exit so the content does not vanish mid-fade.
package struct SettingsSheetModel: Equatable {
    package private(set) var isOpen = false
    package private(set) var phase: SettingsSheetPhase = .entering
    /// Lives here, not in the view, so Esc can clear it before closing.
    package var query = ""
    /// Popups and alerts live here for the same reason: the root sees them
    /// before it decides to close the sheet.
    package var dialogs = SettingsDialogStack()

    package init() {}

    /// True when the caller must animate `settle()` on the next turn. An
    /// open sheet stays as it is: a second entry point must not replay the
    /// entrance or wipe the search.
    package mutating func open(animated: Bool) -> Bool {
        guard !isOpen || phase == .leaving else { return false }
        isOpen = true
        phase = animated ? .entering : .shown
        query = ""
        dialogs = SettingsDialogStack()
        return animated
    }

    package mutating func settle() {
        guard isOpen, phase == .entering else { return }
        phase = .shown
    }

    /// A second request during the exit is not a close: animating a phase
    /// that does not change completes at once and would cut the exit short.
    package var canClose: Bool { isOpen && phase != .leaving }

    /// True when the caller must call `finishClose()` once the exit has played.
    package mutating func close(animated: Bool) -> Bool {
        guard canClose else { return false }
        dialogs = SettingsDialogStack()
        phase = .leaving
        guard animated else {
            isOpen = false
            return false
        }
        return true
    }

    /// A reopen during the exit moved the phase on; the old exit's end must not close it.
    package mutating func finishClose() {
        guard phase == .leaving else { return }
        isOpen = false
    }

    /// Closes the alert before the popup. The sheet stays open.
    @discardableResult
    package mutating func dismissDialog() -> Bool {
        dialogs.dismissTop()
    }

    package mutating func escape() -> SettingsEscape {
        guard canClose else { return .ignored }
        guard query.isEmpty else {
            query = ""
            return .clearedSearch
        }
        return .close
    }
}

/// The scrim and the sheet over the window.
struct SettingsSheetHost: View {
    @Binding var model: SettingsSheetModel
    @Binding var tab: SettingsTab
    let preview: VoicePreview?
    let chat: ChatViewModel?
    let updates: UpdateState?
    let welcome: WelcomeModel?
    let memory: (any MemoryBrowsing)?
    let browser: BrowserSettingsModel?
    let onClose: () -> Void

    @Environment(DropdownHost.self) private var dropdowns

    static var closeLabel: String { Localized.string("settings.close") }

    var body: some View {
        GeometryReader { geo in
            let size = SettingsSheetMetrics.size(in: geo.size)
            ZStack {
                Color.black.opacity(SettingsSheetMetrics.scrimAlpha)
                    .opacity(model.phase.opacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)
                sheet
                    .frame(width: size.width, height: size.height)
                    .opacity(model.phase.opacity)
                    .scaleEffect(model.phase.scale)
                    .offset(y: model.phase.offsetY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var sheet: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsSheetMetrics.radius)
        return SettingsView(
            preview: preview, chat: chat, updates: updates, welcome: welcome,
            memory: memory, browser: browser, tab: $tab, query: $model.query,
            dialogs: $model.dialogs, onClose: onClose)
            .background(Semantic.background)
            .clipShape(shape)
            .background(shape.fill(Semantic.background).elevation(SettingsSheetMetrics.elevation))
            .overlay(shape.stroke(Semantic.borderChrome, lineWidth: Stroke.hairline))
            .overlay(alignment: .topTrailing) {
                CloseButton(label: Self.closeLabel) {
                    dropdowns.dismiss()
                    onClose()
                }
                .padding(SettingsSheetMetrics.closeInset)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}
