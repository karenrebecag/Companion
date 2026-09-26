import CompanionCore
import Foundation

/// Wave 15b-4/15b-5: what a fresh press starts in parallel with the mic —
/// warming the voice ahead of the first reply, and sensing context ahead of
/// the commit. Split out of `VoiceSession` — the actor is at the 800-line
/// gate (Wave DM0) and this delivery must not add to it — the same pattern
/// `VoiceSessionTimeline` already uses: not `private`, but still
/// actor-isolated by the actor itself, not by access level.
extension VoiceSession {
    /// Called once per fresh press (never a bounce, `hold()`'s own guard).
    func fanOut() {
        // 15b-5: sensing does not need the OpenAI key — a classic-only hold
        // still benefits from context read at press instead of at commit.
        let sensor = classic.sensor
        let config = configProvider.current
        // Code review 2026-09-23 (medio): a hold that ends without ever
        // reading its sense (silence, or dictation that never submits)
        // left the previous press's Task orphaned — this reassignment
        // dropped its only reference instead of cancelling it.
        classic.cancelPressedContext()
        classic.pressedContext = Task {
            await sensor?.sense(config.contextChannels, budget: config.contextBudget)
        }
        // The classic (no-key) path has no TTS endpoint to warm.
        guard openAIKey() != nil else { return }
        let synth = synthesizer
        let language = config.language
        Task.detached { await synth.prewarm(DecisionCopy.prewarmSet(language)) }
        Task.detached { await synth.warmConnection() }
    }
}
