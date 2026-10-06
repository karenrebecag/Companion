import SwiftUI

/// What a hold pasted, offered back (16m-4): the words as Incredible sets
/// them, with copy and hide. The island paints it while the projection keeps
/// the text; hiding sends the event that lets it go.
struct IslandDictationCard: View {
    let app: String
    let text: String
    let onCopy: () -> Void
    let onHide: () -> Void
    let onHover: (Bool) -> Void
    @State private var copied = false
    @State private var copiedReset: Task<Void, Never>?

    var body: some View {
        IslandGridRow(alignment: .top) {
            Image(systemName: "text.cursor")
                .font(GeistFont.uiLabel)
                .foregroundStyle(ArcTone.textSecondary.color)
                .frame(height: IslandGrid.lead)
                .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: IslandDictationMetrics.gap) {
                Text(String(format: Localized.string("island.dictated"), app))
                    .font(GeistFont.uiCaption.weight(.medium))
                    .foregroundStyle(ArcTone.textSecondary.color)
                    .lineLimit(1)
                    .frame(minHeight: IslandGrid.lead)
                words
            }
        } trail: {
            HStack(spacing: Space.x1) {
                IconButton(copied ? "checkmark" : "doc.on.doc",
                           label: Localized.string(copied ? "island.dictation.copied" : "island.dictation.copy"),
                           size: .islandClose, tone: .island, pressable: true,
                           tint: copied ? IslandDictationMetrics.copiedTint.color : nil, action: copy)
                CloseButton(variant: .island, label: Localized.string("island.dictation.hide"), action: onHide)
            }
            .frame(height: IslandGrid.lead)
        }
        .accessibilityElement(children: .contain)
        .onHover(perform: onHover)
        .onAppear {
            AccessibilityNotification.Announcement(String(format: Localized.string("island.dictated"), app)).post()
        }
        .onDisappear { copiedReset?.cancel() }
    }

    private var words: some View {
        Text(text)
            .font(Fonts.geist(IslandDictationMetrics.textSize).weight(.medium))
            .tracking(IslandDictationMetrics.textTracking, at: IslandDictationMetrics.textSize)
            .lineSpacing(AnswerBlockMetrics.lineSpacing(
                size: IslandDictationMetrics.textSize, leading: IslandDictationMetrics.textLeading))
            .foregroundStyle(ArcTone.foreground.color)
            .lineLimit(IslandDictationMetrics.maxLines)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy() {
        onCopy()
        copied = true
        AccessibilityNotification.Announcement(Localized.string("island.dictation.copied")).post()
        copiedReset?.cancel()
        copiedReset = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(IslandDictationMetrics.copiedFor)) } catch { return }
            copied = false
        }
    }
}
