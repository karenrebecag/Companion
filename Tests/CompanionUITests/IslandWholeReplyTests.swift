import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import SwiftUI
import Testing

// Brief isla-maquetacion-incredible, F2 (and K5 of isla-ciclo-y-legibilidad):
// the island cut the reply to its first paragraph and 240 characters with
// "…". Now it shows the whole spoken reply, every paragraph, up to its last
// `wordCap` words, in a column that scrolls only past its height cap.

@Test @MainActor func aLongReplyIsShownWhole() {
    let first = String(repeating: "uno dos tres cuatro cinco ", count: 20)
    let second = String(repeating: "seis siete ocho nueve diez ", count: 20)
    let reply = first + "\n\n" + second
    expect(reply.count > 500, "la respuesta pasa de los 240 de antes")
    let shown = IslandReplyText.spoken(from: reply)
    expect(!shown.contains("…"), "sin corte con elipsis")
    expect(shown.hasPrefix("uno dos"), "el primer párrafo")
    expect(shown.hasSuffix("nueve diez"), "y el último")
    expect(shown.contains("\n\n"), "los párrafos siguen separados")
}

@Test @MainActor func pastTheCapOnlyTheLastWordsAreShown() {
    let words = (1...(IslandReplyText.wordCap + 100)).map { "w\($0)" }
    let shown = IslandReplyText.spoken(from: words.joined(separator: " "))
    let kept = shown.split(whereSeparator: \.isWhitespace)
    expectEq(kept.count, IslandReplyText.wordCap, "solo el tope de palabras")
    expectEq(kept.first.map(String.init), "w101", "se van las primeras")
    expectEq(kept.last.map(String.init), "w\(IslandReplyText.wordCap + 100)", "se queda la última")
}

@Test @MainActor func theWordCapIsExactAtItsBoundary() {
    let cap = IslandReplyText.wordCap
    let atCap = IslandReplyText.spoken(from: (1...cap).map { "w\($0)" }.joined(separator: " "))
        .split(whereSeparator: \.isWhitespace)
    expectEq(atCap.count, cap, "justo en el tope no se pierde ninguna")
    expectEq(atCap.first.map(String.init), "w1", "y la primera sigue")
    let pastCap = IslandReplyText.spoken(from: (1...(cap + 1)).map { "w\($0)" }.joined(separator: " "))
        .split(whereSeparator: \.isWhitespace)
    expectEq(pastCap.count, cap, "una de más: se va una")
    expectEq(pastCap.first.map(String.init), "w2", "la que se va es la primera")
    expectEq(pastCap.last.map(String.init), "w\(cap + 1)", "y la última se queda")
}

@Test @MainActor func theKeptTailKeepsItsParagraphs() {
    let cap = IslandReplyText.wordCap
    let head = (1...cap).map { "a\($0)" }.joined(separator: " ")
    let shown = IslandReplyText.spoken(from: head + "\n\nfin del todo")
    expect(shown.hasSuffix("\n\nfin del todo"), "el corte por palabras no aplana los párrafos")
}

@Test @MainActor func aWholeMarkedUpReplyFitsTheWindow() {
    // Markup makes 600 words longer than 600 plain ones; the window must
    // still reach the last word, or the cap is never what the island shows.
    let reply = (1...IslandReplyText.wordCap).map { "**w\($0)**" }.joined(separator: " ")
    let shown = IslandReplyText.spoken(from: reply)
    expect(shown.hasSuffix("w\(IslandReplyText.wordCap)"), "la última palabra marcada llega a la isla")
}

@Test @MainActor func codeIsNotSpokenSoTheIslandSkipsIt() {
    let reply = "Así se hace:\n\n```swift\nlet a = 1\n```\n\nY listo."
    expectEq(IslandReplyText.spoken(from: reply), "Así se hace:\n\nY listo.", "el bloque de código no se pinta")
}

@Test @MainActor func codeInEveryShapeStaysOff() {
    expectEq(IslandReplyText.spoken(from: "```\nlet a = 1\n```"), "", "solo código: nada")
    expectEq(IslandReplyText.spoken(from: "Mira:\n\n```swift\nlet a = 1\nlet b"), "Mira:",
             "un bloque que aún no cierra (streaming) no se asoma")
    expectEq(IslandReplyText.spoken(from: "Uno\n\n```\na\n```\n\nDos\n\n```\nb\n```\n\nTres"),
             "Uno\n\nDos\n\nTres", "dos bloques")
    expectEq(IslandReplyText.spoken(from: "antes```x```después"), "antes\n\ndespués",
             "pegado a palabras no las junta")
}

@Test @MainActor func strayBracketsCostLinearWork() {
    // The whole window is one paragraph now; a search that rescans the rest
    // per stray "[" froze the island for half a second (security review F2).
    let floods = [String(repeating: "[", count: 8_000),
                  String(repeating: "[a](", count: 2_000),
                  "[" + String(repeating: "](", count: 4_000)]
    for flood in floods {
        let start = Date()
        _ = IslandReplyText.spoken(from: flood)
        expect(Date().timeIntervalSince(start) < 0.2, "corchetes sueltos: acotado")
    }
    expectEq(IslandReplyText.spoken(from: "ve [aquí](https://x.y/a b) y [ya]"), "ve aquí y [ya]",
             "un enlace sigue leyendo su etiqueta")
}

@Test @MainActor func theColumnFitsUnderTheCanvas() {
    for band: CGFloat in [24, 32, 38] {
        let column = IslandChrome.columnMaxHeight(bandHeight: band)
        expect(column > 0 && column <= IslandChrome.columnCap, "banda \(band): bajo el tope de la columna")
        let open = band + IslandChrome.columnGaps + column
        expect(open <= IslandChrome.canvasHeight - IslandChrome.shadowRoom,
               "banda \(band): la columna entera cabe en la forma (\(open))")
    }
}

@MainActor private func columnHeight<V: View>(_ content: V, cap: CGFloat) -> CGFloat {
    let view = IslandColumn(maxHeight: cap) { content }.frame(width: 460)
    return NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: 460, height: 10_000)).height
}

// An unhosted controller never fires `onGeometryChange`, so this pins the
// hug branch and its first-frame clamp; the ScrollView branch is not reached.
@Test @MainActor func theColumnHugsShortContentAndStopsAtItsCap() {
    expectEq(columnHeight(Color.clear.frame(height: 80), cap: 300), 80, "corta: mide lo suyo, sin scroll")
    expectEq(columnHeight(Color.clear.frame(height: 2_000), cap: 300), 300, "larga: el tope")
}
