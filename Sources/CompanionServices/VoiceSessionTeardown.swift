import CompanionCore
import Foundation

/// Closing the realtime session: tearing down the pumps and the ear, then
/// writing the session's memory note. Split out of VoiceSession when it
/// crossed the 400-line gate. What they touch is not `private` any more but
/// still actor-isolated: the actor, not the access level, is what keeps
/// this state single-threaded.
extension VoiceSession {
    func closeRealtime() async {
        screen?.cancel()
        pendingAnnouncements.removeAll()
        voiceClosed = true
        await silenceAnnouncements(reason: "session-closed")
        micSilenceTask?.cancel()
        micSilenceTask = nil
        eventTask?.cancel()
        eventTask = nil
        earTurnTask?.cancel()
        earTurnTask = nil
        partialTask?.cancel()
        partialTask = nil
        await earTask?.value
        earTask = nil
        earSegment = nil
        dictationTask?.cancel()
        dictationTask = nil
        flushTimeline()
        await audit.end()
        await realtime.close(mic: mic)
        await writeSessionMemory()
    }

    /// 9j-2 write path: distill what THIS session asked into a short note.
    /// Mechanical (no model call) and best-effort — a failed write is logged,
    /// never surfaced as a session error.
    private func writeSessionMemory() async {
        guard let memoryStore else { return }
        // The memory reads the words, not the model's history: the compact
        // context line ("[voice · 1Password]") must never reach a file.
        let turns = await classic.thread.memoryTurns()
        guard turns.count > sessionStartTurns else { return }
        let fresh = Array(turns.dropFirst(sessionStartTurns))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let summary = MemorySummary.distill(
            turns: fresh, date: formatter.string(from: Date())) else { return }
        do {
            try memoryStore.appendSession(summary)
            Log.app("memory: session summary saved")
        } catch {
            Log.app("memory: summary write failed (\(error))")
        }
    }

    func openAIKey() -> String? {
        let value: String?
        do {
            value = try secrets.read(.openAI)
        } catch {
            Log.app("voice: OpenAI key unread")
            return nil
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
