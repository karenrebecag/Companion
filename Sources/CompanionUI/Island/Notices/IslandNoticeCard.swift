import CompanionCore
import SwiftUI

/// The notice card on its measured grid (16m-4). Limit, update and
/// diagnostic are an icon column and the rest; the permission notice is the
/// consent stack. The countdown ring is the notice's remaining life.
struct IslandNoticeCard: View {
    let content: IslandNotice.Content
    let onAction: (IslandState.Action) -> Void
    let onDismiss: () -> Void
    @State private var shownAt = Date()

    var body: some View {
        IslandNoticeWidth(grid: content.grid) {
            Group {
                if content.grid == .permission { consent } else { gridded }
            }
            .padding(.vertical, IslandNoticeMetrics.paddingY)
            .padding(.horizontal, IslandNoticeMetrics.paddingX)
            .background(RoundedRectangle(cornerRadius: IslandInk.cardRadius).fill(IslandInk.field))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(IslandNotice.announcement(content)).post() }
    }

    /// Icon column, then the words; the update card adds its actions to the
    /// right, the others hang the action under the words.
    private var gridded: some View {
        HStack(alignment: .top, spacing: IslandNoticeMetrics.limitColumnGap) {
            tile(IslandNoticeMetrics.gutter(content.grid))
            VStack(alignment: .leading, spacing: IslandNoticeMetrics.limitRowGap) {
                words
                if content.grid != .update { actionButton }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if content.grid == .update {
                HStack(spacing: Space.x2) {
                    dismissButton
                    actionButton
                }
            } else if let lifetime = content.lifetime {
                ring(lifetime)
            }
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: IslandNoticeMetrics.consentGap) {
            HStack(alignment: .top, spacing: IslandNoticeMetrics.limitColumnGap) {
                tile(IslandNoticeMetrics.gutter(.permission))
                words.frame(maxWidth: .infinity, alignment: .leading)
                if let lifetime = content.lifetime { ring(lifetime) }
            }
            actionButton
        }
    }

    private func tile(_ side: CGFloat) -> some View {
        Image(systemName: content.symbol)
            .font(GeistFont.uiLabel)
            .foregroundStyle(IslandInk.blue)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(IslandInk.blueTile))
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(content.title)
                .font(GeistFont.uiLabel.weight(.semibold))
                .foregroundStyle(IslandInk.text)
                .fixedSize(horizontal: false, vertical: true)
            if let body = content.body {
                Text(body)
                    .font(GeistFont.uiCaption)
                    .foregroundStyle(IslandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let action = content.action, let title = content.actionTitle {
            Button { onAction(action) } label: {
                Text(title + " →")
                    .font(GeistFont.uiCaption.weight(.semibold))
                    .foregroundStyle(IslandInk.panel)
                    .padding(.horizontal, Space.x3)
                    .padding(.vertical, IslandInk.chipVertical)
                    .background(Capsule().fill(IslandInk.text))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if let title = content.dismissTitle {
            Button(title, action: onDismiss)
                .buttonStyle(CapsuleChipStyle(ink: .island, density: .compact))
        }
    }

    /// The × sits in a ring that empties as the card's time runs out. Not
    /// `CloseButton`: the ring is the notice's remaining life, a clock the
    /// shared × has no place for.
    private func ring(_ lifetime: Double) -> some View {
        Button(action: onDismiss) {
            TimelineView(.animation(minimumInterval: IslandInk.ringFrame)) { context in
                let left = IslandNotice.remaining(
                    elapsed: context.date.timeIntervalSince(shownAt), lifetime: lifetime)
                ZStack {
                    Circle().stroke(IslandInk.hairline, lineWidth: Stroke.thin)
                    Circle()
                        .trim(from: 0, to: left)
                        .stroke(IslandInk.secondary, style: StrokeStyle(lineWidth: Stroke.thin, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "xmark")
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(IslandInk.secondary)
                }
            }
            .frame(width: IslandInk.slotSide, height: IslandInk.slotSide)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localized.string("island.notice.dismiss"))
    }
}
