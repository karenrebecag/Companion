import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D4 follow-up: Excel's formula setter starts a formula on a leading
// + - or @, so text that merely looks like one is sent with the apostrophe
// that makes it a literal cell.

@Test func excelStoresSignedTextAsLiteral() {
    guard let range = SheetRange(a1: "A1:A3") else { return expect(false, "rango") }
    let script = AppleEventSheets.writeScript(
        .excel, range: range, cells: [[.text("- Total (MXN)")], [.text("hola")], [.formula("=SUM(B1:B2)")]],
        workbook: "/tmp/l.xlsx")
    expect(script.contains("\"'- Total (MXN)\""), "excel: el texto con signo va con apóstrofo")
    expect(script.contains("\"hola\""), "excel: el texto normal no cambia")
    expect(!script.contains("\"'hola\""), "excel: y no lleva apóstrofo")
    expect(script.contains("\"=SUM(B1:B2)\""), "excel: la fórmula sigue siéndolo")
}

@Test func numbersKeepsSignedTextAsWritten() {
    guard let range = SheetRange(a1: "A1") else { return expect(false, "rango") }
    let script = AppleEventSheets.writeScript(
        .numbers, range: range, cells: [[.text("- Total (MXN)")]], workbook: "/tmp/l.numbers")
    expect(script.contains("\"- Total (MXN)\"") && !script.contains("'- Total"),
           "numbers: no hay apóstrofo, se vería tal cual")
}
