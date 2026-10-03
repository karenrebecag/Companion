import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
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

// Security review #212: the item is a target the model chose. Control, bidi
// and zero-width characters could hide text from the eye or from VoiceOver,
// and an unbounded one would read on and on.
@Test @MainActor func theReelItemDropsInvisibleCharacters() {
    expectEq(IslandReel.item(["Safa\u{202E}ri"]), "Safari", "sin overrides bidi")
    expectEq(IslandReel.item(["Sa\u{200B}fa\u{2060}ri"]), "Safari", "sin caracteres de ancho cero")
    expectEq(IslandReel.item(["Safari\nNotas\u{0007}"]), "Safari Notas", "un salto separa palabras; los demas controles se van")
    expectEq(IslandReel.item(["Safa\u{2028}ri\u{2029}Notas"]), "Safa ri Notas", "separadores de linea y parrafo son espacios")
    expectEq(IslandReel.item(["  Safari \t  Notas  "]), "Safari Notas", "los espacios se juntan y se recortan")
    for blank in ["\u{2028}", "\u{3164}", "\u{2800}", "\u{115F}", "\u{17B4}", "\u{FFA0}"] {
        expect(IslandReel.item([blank]) == nil, "un glifo en blanco solo no es un item")
    }
    // Accepted: a ZWJ sequence falls apart into its emoji, ZWNJ and
    // variation selectors go too; app names and URLs do not need them, and
    // each can hide text.
    expect(IslandReel.item(["\u{1F468}\u{200D}\u{1F469}"]) == "\u{1F468}\u{1F469}", "el ZWJ se va")
    expect(IslandReel.item(["\u{200B}\u{202E}"]) == nil, "solo invisibles no es un item")
    expectEq(IslandReel.item(["Notas", "\u{200B}"]), "Notas", "un invisible al final no tapa al anterior")
}

@Test @MainActor func theReelItemIsBounded() {
    let max = WorkStateMetrics.reelItemMax
    let a = { (n: Int) in String(repeating: "a", count: n) }
    expectEq(IslandReel.item([a(max - 1)]), a(max - 1), "uno menos que el tope no cambia")
    expectEq(IslandReel.item([a(max)]), a(max), "justo en el tope no se corta")
    expectEq(IslandReel.item([a(max + 1)]), a(max - 1) + "…", "uno mas se corta y lo dice")
    expectEq(IslandReel.item([a(200)]), a(max - 1) + "…", "uno largo tambien")
    expectEq(IslandReel.item([a(max - 2) + " bcd"]), a(max - 2) + "…", "el corte no deja un espacio antes de los puntos")
    expectEq(IslandReel.item([String(repeating: "\u{200B}", count: 300) + "Safari"]), "Safari",
             "los invisibles no gastan el tope")
}

@Test @MainActor func theReelItemBoundsCombiningMarks() {
    let zalgo = "a" + String(repeating: "\u{0301}", count: 5000)
    let item = IslandReel.item([zalgo]) ?? ""
    expect(item.unicodeScalars.count <= WorkStateMetrics.reelItemMax * 4, "las marcas combinantes tambien tienen tope")
    let family = String(repeating: "a", count: WorkStateMetrics.reelItemMax - 2) + "\u{1F1F2}\u{1F1FD}bb"
    let cut = IslandReel.item([family]) ?? ""
    expect(cut.hasSuffix("\u{1F1F2}\u{1F1FD}…"), "el corte no parte una bandera")
}

// Code review: the budget must stop the scan, not just the output; the item
// is recomputed on every render of the island.
@Test @MainActor func aHugeNameStopsAtTheBudget() {
    let huge = String(repeating: "a", count: 2_000_000)
    let start = Date()
    let item = IslandReel.item([huge]) ?? ""
    // The cut scans about 240 scalars; a full walk of 2M takes about a second.
    expect(Date().timeIntervalSince(start) < 0.5, "un nombre enorme se corta sin recorrerlo entero")
    expectEq(item.count, WorkStateMetrics.reelItemMax, "y sale con el tope")
}

// Security review K9: with the line saying "Pensando", VoiceOver must hear
// the app from the reel; its fixed label used to hide the chip's text.
@Test @MainActor func voiceOverHearsTheAppInTheReel() {
    let spoken = IslandReel.spoken("Safari")
    expectEq(spoken.value, "Safari", "VoiceOver lee la app del carrete")
    expect(!spoken.label.isEmpty && spoken.label != "island.reel", "y conserva el nombre de la banda, no la clave")
    expectEq(IslandReel.spoken("Notes").value, "Notes", "el valor sigue al item, no queda fijo")
}
