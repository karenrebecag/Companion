import CompanionCore
import Observation
import SwiftUI

package enum HistoryClearChoice: Equatable, Sendable {
    case cancel
    case confirm
}

/// What the confirmation knows, apart from how it is drawn. Close and the
/// backdrop go through `close()`, so neither can interrupt a delete that
/// is already running.
@MainActor @Observable
package final class HistoryClearModel {
    package private(set) var presented = false
    package private(set) var busy = false
    package private(set) var errorText: String?

    package init() {}

    package func present() {
        presented = true
    }

    package func close() {
        guard presented, !busy else { return }
        presented = false
        errorText = nil
    }

    package func canConfirm(chat: ChatViewModel?) -> Bool {
        presented && !busy && chat != nil
    }

    /// Arms the delete. A second press while it runs does not start another.
    @discardableResult
    package func begin(chat: ChatViewModel?) -> Bool {
        guard canConfirm(chat: chat) else { return false }
        busy = true
        errorText = nil
        return true
    }

    package func finish(cleared: Bool) {
        busy = false
        if cleared {
            presented = false
        } else {
            errorText = Localized.string("settings.history.error")
        }
    }

    package func confirm(chat: ChatViewModel?) async {
        guard begin(chat: chat) else { return }
        // The delete blocks the main actor; this lets "Clearing…" paint first.
        await Task.yield()
        var cleared = false
        do {
            try chat?.applyHistoryClear(.confirm)
            cleared = true
        } catch {
            chat?.log("history: clear failed")
        }
        finish(cleared: cleared)
    }
}

struct HistoryClearDialog: View {
    static let maxWidth: CGFloat = 440

    let model: HistoryClearModel
    let chat: ChatViewModel?

    var body: some View {
        if model.presented {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .onTapGesture { model.close() }
                card
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x3) {
                Text(Localized.string("settings.history.title"))
                    .font(.uiSubtitle)
                    .foregroundStyle(Semantic.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.x3)
                IconButton("xmark", label: CloseButton.label, size: .small) { model.close() }
                    .disabled(model.busy)
            }
            Text(Localized.string("settings.history.blurb"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.errorText {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.x2) {
                Spacer()
                SettingsPill(
                    title: Localized.string("settings.history.cancel"), enabled: !model.busy
                ) { model.close() }
                SettingsPill(
                    title: model.busy
                        ? Localized.string("settings.history.clearing")
                        : Localized.string("settings.history.confirm"),
                    kind: .destructive,
                    enabled: model.canConfirm(chat: chat)
                ) {
                    let model = model
                    let chat = chat
                    Task { @MainActor in await model.confirm(chat: chat) }
                }
            }
        }
        .padding(Space.x5)
        .frame(maxWidth: Self.maxWidth)
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(Semantic.surfaceOverlay)
                .elevation(.sheet))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Semantic.border, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localized.string("settings.history.a11y"))
    }
}
