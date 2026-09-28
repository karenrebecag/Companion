import CompanionCore
@testable import CompanionServices
import Foundation
import PDFKit
import Testing

// Wave 20-2 (spec 20 §6.4-5): a real PDF, paginated, with the words in it,
// and a page that cannot reach the network.

@Test @MainActor func pdfRendererTests() async {
    await testASpecBecomesAPaginatedPDF()
    testTheOfflineRuleBlocksEveryScheme()
    testThePageRunsNoScriptAndKeepsNothing()
}

@MainActor func testASpecBecomesAPaginatedPDF() async {
    let rows = (0..<120).map { #"["fila \#($0)","\#($0)"]"# }.joined(separator: ",")
    let json = #"{"title":"Informe de prueba","blocks":[{"type":"cover","title":"Informe de prueba","subtitle":"Q3"},{"type":"stats","items":[{"label":"Total","value":"$12k","delta":"+8 %"}]},{"type":"chart","kind":"bar","labels":["a","b"],"series":[{"values":[1,2]}]},{"type":"table","columns":["Nombre","Valor"],"rows":[\#(rows)]}]}"#
    guard let spec = DocumentSpec.parse(json) else { return expect(false, "pdf: el spec parsea") }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-\(UUID().uuidString).pdf")
    defer { do { try FileManager.default.removeItem(at: url) } catch {} }
    do {
        let receipt = try await NativeDocumentRenderer().render(spec, format: .pdf, to: url)
        expect((receipt.pages ?? 0) >= 2, "pdf: 120 filas ocupan más de una página (\(receipt.pages ?? 0))")
        expect(receipt.bytes > 0, "pdf: el archivo pesa algo")
        let text = PDFDocument(url: url)?.string ?? ""
        expect(text.contains("Informe de prueba"), "pdf: el título está en el texto del PDF")
        expect(text.contains("fila 119"), "pdf: la última fila no se perdió en la paginación")
    } catch {
        expect(false, "pdf: renderizar no debe fallar (\(error))")
    }
}

@MainActor func testTheOfflineRuleBlocksEveryScheme() {
    for scheme in ["https", "http", "file", "data", "wss", "blob", "ftp"] {
        expect(PDFRenderer.blockEverything.contains(scheme), "pdf: la regla bloquea \(scheme)")
    }
}

/// Code review 20 (MEDIUM): the controls themselves, not just the rule text.
@MainActor func testThePageRunsNoScriptAndKeepsNothing() {
    let config = PDFRenderer.configuration()
    expect(!config.defaultWebpagePreferences.allowsContentJavaScript, "pdf: JavaScript apagado")
    expect(!config.websiteDataStore.isPersistent, "pdf: almacén de datos desechable")
}
