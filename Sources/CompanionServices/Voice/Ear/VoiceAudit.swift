import CompanionCore
import Foundation

/// The native (Apple es-MX) ear for the realtime path. Apple transcribes the
/// mic; OpenAI only reads text and speaks (Wave 9i).
///
/// Recognition runs CONTINUOUSLY for the whole session. Restarting it per
/// turn re-enters the recognizer's cold start — measured at ~12 s before the
/// first word lands — which is exactly what made every turn come back empty.
/// One task for the session; each turn's text is whatever the running
/// transcript has grown beyond what earlier turns already consumed.
///
/// Off silently when Speech is not authorized. Called only from the
/// VoiceSession actor's context; its async methods are
/// `nonisolated(nonsending)` so they run there instead of hopping to the
/// generic executor and racing the state below.
final class VoiceAudit: @unchecked Sendable {
    private let native: any Transcriber
    private var tally = FrameTally()
    private var goal: String?
    private var enabled = false
    /// Prefix of the running transcript that earlier turns already committed.
    private var committed = ""

    init(native: any Transcriber) { self.native = native }

    /// Whether the native ear is live. False means Speech was denied and the
    /// session has no input path.
    var isLive: Bool { enabled }

    /// The ear's running hypotheses (Wave 12c). One consumer: the session's
    /// partial pump, which reads `turnText()` on the actor after each one.
    var partials: AsyncStream<String> { native.partials }

    nonisolated(nonsending) func begin(locale: String) async {
        guard await native.requestAuthorization() else {
            Log.app("ear: not authorized (Speech permission or missing key) — ear off")
            return
        }
        do {
            try await native.start(localeIdentifier: locale)
        } catch {
            Log.app("ear: native transcriber did not start (\(error))")
            return
        }
        enabled = true
        committed = ""
        Log.app("ear: native ear on (locale \(locale))")
    }

    /// Vetted user audio only: the gate keeps the agent's own voice (no AEC)
    /// out, so the transcript never quotes the assistant back as the user.
    nonisolated(nonsending) func hear(_ frame: MicFrame, forwarded: Bool, reason: GateReason?) async {
        guard enabled else { return }
        tally.add(forwarded: forwarded, reason: reason)
        guard forwarded else { return }
        await native.append(frame)
    }

    /// This turn's words: the running transcript beyond the committed prefix.
    func turnText() -> String {
        let full = native.currentText
        guard !committed.isEmpty, full.hasPrefix(committed) else {
            // First turn — or the recognizer revised/restarted its hypothesis.
            // Better to risk repeating a word than to deadlock waiting for a
            // prefix that will never match again.
            return full.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(full.dropFirst(committed.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The turn was committed: everything recognized so far belongs to it.
    func consume() {
        committed = native.currentText
        tally = FrameTally()
        goal = nil
    }

    func noteGoal(_ goal: String) {
        guard enabled else { return }
        self.goal = goal
        Log.app("ear goal: \(goal.count) chars")
    }

    /// One line per turn: the source text and the frame counts.
    func logTurn() {
        guard enabled else { return }
        Log.app(VoiceAuditReport.turnLine(
            native: turnText(), openAI: "(apple is source)",
            tally: tally, goal: goal))
    }

    nonisolated(nonsending) func end() async {
        if enabled { _ = await native.stop() }
        enabled = false
        committed = ""
    }
}
