import CompanionCore
import Foundation
import Observation

@Observable
@MainActor
package final class VoicePreview {
    package private(set) var playing: VoiceID?
    package private(set) var errorText: String?
    /// 15f-6: a sample through the hold's own mouth is playing.
    package private(set) var playingMouth = false

    private let sampler: any VoiceSampling
    /// 15f-6: the hold's mouth (ElevenLabs with key and voice, OpenAI
    /// otherwise), so the preview sounds like what the hold will say.
    private let mouth: (any VoiceSampling)?

    package init(sampler: any VoiceSampling, mouth: (any VoiceSampling)? = nil) {
        self.sampler = sampler
        self.mouth = mouth
    }

    package var isBusy: Bool { playing != nil || playingMouth }

    /// Short on purpose: a preview is for timbre, not for listening to a speech.
    package static let sampleText = Localized.string("voice.sample")

    package func play(_ voice: VoiceID) {
        guard !isBusy else { return }
        playing = voice
        errorText = nil
        Task { [sampler] in
            do {
                try await sampler.play(Self.sampleText, voice: voice)
            } catch {
                errorText = VoiceCopy.previewFailed
            }
            playing = nil
        }
    }

    /// `voice` is the OpenAI voice the mouth falls back to.
    package func playMouth(_ voice: VoiceID) {
        guard !isBusy, let mouth else { return }
        playingMouth = true
        errorText = nil
        Task {
            do {
                try await mouth.play(Self.sampleText, voice: voice)
            } catch {
                errorText = VoiceCopy.previewFailed
            }
            playingMouth = false
        }
    }
}
