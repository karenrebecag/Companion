import CompanionCore
import Foundation
import Observation

@Observable
@MainActor
public final class VoicePreview {
    public private(set) var playing: VoiceID?
    public private(set) var errorText: String?
    /// 15f-6: a sample through the hold's own mouth is playing.
    public private(set) var playingMouth = false

    private let sampler: any VoiceSampling
    /// 15f-6: the hold's mouth (ElevenLabs with key and voice, OpenAI
    /// otherwise), so the preview sounds like what the hold will say.
    private let mouth: (any VoiceSampling)?

    public init(sampler: any VoiceSampling, mouth: (any VoiceSampling)? = nil) {
        self.sampler = sampler
        self.mouth = mouth
    }

    public var isBusy: Bool { playing != nil || playingMouth }

    /// Short on purpose: a preview is for timbre, not for listening to a speech.
    public static let sampleText = Localized.string("voice.sample")

    public func play(_ voice: VoiceID) {
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
    public func playMouth(_ voice: VoiceID) {
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
