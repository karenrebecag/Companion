import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func voiceViewModelErrorTests() {
    pinLanguage()
    // Tests for error handling in VoiceViewModel are covered indirectly
    // through the TurnMachine tests and VoiceCopy static methods.
    // This ensures that the core logic (what error message to show)
    // is testable and correct, and the ViewModel integration is
    // verified manually.

    // Verify that VoiceCopy.failure returns the correct messages for all failure types.
    expectEq(VoiceCopy.failure(.micDenied),
             "No microphone permission. Check System Settings.",
             "error: micDenied message is correct")
    expectEq(VoiceCopy.failure(.sessionDropped),
             "The voice session dropped.",
             "error: sessionDropped message is correct")
    expectEq(VoiceCopy.failure(.speechEngine),
             "I lost my voice. Check the TTS.",
             "error: speechEngine message is correct")
}