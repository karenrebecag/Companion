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
             "I lost my voice. Try again in a moment.",
             "error: speechEngine message is correct")

    // Un permiso negado se arregla en Ajustes del sistema, no en el TTS.
    let denied = VoiceCopy.failure(.speechDenied)
    expect(denied.contains("System Settings"),
           "error: speechDenied manda a donde se concede el permiso")
    expect(!denied.contains("TTS"),
           "error: speechDenied no culpa a la síntesis de voz")
}