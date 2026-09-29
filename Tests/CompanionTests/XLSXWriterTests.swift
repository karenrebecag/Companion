@testable import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 20-4 (spec 20 D6, §6.7): an .xlsx is a zip of SpreadsheetML. Written
// in Swift, checked with the system's own unzip, opened by Numbers live.

@Test func xlsxWriterTests() async {
    testCRC32MatchesTheKnownVector()
    testEveryTableBecomesASheet()
    testCellsKeepTheirType()
    testSheetNamesAreLegalAndUnique()
    testXMLIsEscapedAndControlCharactersDropped()
    await testTheZipIsValidForTheSystemUnzip()
    testADocumentWithoutRowsHasNoWorkbook()
    testAForbiddenFormulaIsWrittenAsText()
}

private let spec = DocumentSpec.parse("""
{"title":"Ventas","blocks":[
 {"type":"stats","title":"Resumen","items":[{"label":"Total","value":"12400"}]},
 {"type":"table","title":"Por país","columns":["País","Ventas","Total"],"rows":[["MX","10","=B2*2"],["CO","7.5","=B3*2"]]},
 {"type":"chart","title":"Serie","kind":"line","labels":["ene","feb"],"series":[{"name":"2026","values":[1,2]}]}
]}
""")!

func testCRC32MatchesTheKnownVector() {
    expectEq(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926, "CRC32: el vector de referencia")
    expectEq(ZipWriter.crc32(Data()), 0, "CRC32: vacío es cero")
}

func testEveryTableBecomesASheet() {
    let sheets = XLSXWriter.sheets(spec)
    expectEq(sheets.map(\.name), ["Resumen", "Por país", "Serie"], "xlsx: cifras, tabla y serie, una hoja cada una")
    expectEq(sheets[1].rows.count, 3, "xlsx: encabezado más dos filas")
}

func testCellsKeepTheirType() {
    let xml = XLSXWriter.sheetXML(XLSXWriter.sheets(spec)[1], allowFormulas: true)
    expect(xml.contains("<f>B2*2</f>"), "xlsx: una fórmula va sin el = en <f>")
    expect(xml.contains("<v>7.5</v>"), "xlsx: un número puro va como número")
    expect(xml.contains("t=\"inlineStr\"><is><t>MX</t>"), "xlsx: el texto va en línea")
    expect(xml.contains("<pane ySplit=\"1\""), "xlsx: la primera fila queda congelada")
    expect(xml.contains("s=\"1\""), "xlsx: el encabezado lleva el estilo en negrita")
}

func testSheetNamesAreLegalAndUnique() {
    let names = XLSXWriter.uniqueNames(["Q3: ventas/[MX]?", "Q3: ventas/[MX]?", "", String(repeating: "x", count: 40)])
    expect(names.allSatisfy { $0.count <= 31 }, "xlsx: 31 caracteres como mucho")
    expect(names.allSatisfy { !$0.contains(where: { ":\\/?*[]".contains($0) }) }, "xlsx: sin caracteres prohibidos")
    expectEq(Set(names).count, names.count, "xlsx: nombres únicos")
    expectEq(names[2], "Hoja 3", "xlsx: sin nombre se numera")
}

func testXMLIsEscapedAndControlCharactersDropped() {
    expectEq(XLSXWriter.xml("a<b & \"c\"\u{0001}"), "a&lt;b &amp; &quot;c&quot;", "xlsx: XML escapado y sin caracteres de control")
}

func testTheZipIsValidForTheSystemUnzip() async {
    guard let data = XLSXWriter.package(spec) else { return expect(false, "xlsx: empaqueta") }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID().uuidString).xlsx")
    do {
        try data.write(to: url)
        defer { do { try FileManager.default.removeItem(at: url) } catch {} }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tq", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        expectEq(process.terminationStatus, 0, "xlsx: unzip -t lo valida (\(output))")
        for part in ["\\[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
                     "xl/styles.xml", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml", "xl/worksheets/sheet3.xml"] {
            let lint = Process()
            lint.executableURL = URL(fileURLWithPath: "/bin/sh")
            lint.arguments = ["-c", "/usr/bin/unzip -p \"$0\" \"$1\" | /usr/bin/xmllint --noout -", url.path, part]
            try lint.run()
            lint.waitUntilExit()
            expectEq(lint.terminationStatus, 0, "xlsx: \(part) es XML bien formado")
        }
        let receipt = try await NativeDocumentRenderer().render(spec, format: .xlsx, to: url)
        expect(receipt.bytes > 0 && receipt.pages == nil, "xlsx: el renderizador lo escribe y no cuenta páginas")
    } catch {
        expect(false, "xlsx: escribir y validar no debe fallar (\(error))")
    }
}

func testADocumentWithoutRowsHasNoWorkbook() {
    let prose = DocumentSpec(title: "x", blocks: [.paragraph("solo texto")])
    expect(XLSXWriter.package(prose) == nil, "xlsx: sin tablas no hay libro que escribir")
}

/// Code review 20 (MEDIUM): a cell from the web that looks like a fetching
/// formula lands as text, never as a live formula in the user's Excel.
func testAForbiddenFormulaIsWrittenAsText() {
    let sheet = XLSXWriter.Sheet(name: "x", rows: [["a"], ["=WEBSERVICE(\"https://x\")"], ["=cmd|' /c calc'!A0"], ["+cmd|' /c calc'!A0"]])
    let xml = XLSXWriter.sheetXML(sheet)
    expect(!xml.contains("<f>"), "xlsx: ninguna fórmula de red o DDE se escribe como fórmula")
    expect(xml.contains("WEBSERVICE"), "xlsx: queda visible como texto")
    expect(xml.contains("<t>+cmd|"), "xlsx: un disparador + queda como texto en línea")
}
