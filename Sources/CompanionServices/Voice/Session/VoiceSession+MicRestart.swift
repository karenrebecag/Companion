import CompanionCore
import Foundation

/// The mic can move itself to another input while a session is open (the
/// chosen one was unplugged). With echo cancellation that means a new engine,
/// and the player was attached to the old one: it has to follow, or the agent
/// goes mute for the rest of the session.
extension VoiceSession {
    func watchMicRestarts() {
        micRestartTask?.cancel()
        let restarts = mic.subscribeRestarts()
        micRestartTask = Task { [weak self] in
            for await event in restarts {
                if Task.isCancelled { return }
                await self?.micRestarted(event)
            }
        }
    }

    func stopWatchingMicRestarts() {
        micRestartTask?.cancel()
        micRestartTask = nil
    }

    private func micRestarted(_ event: MicRestart) async {
        guard !voiceClosed else { return }
        switch event {
        case .restarted(let echoCancellation):
            do {
                try await player.start(sharedEngine: echoCancellation)
            } catch {
                await apply(.turnFailed(.micUnavailable))
            }
        case .failed:
            await apply(.turnFailed(.micUnavailable))
        }
    }
}
