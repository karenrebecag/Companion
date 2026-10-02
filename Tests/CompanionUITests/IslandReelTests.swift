import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Testing

// K8 (brief isla-ciclo-y-legibilidad, signed by Karen): the reel painted one
// chip per touched app, an empty one included. Incredible's reel shows one
// item, the latest, and swaps it in after its own delay.

@Test @MainActor func theReelShowsOnlyTheLatestApp() {
    expectEq(IslandReel.item(["Slack", "Safari"]), "Safari", "un solo item: el último")
    expectEq(IslandReel.item(["Notes"]), "Notes", "con uno, ese")
}

@Test @MainActor func theReelNeverShowsAnEmptyItem() {
    expect(IslandReel.item([]) == nil, "sin apps tocadas, sin carrete")
    expect(IslandReel.item([""]) == nil, "un destino vacío no es un item")
    expect(IslandReel.item(["  "]) == nil, "ni uno de puros espacios")
    expectEq(IslandReel.item(["Slack", ""]), "Slack", "un vacío al final no tapa al anterior")
}

@Test @MainActor func theReelSwapsAtIncrediblesDelay() {
    expectEq(MotionTime.reelSwap, 0.65, "el cambio de item entra a los 650 ms (referencia local)")
}
