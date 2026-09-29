@testable import CompanionCore
import Foundation
import Testing

// Wave 20c D4 (H4): the sheet for a write shows what it authorizes.

@Test func sheetApprovalTests() {
    testTheSheetShowsTheWorkbookAndEveryCell()
    testTheFingerprintFollowsTheValues()
    testTheWorkbookIsBoundByTheRunnerNeverTheModel()
    testTheLegacyDetailShowsTheWorkbookAndTheWholeValues()
}

private func request(_ object: [String: Any]) -> ApprovalRequest {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    return ApprovalRequest(requestId: "r", toolName: "sheet_write", summary: "",
                           inputJSON: String(data: data, encoding: .utf8) ?? "")
}

private func longValues(last: String) -> String {
    let rows = (0..<40).map { "[\"fila\($0)-" + String(repeating: "x", count: 30) + "\"]" }
    return "[" + rows.joined(separator: ",") + ",[\"" + last + "\"]]"
}

func testTheSheetShowsTheWorkbookAndEveryCell() {
    let shown = ApprovalCopy.display(for: request([
        "app": "excel", "range": "A1:A41", "workbook": "/Users/k/Ventas Q3.xlsx",
        "values": longValues(last: "ULTIMA-CELDA"),
    ]), language: .en)
    let preview = shown.preview ?? ""
    expect(shown.subject != "sheet_write", "hoja: el sujeto dice dónde, no el id de la tool")
    expect(preview.contains("/Users/k/Ventas Q3.xlsx"), "hoja: nombra el libro por su ruta")
    expect(preview.contains("ULTIMA-CELDA"), "hoja: la última celda, la que un corte escondía, se ve")
    expect(preview.contains("41 cells"), "hoja: dice cuántas celdas escribe")
}

func testTheFingerprintFollowsTheValues() {
    let a: [[SheetCell]] = [[.text("a"), .number(1)]]
    expectEq(SheetApproval.fingerprint(a), SheetApproval.fingerprint(a), "hash: estable")
    expect(!SheetApproval.fingerprint(a).isEmpty, "hash: no vacío")
    expect(SheetApproval.fingerprint(a) != SheetApproval.fingerprint([[.text("a"), .number(2)]]),
           "hash: cambia con un valor")
    expect(SheetApproval.fingerprint([[.text("=A1")]]) != SheetApproval.fingerprint([[.formula("=A1")]]),
           "hash: texto y fórmula no son lo mismo")
    expect(SheetApproval.fingerprint([[.text("ab"), .text("c")]]) != SheetApproval.fingerprint([[.text("a"), .text("bc")]]),
           "hash: la frontera entre celdas cuenta")
}

func testTheWorkbookIsBoundByTheRunnerNeverTheModel() {
    let spoofed = #"{"app":"excel","range":"A1","values":"[[1]]","workbook":"/falso.xlsx"}"#
    let bound = SheetApproval.bind(spoofed, workbook: "/real.xlsx")
    expectEq(ToolArguments.parse(bound)?["workbook"] as? String, "/real.xlsx", "ligado: manda el del runner")
    expectEq(ToolArguments.parse(bound)?["range"] as? String, "A1", "ligado: el resto queda")
    let unresolved = SheetApproval.bind(spoofed, workbook: nil)
    expect(ToolArguments.parse(unresolved)?["workbook"] == nil, "ligado: sin libro resuelto, el del modelo no queda")
}

func testTheLegacyDetailShowsTheWorkbookAndTheWholeValues() {
    let detail = SheetValues.approvalDetail(["app": "excel", "range": "A1:A41", "workbook": "/Users/k/V.xlsx",
                                             "values": longValues(last: "ULTIMA-CELDA")])
    expect(detail?.contains("/Users/k/V.xlsx") == true, "detalle: el libro")
    expect(detail?.contains("ULTIMA-CELDA") == true, "detalle: sin cortar a 200")
}
