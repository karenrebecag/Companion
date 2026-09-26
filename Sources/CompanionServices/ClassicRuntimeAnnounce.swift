import CompanionCore
import Foundation

/// Code review 2026-09-25 (HIGH-B): the end of a job in classic mode. The
/// synthesizer used to receive the model-facing instruction verbatim; now
/// the voice says a fixed line of our own and then a summary the hold
/// brain writes in a turn of its own, through the same `TurnMouth` as any
/// reply — the JSON guard and the language gate included.
extension ClassicRuntime {
    func announce(_ announcement: JobAnnouncement) async {
        let language = announcement.language
        await synthesizer.begin()
        // The fixed line is in the app language, so it is also the gate's
        // evidence for the summary that follows.
        var mouth = TurnMouth(
            language: language, recognizer: languageRecognizer, heard: announcement.spokenLine)
        await say(announcement.spokenLine, &mouth)
        if let source = announcement.summarySource {
            await summarize(source, language: language, &mouth)
        }
        if Task.isCancelled { return }
        if let rest = mouth.buffer.drain() { await say(rest, &mouth) }
        await synthesizer.finish()
    }

    /// No tools and no thread: the summary is spoken, never threaded — the
    /// specialist's own text is already the assistant message.
    private func summarize(_ source: String, language: AppLanguage, _ mouth: inout TurnMouth) async {
        let request = Turn(role: .user, content: Escalation.summaryRequest(source, language))
        do {
            for try await delta in chat.stream([request], tools: []) {
                if Task.isCancelled { return }
                guard case .text(let raw) = delta else { continue }
                await speak(mouth.json.feed(raw), &mouth)
            }
        } catch {
            Log.app("voice: job summary failed")
        }
        if Task.isCancelled { return }
        await speak(mouth.json.finish(), &mouth)
    }

    /// A goal object in a summary is never a proposal: nobody asked for
    /// anything, so it is only counted and dropped.
    private func speak(_ step: HandoffInText.Step, _ mouth: inout TurnMouth) async {
        let dropped = step.droppedChars + (step.handoff == nil ? 0 : step.handoffChars)
        if dropped > 0 { Log.app("mouth: dropped reason=json chars=\(dropped)") }
        guard !step.speakable.isEmpty else { return }
        mouth.spoken += step.speakable
        for sentence in mouth.buffer.append(step.speakable) {
            if Task.isCancelled { return }
            await say(sentence, &mouth)
        }
    }
}
