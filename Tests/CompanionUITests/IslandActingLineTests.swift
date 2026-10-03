import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Testing

// K9 (brief isla-ciclo-y-legibilidad, Karen): while it acts, the line reads
// as thinking and names no app; the app lives in the reel (K8).

@Test @MainActor func actingReadsAsThinking() {
    expectEq(IslandCopy.line(.acting(["Safari"])), IslandCopy.line(.thinking), "K9: actuar dice pensando")
    expectEq(IslandCopy.line(.acting([])), IslandCopy.line(.thinking), "K9: sin objetivos, igual")
}

@Test @MainActor func actingNamesNoApp() {
    expect(!IslandCopy.line(.acting(["Safari", "Notas"])).contains("Safari"), "K9: la linea no nombra la app")
}

@Test @MainActor func thinkingIntoActingDoesNotSwap() {
    expectEq(IslandCopy.swapKey(.acting(["Safari"])), IslandCopy.swapKey(.thinking),
             "K9: la misma palabra no sale y vuelve a entrar")
    expect(IslandCopy.swapKey(.acting(["Safari"])) != IslandCopy.swapKey(.speaking),
           "K9: pasar a hablar si cambia")
}
