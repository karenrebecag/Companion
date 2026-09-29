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
        VStack(alignment: .leading, spacing: IslandDictationMetrics.gap) {
            HStack(spacing: Space.x2) {
                Text(String(format: Localized.string("island.dictated"), app))
                    .font(GeistFont.uiCaption.weight(.semibold))
                    .foregroundStyle(IslandInk.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                IconButton(copied ? "checkmark" : "doc.on.doc",
                           label: Localized.string(copied ? "island.dictation.copied" : "island.dictation.copy"),
                           size: .islandClose, tone: .island, pressable: true, action: copy)
                CloseButton(variant: .island, label: Localized.string("island.dictation.hide"), action: onHide)
            }
            Text(text)
                .font(Fonts.geist(IslandDictationMetrics.textSize).weight(.medium))
                .tracking(IslandDictationMetrics.textTracking, at: IslandDictationMetrics.textSize)
                .lineSpacing(AnswerBlockMetrics.lineSpacing(
                    size: IslandDictationMetrics.textSize, leading: IslandDictationMetrics.textLeading))
                .foregroundStyle(IslandInk.text)
                .lineLimit(IslandDictationMetrics.maxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, IslandDictationMetrics.paddingTop)
        .padding(.horizontal, IslandDictationMetrics.paddingX)
        .padding(.bottom, IslandDictationMetrics.paddingBottom)
        .frame(minWidth: IslandDictationMetrics.minWidth, maxWidth: IslandDictationMetrics.maxWidth)
        .background(RoundedRectangle(cornerRadius: IslandInk.cardRadius).fill(IslandInk.field))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onHover(perform: onHover)
        .onAppear {
            AccessibilityNotification.Announcement(String(format: Localized.string("island.dictated"), app)).post()
        }
        .onDisappear { copiedReset?.cancel() }
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
