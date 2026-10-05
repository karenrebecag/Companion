import CompanionCore
import SwiftUI

/// The notice card on its measured grid (16m-4). Limit, update and
/// diagnostic are an icon column and the rest; the permission notice is the
/// consent stack. The countdown ring is the notice's remaining life.
struct IslandNoticeCard: View {
    let content: IslandNotice.Content
    /// A chat error draws a ring, but its clock is the view's task: hovering
    /// must not freeze that ring or tell the session to pause.
    let pausesClock: Bool
    let onHover: (Bool) -> Void
    let onAction: (IslandState.Action) -> Void
    let onDismiss: () -> Void
    @State private var shownAt = Date()
    @State private var pause = NoticePause()

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
        .onHover { over in
            pause.pointerMoved(over, pausesClock: pausesClock, at: Date(), send: onHover)
        }
        .onChange(of: content) { _, _ in
            // A new notice arms its own clock. The ring must not keep the
            // previous one's paused time; if the pointer is still down, the
            // fresh clock pauses too.
            shownAt = Date()
            pause.reset(at: shownAt)
            if pause.over, pausesClock { onHover(true) }
        }
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
                let paused = pausesClock ? pause.accumulated(at: context.date) : 0
                let left = NoticeRing.fraction(
                    elapsed: context.date.timeIntervalSince(shownAt),
                    paused: paused, lifetime: lifetime)
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

/// The view's pause rule. The same one the reducer uses, so a ring and its
/// session clock stop together. A chat error is not a session card.
enum NoticeHoverRule {
    static func viewPauses(_ line: IslandState.Line) -> Bool {
        guard let card = sessionCard(line) else { return false }
        return SessionMachine.pausesOnHover(card)
    }

    private static func sessionCard(_ line: IslandState.Line) -> SessionCard? {
        switch line {
        case .couldntHear: .couldntHear
        case .permission(let failure): .permission(failure)
        case .failure(let failure): .failure(failure)
        case .holdHint: .holdHint
        case .connectApp(let slug, let name): .connectApp(slug: slug, name: name)
        case .signInApp(let slug, let name): .signInApp(slug: slug, name: name)
        case .receipt(let receipt): .receipt(receipt)
        case .replyCut: .replyCut
        case .approvalWithdrawn: .approvalWithdrawn
        default: nil
        }
    }
}

/// Time the pointer has spent over a countdown card. The ring subtracts it
/// from the elapsed time, so the stroke freezes and then continues.
struct NoticePause: Equatable {
    var over = false
    private var total: TimeInterval = 0
    private var since: Date?

    /// The pointer is recorded first. `pausesClock` only decides whether the
    /// session hears about it, so leaving a card with no clock still clears
    /// the pause the previous card started.
    mutating func pointerMoved(_ over: Bool, pausesClock: Bool, at date: Date, send: (Bool) -> Void) {
        hover(over, at: date)
        guard pausesClock else { return }
        send(over)
    }

    mutating func hover(_ over: Bool, at date: Date) {
        guard over != self.over else { return }
        if over {
            since = date
        } else if let since {
            total += date.timeIntervalSince(since)
            self.since = nil
        }
        self.over = over
    }

    /// The next notice starts full. `over` stays, so a pointer that never
    /// left pauses the new clock immediately.
    mutating func reset(at date: Date) {
        total = 0
        since = over ? date : nil
    }

    func accumulated(at date: Date) -> TimeInterval {
        total + (since.map { date.timeIntervalSince($0) } ?? 0)
    }
}

/// The ring is the time left, not an animation ending.
enum NoticeRing {
    static func fraction(elapsed: TimeInterval, paused: TimeInterval, lifetime: TimeInterval) -> Double {
        IslandNotice.remaining(elapsed: elapsed - paused, lifetime: lifetime)
    }
}
