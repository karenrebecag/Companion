import CompanionCore
import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

// The result document's logic apart from the view: which blocks a reply
// leaves it, how the blocks space themselves, how the shape sizes for it.

@Test @MainActor func testTheDocumentKeepsTheRepliesStructureAndLetsTheSourcesTravelAsChips() {
    let reply = """
    Webflow publica en el CDN.

    - Exporta los slugs
    - Prepara las redirecciones

    | Paso | Tiempo |
    | --- | --- |
    | Inventario | 1 dia |

    ## Fuentes

    - [Docs](https://webflow.com/docs)
    """
    let document = IslandResultCardModel.document(of: reply)
    expectEq(document.sources.map(\.url), ["https://webflow.com/docs"], "documento: la fuente sale como chip")
    let kinds = document.blocks.map { block -> String in
        switch block {
        case .paragraph: "p"
        case .list: "list"
        case .table: "table"
        default: "other"
        }
    }
    expectEq(kinds, ["p", "list", "table"], "documento: parrafo, vinetas y tabla; sin la lista de fuentes")
}

@Test @MainActor func testTheDocumentLeavesTheCardsAndFencesToTheInlineVisualsAndTheChoiceToItsOwnCard() {
    let reply = """
    Aqui va.

    ```companion:choice
    {"question":"Cual?","options":["A","B"]}
    ```

    ```companion:chart
    {"title":"Reuniones","kind":"radar","labels":["a","b","c"],"series":[{"name":"x","values":[3,5,4]}]}
    ```
    """
    let document = IslandResultCardModel.document(of: reply)
    expectEq(document.blocks.count, 1, "documento: solo la prosa, la eleccion y la grafica se pintan aparte")
}

@Test @MainActor func testAParagraphWithOnlyAModelTagIsDroppedNotPaintedEmpty() {
    let document = IslandResultCardModel.document(of: "<steer>nota interna</steer>\n\nLa respuesta.")
    expectEq(document.blocks, [.paragraph("La respuesta.")], "documento: la etiqueta interna no se pinta")
}

@Test @MainActor func testBlockMarginsCollapseToTheLargerOfTheTwoSides() {
    let paragraph = AnswerBlock.paragraph("a")
    let list = AnswerBlock.list(ordered: false, items: [MarkdownSplitter.Item(depth: 0, text: "x")])
    let table = AnswerBlock.table(headers: ["h"], rows: [["c"]])
    let section = AnswerBlock.section("S")
    expectEq(IslandDocProse.gap(between: paragraph, and: paragraph), DocCardMetrics.paragraphGap, "margenes: parrafo a parrafo")
    expectEq(IslandDocProse.gap(between: paragraph, and: list), DocCardMetrics.paragraphGap,
             "margenes: la lista pide menos antes que lo que el parrafo deja despues")
    expectEq(IslandDocProse.gap(between: list, and: paragraph), DocCardMetrics.listGapAfter, "margenes: despues de una lista")
    expectEq(IslandDocProse.gap(between: table, and: paragraph), DocCardMetrics.tableGapAfter, "margenes: despues de una tabla")
    expectEq(IslandDocProse.gap(between: paragraph, and: section), DocCardMetrics.headingGapBefore,
             "margenes: un titulo pide mas que lo que deja el parrafo")
}

@Test @MainActor func testBlocksFadeInOneAfterAnotherAndTheLastDelayHolds() {
    expectEq(DocCardMotion.delay(at: 0), DocCardMotion.firstDelay, "escalon: el primero")
    expect(DocCardMotion.delay(at: 1) < DocCardMotion.delay(at: 2), "escalon: cada bloque llega despues")
    expectEq(DocCardMotion.delay(at: 40), DocCardMotion.delays.last, "escalon: del quinto en adelante, el mismo")
}

@Test @MainActor func testTheDocumentShapeIsTheCardPlusTheShellMarginAndFitsTheCanvas() {
    let notch = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 945,
        safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662))
    expectEq(IslandChrome.width(for: .docCard, notch: notch), DocCardMetrics.width + 2 * IslandChrome.shellMargin,
             "documento: el ancho de la tarjeta mas el margen del cascaron")
    expect(IslandChrome.canvasWidth >= IslandChrome.docCardWidth + 2 * Space.x5, "documento: el lienzo lo aloja con su sombra")
}

@Test @MainActor func testAReceiptNoticeOpensTheDocumentShapeButAnUndoRowKeepsTheNarrowCard() {
    var projection = SessionProjection()
    projection.notice = .receipt(ActionReceipt(lines: ["Abri Safari."])!)
    expectEq(IslandState.from(projection, pebbleHidden: false).size, .docCard, "recibo: el documento es ancho")
    projection.kind = .processing(.completed)
    projection.receipt = UndoReceipt(kind: .created, subject: "plan.md")
    expectEq(IslandState.from(projection, pebbleHidden: false).size, .card,
             "recibo: la fila de deshacer vive en la columna angosta")
}

@Test @MainActor func testALedgerRowSaysDoneOrVerifiedInOneShortWord() {
    expectEq(IslandReceipt.pillLabel(ReceiptLine(text: "x", verified: true), language: .es), "Verificado", "pildora: comprobado")
    expectEq(IslandReceipt.pillLabel(ReceiptLine(text: "x", verified: false), language: .en), "Done", "pildora: hecho")
}
