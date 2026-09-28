import CompanionCore
import Foundation
import Testing

// Wave 20-2 (spec 20 §4 D4, §6.4-5): the model sends blocks, never HTML; the
// template escapes everything and draws charts as inline SVG.

@Test func documentSpecTests() {
    testASpecParsesItsBlocks()
    testASpecArrivesAsAStringOrAnObject()
    testUnknownBlocksAreSkippedNotFatal()
    testASpecIsBounded()
    testEveryTextIsEscaped()
    testTheHTMLHasNoScriptAndNoRemoteReference()
    testChartsBecomeInlineSVG()
    testAChartWithNegativesAndOnePointStillDraws()
    testTheFormatComesFromThePath()
}

private let sample = """
{"title":"Informe Q3","subtitle":"Ventas LATAM","blocks":[
 {"type":"cover","title":"Informe Q3","subtitle":"Ventas","date":"28 sep 2026"},
 {"type":"heading","text":"Resumen","level":1},
 {"type":"paragraph","text":"Crecimos."},
 {"type":"bullets","items":["uno","dos"]},
 {"type":"stats","items":[{"label":"Total","value":"$12k","delta":"+8 %"}]},
 {"type":"table","columns":["País","Ventas"],"rows":[["MX",10],["CO",7]]},
 {"type":"chart","kind":"bar","labels":["jul","ago"],"series":[{"name":"2026","values":[4,6]}]},
 {"type":"callout","text":"Ojo con agosto","tone":"warning"},
 {"type":"divider"}
]}
"""

func testASpecParsesItsBlocks() {
    guard let spec = DocumentSpec.parse(sample) else { return expect(false, "documento: parsea") }
    expectEq(spec.title, "Informe Q3", "documento: título")
    expectEq(spec.blocks.count, 9, "documento: nueve bloques")
    guard case .heading(let text, let level) = spec.blocks[1] else { return expect(false, "encabezado") }
    expectEq(text, "Resumen", "encabezado: texto")
    expectEq(level, 1, "encabezado: nivel")
    guard case .table(let table) = spec.blocks[5] else { return expect(false, "tabla") }
    expectEq(table.rows[1], ["CO", "7"], "tabla: reusa el parser de tarjetas")
    guard case .callout(_, let tone) = spec.blocks[7] else { return expect(false, "aviso") }
    expectEq(tone, .warning, "aviso: tono")
}

func testASpecArrivesAsAStringOrAnObject() {
    let object: [String: Any] = ["title": "X", "blocks": [["type": "paragraph", "text": "hola"]]]
    expectEq(DocumentSpec.parse(any: object)?.blocks.count, 1, "documento: acepta un objeto")
    expectEq(DocumentSpec.parse(any: #"{"title":"X","blocks":[{"type":"divider"}]}"#)?.blocks.count, 1,
             "documento: acepta un string con JSON")
    expect(DocumentSpec.parse(any: 42) == nil, "documento: un número no es un documento")
}

func testUnknownBlocksAreSkippedNotFatal() {
    let spec = DocumentSpec.parse(#"{"title":"X","blocks":[{"type":"video"},{"type":"paragraph","text":"a"}]}"#)
    expectEq(spec?.blocks.count, 1, "un bloque desconocido se salta; el documento sigue")
    expect(DocumentSpec.parse(#"{"title":"X","blocks":[]}"#) == nil, "sin bloques no hay documento")
    expect(DocumentSpec.parse(#"{"blocks":[{"type":"divider"}]}"#) == nil, "sin título no hay documento")
}

func testASpecIsBounded() {
    let many = (0..<400).map { _ in #"{"type":"divider"}"# }.joined(separator: ",")
    expectEq(DocumentSpec.parse(#"{"title":"X","blocks":[\#(many)]}"#)?.blocks.count, DocumentSpec.maxBlocks,
             "documento: tope de bloques")
    let long = String(repeating: "a", count: DocumentSpec.maxText + 100)
    guard case .paragraph(let text)? = DocumentSpec.parse(#"{"title":"X","blocks":[{"type":"paragraph","text":"\#(long)"}]}"#)?.blocks.first
    else { return expect(false, "párrafo largo: parsea") }
    expect(text.count <= DocumentSpec.maxText, "documento: un texto enorme se recorta")
}

func testEveryTextIsEscaped() {
    let hostile = #"{"title":"<script>alert(1)</script>","blocks":[{"type":"paragraph","text":"a & b <img src=x onerror=1>"},{"type":"table","columns":["\"><b>"],"rows":[["</td>"]]}]}"#
    guard let spec = DocumentSpec.parse(hostile) else { return expect(false, "hostil: parsea") }
    let html = DocumentHTML.render(spec)
    expect(!html.contains("<script>alert"), "HTML: un título con script sale escapado")
    expect(!html.contains("<img src=x"), "HTML: una etiqueta en un párrafo sale escapada")
    expect(html.contains("a &amp; b"), "HTML: el ampersand se escapa")
    expect(!html.contains("\"><b>"), "HTML: una comilla no cierra un atributo")
}

func testTheHTMLHasNoScriptAndNoRemoteReference() {
    guard let spec = DocumentSpec.parse(sample) else { return expect(false, "muestra: parsea") }
    let html = DocumentHTML.render(spec).lowercased()
    expect(!html.contains("<script"), "HTML: ningún script")
    expect(!html.contains("http://") && !html.contains("https://") && !html.contains("src="),
           "HTML: nada remoto; todo en línea")
    expect(html.contains("<svg"), "HTML: la gráfica va como SVG en línea")
    expect(html.contains("informe q3"), "HTML: el contenido está")
}

func testChartsBecomeInlineSVG() {
    for kind in ChartBlock.Kind.allCases {
        let block = ChartBlock(title: "t", kind: kind, labels: ["a", "b", "c"],
                               series: [.init(name: "s", values: [1, 3, 2])])
        let svg = ChartSVG.render(block)
        expect(svg.hasPrefix("<svg"), "SVG \(kind): empieza como SVG")
        expect(!svg.contains("NaN") && !svg.contains("inf"), "SVG \(kind): coordenadas finitas")
    }
}

func testAChartWithNegativesAndOnePointStillDraws() {
    let block = ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [-5])])
    let svg = ChartSVG.render(block)
    expect(!svg.contains("NaN"), "SVG: un solo punto negativo no divide por cero")
    let flat = ChartBlock(kind: .line, labels: ["a", "b"], series: [.init(values: [0, 0])])
    expect(!ChartSVG.render(flat).contains("NaN"), "SVG: una serie plana no divide por cero")
    let pieZero = ChartBlock(kind: .pie, labels: ["a"], series: [.init(values: [0])])
    expect(!ChartSVG.render(pieZero).contains("NaN"), "SVG: un pastel que suma cero no divide por cero")
}

func testTheFormatComesFromThePath() {
    expectEq(DocumentFormat(path: "/tmp/x.pdf"), .pdf, "formato: .pdf")
    expectEq(DocumentFormat(path: "informe.XLSX"), .xlsx, "formato: .xlsx sin importar mayúsculas")
    expectEq(DocumentFormat(path: "notas.docx"), nil, "formato: .docx fuera de 20 (D7 a)")
}
