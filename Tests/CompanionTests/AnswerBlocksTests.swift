import CompanionCore
import Foundation
import Testing

// Wave 16m-1: the rich answer popup paints typed blocks, and which markdown
// becomes which block is contract, not styling — Incredible's ovx catalog
// has blocks (tasks, callout, file chip, eyebrow) that our splitter does not
// name, so the derivation lives in Core and is pinned here before any view.

@Test func answerBlocksTests() {
    testHeadingLevelsMapToTitleSectionEyebrow()
    testTaskListSplitsFromPlainList()
    testCalloutDerivesFromBoldLeadQuote()
    testFileChipDerivesFromLoneInlinePath()
    testDataFencesBecomeCards()
    testRichnessDecidesThePopup()
}

func testHeadingLevelsMapToTitleSectionEyebrow() {
    let blocks = AnswerBlocks.blocks(from: """
    # Informe
    ## Detalle
    ### CONTEXTO
    un párrafo
    """)
    expectEq(blocks, [
        .title("Informe"), .section("Detalle"), .eyebrow("CONTEXTO"),
        .paragraph("un párrafo"),
    ], "16m-1: h1/h2 con peso propio, h3 funciona como eyebrow")
}

func testTaskListSplitsFromPlainList() {
    let tasks = AnswerBlocks.blocks(from: """
    - [x] mandar el invite
    - [ ] revisar el hilo
    """)
    expectEq(tasks, [.tasks([
        TaskLine(done: true, text: "mandar el invite"),
        TaskLine(done: false, text: "revisar el hilo"),
    ])], "16m-1: las casillas son tareas, no viñetas")

    let plain = AnswerBlocks.blocks(from: "- uno\n- dos")
    expectEq(plain, [.list(ordered: false, items: [
        MarkdownSplitter.Item(depth: 0, text: "uno"),
        MarkdownSplitter.Item(depth: 0, text: "dos"),
    ])], "16m-1: una lista sin casillas sigue siendo lista")

    // One checkbox does not convert its plain siblings: mixed stays a list.
    let mixed = AnswerBlocks.blocks(from: "- [x] hecha\n- suelta")
    expectEq(mixed.count, 1, "16m-1: mixta no se parte")
    if case .list = mixed[0] {} else {
        expect(false, "16m-1: mixta cae a lista, nunca inventa casillas")
    }
}

func testCalloutDerivesFromBoldLeadQuote() {
    let callout = AnswerBlocks.blocks(from: "> **Ojo:** el deploy es de Karen")
    expectEq(callout, [.callout(title: "Ojo", body: "el deploy es de Karen")],
             "16m-1: cita con titular en negrita = callout")

    let quote = AnswerBlocks.blocks(from: "> lo dijo la spec")
    expectEq(quote, [.quote("lo dijo la spec")],
             "16m-1: cita sin titular sigue siendo cita")
}

func testFileChipDerivesFromLoneInlinePath() {
    expectEq(AnswerBlocks.blocks(from: "`Sources/CompanionCore/Log.swift`"),
             [.fileChip("Sources/CompanionCore/Log.swift")],
             "16m-1: una línea que es solo una ruta en código = chip de archivo")
    expectEq(AnswerBlocks.blocks(from: "usa `Log.app` para eso"),
             [.paragraph("usa `Log.app` para eso")],
             "16m-1: código en línea dentro de prosa no es chip")
    expectEq(AnswerBlocks.blocks(from: "`hola mundo`"),
             [.paragraph("`hola mundo`")],
             "16m-1: código en línea con espacios no es una ruta")
}

func testDataFencesBecomeCards() {
    let md = "```companion:stats\n{\"items\":[{\"label\":\"Total\",\"value\":\"51 KB\"}]}\n```"
    let blocks = AnswerBlocks.blocks(from: md)
    expectEq(blocks.count, 1, "16m-1: la fence es un bloque")
    if case .card = blocks[0] {} else {
        expect(false, "16m-1: companion:stats llega como tarjeta, no como código")
    }
    // A broken fence stays visible as code, same rule as the window.
    let broken = AnswerBlocks.blocks(from: "```companion:stats\n{rot\n```")
    if case .code = broken[0] {} else {
        expect(false, "16m-1: la fence rota se queda como código a la vista")
    }

    // Security review 16m: a gallery card loads model-supplied paths and
    // URLs at RENDER time, with no click — in an overlay above every app
    // that is a zero-click beacon. Until CompanionBlocks validates the
    // gallery (https-only, path allowlist), the popup shows the fence as
    // code, never as the card.
    let gallery = AnswerBlocks.blocks(from:
        "```companion:gallery\n{\"items\":[{\"path\":\"/etc/passwd\"}]}\n```")
    if case .code = gallery[0] {} else {
        expect(false, "16m-1: la fence de galería NO es tarjeta en el popup")
    }
}

func testRichnessDecidesThePopup() {
    // D2 (spec §5): a short phrase never opens the popup.
    expect(!AnswerBlocks.isRich(AnswerBlocks.blocks(from: "Listo, ya quedó.")),
           "16m-1: una frase corta no abre popup")
    expect(AnswerBlocks.isRich(AnswerBlocks.blocks(from: "# T\ncuerpo")),
           "16m-1: un título ya es contenido rico")
    expect(AnswerBlocks.isRich(AnswerBlocks.blocks(from: "| a | b |\n|---|---|\n| 1 | 2 |")),
           "16m-1: una tabla es contenido rico")
    let long = String(repeating: "palabra ", count: 40)
    expect(AnswerBlocks.isRich(AnswerBlocks.blocks(from: long)),
           "16m-1: un párrafo más largo que el resumen de la tarjeta es rico")
    expect(!AnswerBlocks.isRich(AnswerBlocks.blocks(from: "uno\n\ndos")),
           "16m-1: dos frases cortas siguen sin abrir popup")
}
