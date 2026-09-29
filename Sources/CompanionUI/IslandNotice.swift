import CompanionCore
import SwiftUI

/// Where the brake sits (spec 16i §2): while the voice speaks the orb itself
/// turns into the red stop button, as in Incredible; otherwise a chip.
enum IslandStop {
    /// "Cancelled" stays under the notch this long after a stop.
    static let cancelledFor: Double = 2

    static func asOrb(_ state: IslandState) -> Bool {
        state.showsStop && state.meter == .agent
    }

    static func asChip(_ state: IslandState) -> Bool {
        state.showsStop && !asOrb(state)
    }
}

/// The voice's own volume, not the system's. The stored preference reads 0
/// as "never set" and plays it at full volume, so the slider stops above it.
enum IslandVolume {
    static let floor = 0.05

    static func clamped(_ value: Double) -> Double {
        min(max(value, floor), 1)
    }

    static func percent(_ value: Double) -> Int {
        Int((clamped(value) * 100).rounded())
    }
}

/// A notice with a way out, drawn as Incredible's card (spec 16i §9): what
/// happened, how to fix it, and the button that does.
enum IslandNotice {
    struct Content: Equatable {
        let symbol: String
        let title: String
        let body: String?
        let action: IslandState.Action?
        /// Set when the notice leaves on its own; the ring counts it down.
        let lifetime: Double?
    }

    static func content(for line: IslandState.Line) -> Content? {
        switch line {
        case .couldntHear:
            Content(symbol: "mic.slash.fill", title: Localized.string("island.notice.couldntHear.title"),
                    body: Localized.string("island.notice.couldntHear.body"),
                    action: .openPermission(.micDenied), lifetime: SessionMachine.noticeDelay)
        case .permission(let failure):
            Content(symbol: "lock.fill", title: VoiceCopy.failure(failure), body: nil,
                    action: .openPermission(failure), lifetime: nil)
        case .failure(let failure):
            Content(symbol: symbol(failure), title: VoiceCopy.failure(failure), body: nil,
                    action: keysAction(failure), lifetime: nil)
        case .connectApp(let slug, let name):
            // 16k-3: the way to the Apps page rides the card; it leaves on
            // its own so an unanswered nudge never squats the island.
            Content(symbol: "app.badge", title: String(format: Localized.string("island.connectApp"), name),
                    body: Localized.string("island.connectApp.body"),
                    action: .openApps(slug: slug), lifetime: SessionMachine.noticeDelay)
        default:
            nil
        }
    }

    /// 1 when the card appears, 0 when it leaves.
    static func remaining(elapsed: Double, lifetime: Double) -> Double {
        guard lifetime > 0 else { return 0 }
        return min(max(1 - elapsed / lifetime, 0), 1)
    }

    static func actionTitle(_ content: Content) -> String? {
        guard let action = content.action else { return nil }
        if content.lifetime != nil { return Localized.string("island.notice.checkMic") }
        return IslandCopy.action(action)
    }

    private static func symbol(_ failure: TurnFailure) -> String {
        switch failure {
        case .noProviders, .quotaExceeded: "key.fill"
        case .networkUnavailable, .sessionDropped: "wifi.exclamationmark"
        case .micDenied, .micUnavailable, .micSilent, .notHeard: "mic.slash.fill"
        default: "exclamationmark.circle.fill"
        }
    }

    private static func keysAction(_ failure: TurnFailure) -> IslandState.Action? {
        switch failure {
        case .noProviders, .quotaExceeded: .openKeys
        default: nil
        }
    }
}

struct IslandNoticeCard: View {
    let content: IslandNotice.Content
    let onAction: (IslandState.Action) -> Void
    let onDismiss: () -> Void
    @State private var shownAt = Date()

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x3) {
                Image(systemName: content.symbol)
                    .font(GeistFont.uiLabel)
                    .foregroundStyle(IslandInk.blue)
                    .frame(width: IslandInk.noticeTile, height: IslandInk.noticeTile)
                    .background(RoundedRectangle(cornerRadius: Radius.lg).fill(IslandInk.blueTile))
                    .accessibilityHidden(true)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                if let lifetime = content.lifetime {
                    dismiss(lifetime)
                }
            }
            if let action = content.action, let title = IslandNotice.actionTitle(content) {
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
        .padding(Space.x3)
        .background(RoundedRectangle(cornerRadius: IslandInk.cardRadius).fill(IslandInk.field))
    }

    /// The × sits in a ring that empties as the card's time runs out.
    private func dismiss(_ lifetime: Double) -> some View {
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

/// The orb while it speaks: red, a square inside, "Stop talking" above.
struct IslandStopOrb: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(GeistFont.uiCaption)
                .foregroundStyle(IslandInk.text)
                .frame(width: IslandChrome.meterSide, height: IslandChrome.meterSide)
                .background(Circle().fill(IslandInk.stop))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .islandTooltip(Localized.string("island.tip.stop"))
        .accessibilityLabel(Localized.string("island.tip.stop"))
    }
}

/// Follow up from the window (spec 16j §8): the task rides in the island as
/// a TASK tag until the next turn continues it.
struct IslandFollowUpRow: View {
    let title: String
    let onDrop: () -> Void

    var body: some View {
        HStack(spacing: Space.x2) {
            Text(Localized.string("island.task"))
                .font(GeistFont.uiCaption.weight(.semibold))
                .foregroundStyle(IslandInk.secondary)
                .padding(.horizontal, Space.x2)
                .padding(.vertical, Space.x1)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(IslandInk.hairline, lineWidth: Stroke.hairline))
            Text(title)
                .font(GeistFont.uiLabel)
                .foregroundStyle(IslandInk.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDrop) {
                Image(systemName: "xmark")
                    .font(GeistFont.uiCaption)
                    .foregroundStyle(IslandInk.secondary)
                    .frame(width: IslandInk.slotSide, height: IslandInk.slotSide)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localized.string("island.task.drop"))
        }
    }
}
