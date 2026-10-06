import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// The composer's mark is Arc's voice orb: it speaks with the voice coming
// back and never with the mic, so the user's own voice never looks like the
// assistant's. The orb swells with the level by itself.

@Test @MainActor func theComposerOrbSpeaksWithTheVoice() {
    expectEq(VoiceOrbState.composer(levels: VoiceLevels(mic: 0, agent: 0)), .idle, "en silencio: reposo")
    expectEq(VoiceOrbState.composer(levels: VoiceLevels(mic: 0, agent: 0.6)), .speaking, "la voz: habla")
}

// QA review: the headline rule lives in which level the orb reads.
@Test @MainActor func theComposerOrbReadsTheVoiceNotTheMic() {
    expectEq(VoiceOrbState.composer(levels: VoiceLevels(mic: 1, agent: 0)), .idle, "el microfono no lo mueve")
}

@Test @MainActor func aBrokenLevelLeavesTheComposerOrbAtRest() {
    expectEq(VoiceOrbState.composer(levels: VoiceLevels(mic: 0, agent: .nan)), .idle, "nan: reposo")
    expectEq(VoiceOrbState.composer(levels: VoiceLevels(mic: 0, agent: -.infinity)), .idle, "menos infinito: reposo")
    expectEq(VoiceOrbState.composer(levels: VoiceLevels(mic: 0, agent: VoiceOrbState.speechFloor)), .idle,
             "en el umbral todavia es silencio")
}
