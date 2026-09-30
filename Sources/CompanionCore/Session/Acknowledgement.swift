import Foundation

/// Wave 16h-2 (criterion 1): work the user would otherwise wait on in
/// silence opens with one line of ours, said before the work starts.
/// Incredible acknowledges in 1-2.5 s; Companion sat 32 s mute on "búscalo
/// en Safari" because the model delegated without a word.
package enum Acknowledgement: Sendable {
    /// A parent tool still running after this long gets its line. Below it
    /// the result comes fast enough that a line would only be chatter.
    package static let slowToolAfter: Duration = .seconds(1)

    /// The router already says this when it delegates, and it is in the
    /// prewarmed set, so the model path reuses it: same words for the same
    /// act, and audio that is already on disk.
    package static func delegating(_ language: AppLanguage) -> String {
        DecisionCopy.delegated(language)
    }

    /// Says what the slow step is doing when that is known; the screen is
    /// the case Incredible names ("Let me take a look at your screen").
    package static func working(tool name: String, _ language: AppLanguage) -> String {
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
    package static func isNeeded(saidSoFar said: String) -> Bool {
        said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 16h-2 (security M1): what a spoken yes did with the sheet.
package enum SpokenApproval: Sendable, Equatable {
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
package enum SpokenYes {
    /// Timing alone is not consent (16q-1 review, security M3): the model
    /// can call `resolve_approval(true)` in the hold after the question
    /// whatever the user said, and a specialist's output can ask it to. The
    /// words of THAT hold must be a clear yes.
    package static func admits(
        realtime: Bool, announcedAt: TimeInterval?, holdStartedAt: TimeInterval?, heard: String?
    ) -> Bool {
        guard !realtime, let announcedAt, let holdStartedAt, let heard, affirms(heard)
        else { return false }
        return holdStartedAt >= announcedAt + ApprovalClickGuard.dwell
    }

    /// A closed allowlist, on purpose: every word must be a yes or a
    /// politeness word, so anything not foreseen (a question with or without
    /// its mark, a hedge, a negation, a number) is not a yes. Short (a yes
    /// with a paragraph after it is another request), counted in the words as
    /// said, and at least one word must be a real yes ("por favor" alone is not).
    // HACK: a word list is the whole judgment. It misses phrasings that mean
    // yes and cannot tell irony. Upgrade trigger: the approval judge (16q-3)
    // reads the user's words and replaces this.
    package static func affirms(_ said: String) -> Bool {
        let raw = said.split(whereSeparator: \.isWhitespace)
        guard (1 ... maxWords).contains(raw.count) else { return false }
        guard !said.contains(where: { $0.isNumber || "?¿".contains($0) }) else { return false }
        var accented: [String] = []
        for word in raw {
            let letters = trimmedToLetters(String(word))
            if letters.isEmpty {
                // A lone dash or ellipsis says nothing; a symbol or emoji might.
                guard word.allSatisfy({ $0.isPunctuation }) else { return false }
                continue
            }
            accented.append(letters)
        }
        let words = accented.map { $0.folding(options: .diacriticInsensitive, locale: nil) }
        // "si" is also "if": unaccented, it only counts as the whole answer.
        if accented.contains("si"), !words.allSatisfy({ $0 == "si" }) { return false }
        return matchesAllowlist(words)
    }

    private static func matchesAllowlist(_ words: [String]) -> Bool {
        var index = 0
        var sawYes = false
        while index < words.count {
            if let phrase = phrases.first(where: { words[index...].starts(with: $0.words) }) {
                sawYes = sawYes || !phrase.polite
                index += phrase.words.count
            } else if yesWords.contains(words[index]) {
                sawYes = true
                index += 1
            } else if politeWords.contains(words[index]) {
                index += 1
            } else {
                return false
            }
        }
        return sawYes
    }

    private static func trimmedToLetters(_ word: String) -> String {
        let lowered = word.lowercased()
        guard let first = lowered.firstIndex(where: \.isLetter),
              let last = lowered.lastIndex(where: \.isLetter) else { return "" }
        return String(lowered[first ... last])
    }

    private static let maxWords = 4
    private static let yesWords: Set<String> = [
        "si", "sip", "dale", "adelante", "hazlo", "permitelo", "aprobado", "apruebalo", "claro", "vale",
        "ok", "okay", "andale", "sale", "va", "orale", "perfecto",
        "yes", "yeah", "yep", "sure", "approved", "alright",
    ]
    private static let politeWords: Set<String> = ["please"]
    /// Longest first: "claro que si" is a unit, and "que" is allowed nowhere else.
    private static let phrases: [(words: [String], polite: Bool)] = [
        (["claro", "que", "si"], false), (["de", "acuerdo"], false), (["go", "ahead"], false),
        (["do", "it"], false), (["allow", "it"], false), (["sounds", "good"], false),
        (["por", "favor"], true),
    ]
}

/// Wave 16h-2 (criterion 2): a job's end is said in a gap, never over the
/// user or over a turn of the voice's own. It waits for the turn to end.
package enum AnnouncementGap: Sendable {
    /// A job's end older than this is not said any more.
    // HACK: one fixed age for every notice. Upgrade trigger: a notice that
    // must survive a long turn (a meeting-length dictation) — then the age
    // counts from when the gap first opened, not from the job's end.
    package static let maxAge: TimeInterval = 120

    package static func isOpen(_ voice: TurnSnapshot) -> Bool {
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
