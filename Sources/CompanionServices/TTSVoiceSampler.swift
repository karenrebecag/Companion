import CompanionCore
import Foundation

/// Fetches a sample with the chat audio endpoint and plays it. Deliberately
/// separate from the realtime path: a preview must never touch a live session.
public struct TTSVoiceSampler: VoiceSampling {
    private let fetcher: any TTSFetching
    private let playback: any SpeechPlayback

    public init(fetcher: any TTSFetching, playback: any SpeechPlayback) {
        self.fetcher = fetcher
        self.playback = playback
    }

    public func play(_ text: String, voice: VoiceID) async throws {
        let audio = try await fetcher.fetch(text, voice: voice)
        try await playback.play(audio)
    }
}
