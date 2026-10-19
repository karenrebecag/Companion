import CompanionCore
import Foundation
import Observation

@Observable
@MainActor
package final class VoicePreview {
    /// A sample through the hold's own mouth is playing.
    package private(set) var playing = false
    package private(set) var errorText: String?

    /// The hold's mouth (ElevenLabs with key and voice, the system voice
    /// otherwise), so the preview sounds like what the hold will say.
    private let mouth: any VoiceSampling

    package init(mouth: any VoiceSampling) {
        self.mouth = mouth
    }

    package var isBusy: Bool { playing }

    /// Short on purpose: a preview is for timbre, not for listening to a speech.
    package static let sampleText = Localized.string("voice.sample")

    /// `voice` is passed through to the mouth; neither mouth reads it today.
    package func play(_ voice: VoiceID) {
        guard !isBusy else { return }
        playing = true
        errorText = nil
        Task {
            do {
                try await mouth.play(Self.sampleText, voice: voice)
            } catch {
                errorText = VoiceCopy.previewFailed
            }
            playing = false
        }
    }
}
