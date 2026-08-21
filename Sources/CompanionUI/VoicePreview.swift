import CompanionCore
import Foundation
import Observation

@Observable
@MainActor
public final class VoicePreview {
    public private(set) var playing: VoiceID?
    public private(set) var errorText: String?

    private let sampler: any VoiceSampling

    public init(sampler: any VoiceSampling) {
        self.sampler = sampler
    }

    /// Short on purpose: a preview is for timbre, not for listening to a speech.
    public static let sampleText = "Hola, soy Companion. Así sueno."

    public func play(_ voice: VoiceID) {
        guard playing == nil else { return }
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
}
