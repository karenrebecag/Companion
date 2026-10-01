@testable import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D4 follow-up: `formulas` gates live formulas in an .xlsx, so the
// model has to be able to find it in the tool contract.

@Test func createDocumentDocumentsTheFormulasSwitch() {
    let spec = DeliverableTools.spec(.createDocument)
    let document = spec.properties.first { $0.name == "document" }?.description ?? ""
    let text = spec.description + " " + document
    expect(text.contains("\"formulas\":true"), "contrato: formulas:true está documentado")
    expect(text.contains("allowlist") || text.contains("plain functions"),
           "contrato: dice que solo pasan funciones simples")
}
