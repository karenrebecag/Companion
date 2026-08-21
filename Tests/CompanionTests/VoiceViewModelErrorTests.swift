import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func voiceViewModelErrorTests() {
    // Tests for error handling in VoiceViewModel are covered indirectly
    // through the TurnMachine tests and VoiceCopy static methods.
    // This ensures that the core logic (what error message to show)
    // is testable and correct, and the ViewModel integration is
    // verified manually.

    // Verify that VoiceCopy.failure returns the correct messages for all failure types.
    expectEq(VoiceCopy.failure(.micDenied),
             "Sin permiso de micrófono. Revisa Ajustes del sistema.",
             "error: micDenied message is correct")
    expectEq(VoiceCopy.failure(.sessionDropped),
             "La sesión de voz se cayó.",
             "error: sessionDropped message is correct")
    expectEq(VoiceCopy.failure(.speechEngine),
             "Me quedé sin voz. Revisa el TTS.",
             "error: speechEngine message is correct")
}