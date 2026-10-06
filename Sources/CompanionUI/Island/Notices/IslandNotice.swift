import CompanionCore
import SwiftUI

/// Where the brake sits (spec 16i §2): while the voice speaks the orb itself
/// turns into the red stop button, as in Incredible; otherwise a chip.
enum IslandStop {
    /// "Cancelled" stays under the notch this long after a stop.
    static let cancelledFor: Double = 2

    /// Incredible has no single brake (16q-1): the orb stops the turn of
    /// voice and the agents keep working; each task has its own stop. The
    /// island's stop is the job's when the job card is what it shows, and the
    /// voice's otherwise. An untagged job has no id to stop by.
    enum Brake: Equatable { case voice, job(JobID?) }

    static func brake(for p: SessionProjection) -> Brake {
        guard p.kind == .processing(.subAgentRunning), let job = p.job else { return .voice }
        return .job(job.id)
    }

    /// The island's stop, applied: the voice's brake never reaches a job.
    static func stop(_ chat: ChatViewModel) {
        switch brake(for: chat.session.projection) {
        case .job(let id?): chat.cancelJob(id)
        case .job(nil): chat.cancelJob()
        case .voice: chat.session.send(.stopVoice)
        }
    }

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
/// happened, how to fix it, and the button that does. 16m-4: each family sits
/// on the grid Incredible measures for it.
enum IslandNotice {
    /// Which measured grid a notice sits on (`IslandNoticeMetrics`).
    nonisolated enum Grid: Equatable { case limit, update, permission, diagnostic }

    struct Content: Equatable {
        let grid: Grid
        let symbol: String
        let title: String
        let body: String?
        let action: IslandState.Action?
        /// The button's own word: a notice's action says what it does, not
        /// what the last notice with a countdown said.
        let actionTitle: String?
        /// Set when the notice leaves on its own; the ring counts it down.
        let lifetime: Double?
        /// An offer (no countdown) is waved away with its own word.
        var dismissTitle: String?
    }

    /// Arc: status tones mean status. A failure is danger; a limit or a
    /// missing permission needs attention; an offer is information.
    static func tone(_ grid: Grid) -> Swatch {
        switch grid {
        case .diagnostic: ArcTone.danger
        case .limit, .permission: ArcTone.warning
        case .update: ArcTone.accent
        }
    }

    /// The faint tint behind a notice's icon.
    static let toneWash = 0.16

    static func content(for line: IslandState.Line) -> Content? {
        switch line {
        case .couldntHear:
            Content(grid: .diagnostic, symbol: "mic.slash.fill",
                    title: Localized.string("island.notice.couldntHear.title"),
                    body: Localized.string("island.notice.couldntHear.body"),
                    action: .openPermission(.micDenied),
                    actionTitle: Localized.string("island.notice.checkMic"),
                    lifetime: SessionMachine.noticeDelay)
        case .permission(let failure):
            Content(grid: .permission, symbol: "lock.fill", title: VoiceCopy.failure(failure), body: nil,
                    action: .openPermission(failure),
                    actionTitle: IslandCopy.action(.openPermission(failure)), lifetime: nil)
        case .failure(.quotaExceeded):
            Content(grid: .limit, symbol: "key.fill",
                    title: Localized.string("island.notice.limit.title"),
                    body: VoiceCopy.failure(.quotaExceeded),
                    action: .openKeys, actionTitle: IslandCopy.action(.openKeys), lifetime: nil)
        case .failure(let failure):
            Content(grid: .diagnostic, symbol: symbol(failure), title: VoiceCopy.failure(failure), body: nil,
                    action: keysAction(failure),
                    actionTitle: keysAction(failure).map(IslandCopy.action), lifetime: nil)
        case .connectApp(let slug, let name):
            // 16k-3: the way to the Apps page rides the card; it leaves on
            // its own so an unanswered nudge never squats the island.
            Content(grid: .permission, symbol: "app.badge",
                    title: String(format: Localized.string("island.connectApp"), name),
                    body: Localized.string("island.connectApp.body"),
                    action: .openApps(slug: slug),
                    actionTitle: IslandCopy.action(.openApps(slug: slug)),
                    lifetime: SessionMachine.noticeDelay)
        case .signInApp(let slug, let name):
            // The account is connected but its session expired: the way back
            // is the Apps page, and the card leaves on its own like the
            // connect nudge.
            Content(grid: .limit, symbol: "person.crop.circle.badge.exclamationmark",
                    title: String(format: Localized.string("island.signIn"), name),
                    body: Localized.string("island.signIn.body"),
                    action: .openApps(slug: slug),
                    actionTitle: Localized.string("island.signIn.action"),
                    lifetime: SessionMachine.noticeDelay)
        case .replyCut:
            Content(grid: .diagnostic, symbol: "wifi.exclamationmark",
                    title: Localized.string("island.replyCut.title"),
                    body: Localized.string("island.replyCut.body"),
                    action: nil, actionTitle: nil, lifetime: SessionMachine.noticeDelay)
        case .approvalWithdrawn:
            Content(grid: .diagnostic, symbol: "hand.raised.fill",
                    title: Localized.string("island.approvalWithdrawn.title"),
                    body: Localized.string("island.approvalWithdrawn.body"),
                    action: nil, actionTitle: nil, lifetime: SessionMachine.noticeDelay)
        case .chatError(let text):
            Content(grid: .diagnostic, symbol: "exclamationmark.circle.fill", title: text, body: nil,
                    action: nil, actionTitle: nil, lifetime: SessionMachine.noticeDelay)
        case .updateAvailable(let tag):
            Content(grid: .update, symbol: "arrow.down.circle.fill",
                    title: String(format: Localized.string("island.notice.update.title"), tag),
                    body: Localized.string("island.notice.update.body"),
                    action: .openUpdate, actionTitle: IslandCopy.action(.openUpdate), lifetime: nil,
                    dismissTitle: Localized.string("island.notice.update.later"))
        default:
            nil
        }
    }

    /// The text whose 6 s clock runs, only while the card is drawn.
    static func expiringChatError(_ line: IslandState.Line) -> String? {
        if case .chatError(let text) = line { return text }
        return nil
    }

    /// What VoiceOver says when the card appears.
    static func announcement(_ content: Content) -> String {
        [content.title, content.body].compactMap { $0 }.joined(separator: ". ")
    }

    /// 1 when the card appears, 0 when it leaves.
    static func remaining(elapsed: Double, lifetime: Double) -> Double {
        guard lifetime > 0 else { return 0 }
        return min(max(1 - elapsed / lifetime, 0), 1)
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

/// The orb while it speaks: red, a square inside, "Stop talking" above.
struct IslandStopOrb: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Arc's end control: the danger tone over its own wash, not a solid red disc.
            Image(systemName: "stop.fill")
                .font(GeistFont.uiCaption)
                .foregroundStyle(IslandInk.stop)
                .frame(width: IslandChrome.meterSide, height: IslandChrome.meterSide)
                .background(Circle().fill(ArcTone.wash(ArcTone.danger, IslandChrome.stopWash)))
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
                .font(GeistFont.uiCaption.weight(.medium))
                .foregroundStyle(IslandInk.secondary)
                .padding(.horizontal, Space.x2)
                .padding(.vertical, Space.x1)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(IslandInk.hairline, lineWidth: Stroke.hairline))
            Text(title)
                .font(GeistFont.uiLabel)
                .foregroundStyle(IslandInk.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            CloseButton(variant: .island, label: Localized.string("island.task.drop"), action: onDrop)
        }
    }
}
