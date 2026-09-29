import Foundation

/// Wave 16h-2 (criterion 1): work the user would otherwise wait on in
/// silence opens with one line of ours, said before the work starts.
/// Incredible acknowledges in 1-2.5 s; Companion sat 32 s mute on "búscalo
/// en Safari" because the model delegated without a word.
public enum Acknowledgement: Sendable {
    /// A parent tool still running after this long gets its line. Below it
    /// the result comes fast enough that a line would only be chatter.
    public static let slowToolAfter: Duration = .seconds(1)

    /// The router already says this when it delegates, and it is in the
    /// prewarmed set, so the model path reuses it: same words for the same
    /// act, and audio that is already on disk.
    public static func delegating(_ language: AppLanguage) -> String {
        DecisionCopy.delegated(language)
    }

    /// Says what the slow step is doing when that is known; the screen is
    /// the case Incredible names ("Let me take a look at your screen").
    public static func working(tool name: String, _ language: AppLanguage) -> String {
        let looks = name == ParentTool.look.rawValue || name == ParentTool.see.rawValue
        switch (looks, language) {
        case (true, .en): return "Let me look at your screen."
        case (true, .es): return "Miro tu pantalla."
        case (false, .en): return "One moment."
        case (false, .es): return "Dame un momento."
        }
    }

    /// One line per turn: once anything was said, the user already knows
    /// the turn is alive.
    public static func isNeeded(saidSoFar said: String) -> Bool {
        said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 16h-2 (security M1): what a spoken yes did with the sheet.
public enum SpokenApproval: Sendable, Equatable {
    case resolved
    case nothingPending
    /// The sheet is there but a voice may not answer it (`SpokenYes`).
    case needsClick
}

/// Review 16h-2 round 3 (HIGH): when a spoken "yes" may answer a sheet.
/// `resolve_approval` is a call the MODEL makes, so its "yes" is only the
/// user's when she can have heard the question and then chose to answer.
/// Realtime has no hold to tie an answer to: never. Classic: the voice must
/// have said the question, and the hold carrying the answer must have
/// started after it, at least the click guard's dwell later.
public enum SpokenYes {
    public static func admits(
        realtime: Bool, announcedAt: TimeInterval?, holdStartedAt: TimeInterval?
    ) -> Bool {
        guard !realtime, let announcedAt, let holdStartedAt else { return false }
        return holdStartedAt >= announcedAt + ApprovalClickGuard.dwell
    }
}

/// Wave 16h-2 (criterion 2): a job's end is said in a gap, never over the
/// user or over a turn of the voice's own. It waits for the turn to end.
public enum AnnouncementGap: Sendable {
    /// A job's end older than this is not said any more.
    // HACK: one fixed age for every notice. Upgrade trigger: a notice that
    // must survive a long turn (a meeting-length dictation) — then the age
    // counts from when the gap first opened, not from the job's end.
    public static let maxAge: TimeInterval = 120

    public static func isOpen(_ voice: TurnSnapshot) -> Bool {
        if voice.pipeline == .realtime { return voice.state == .listening }
        switch voice.state {
        case .idle:
            // A press on its way up is still idle while the mic starts.
            return !voice.classicListenPending && !voice.holdArmed
        case .listening:
            // Warm rest, or hands-free with nobody speaking; a hold's open
            // mic is the user's turn.
            return voice.muted || (!voice.holdArmed && !voice.speechOpen)
        case .connecting, .thinking, .speaking, .error:
            return false
        }
    }
}
