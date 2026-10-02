import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Testing

// K10 (brief isla-ciclo-y-legibilidad, Karen): no visible "Hablando" while
// the agent speaks, and VoiceOver keeps hearing it.

@Test @MainActor func speakingPaintsNoWords() {
    expect(IslandCopy.visibleLine(.speaking) == nil, "K10: hablando no pinta etiqueta")
}

@Test @MainActor func otherLinesKeepTheirWords() {
    let lines: [IslandState.Line] = [.thinking, .pending, .completed, .cancelled, .acting(["Safari"])]
    for line in lines {
        expectEq(IslandCopy.visibleLine(line), IslandCopy.line(line), "K10: \(line) conserva su texto")
    }
}

@Test @MainActor func voiceOverStillHearsSpeaking() {
    expect(IslandCopy.voiceOverOnly(.speaking), "K10: VoiceOver conserva hablando")
    let label = IslandCopy.line(.speaking)
    expect(!label.isEmpty && label != "island.speaking", "K10: VoiceOver lee la frase del catalogo, no la clave")
    expectEq(IslandCopy.visibleLine(.none), IslandCopy.line(.none), "K10: sin linea no se trata como hablando")
    expect(!IslandCopy.voiceOverOnly(.none), "K10: sin linea no hay nada que leer")
    expect(!IslandCopy.voiceOverOnly(.thinking), "K10: pensando ya se pinta")
}
