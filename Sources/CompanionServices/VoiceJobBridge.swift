import CompanionCore
import Foundation

/// Delegation from a voice turn. Lives apart from VoiceSession so the session
/// stays about the turn and this stays about the job.
enum VoiceJobBridge {
    /// Runs the specialist off the voice turn: the conversation must not
    /// stall while a job works, and its answer lands in the shared thread.
    static func run(
        _ handoff: Handoff,
        jobs: any JobSubmitter,
        thread: any ConversationPresenting
    ) async {
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let drain = Task { for await _ in stream {} }
        defer { drain.cancel() }
        do {
            let result = try await jobs.submit(handoff, events: sink)
            sink.finish()
            await thread.appendAssistant(result.output)
        } catch {
            sink.finish()
            Log.app("voice: job failed")
            await thread.appendStatus("El encargo no se pudo completar.")
        }
    }

}
