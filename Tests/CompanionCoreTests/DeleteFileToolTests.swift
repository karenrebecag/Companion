import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// delete_file starts at the strictest rung: it always asks, the sheet names
// the file, a spoken yes cannot settle it, no band lets it act alone, and no
// yes is ever remembered, not even for the exact file.

private func request(_ json: String) -> ApprovalRequest {
    ApprovalRequest(requestId: "r", toolName: "delete_file", summary: "", inputJSON: json)
}

@Test @MainActor func deleteFileIsASpecWithOnlyAPath() {
    let spec = NativeTool.deleteFile.spec
    expectEq(spec.name, "delete_file", "spec: wire name")
    expect(spec.properties.map(\.name) == ["path"] && spec.required == ["path"], "spec: a path and nothing else")
    expect(spec.description.contains("Trash"), "spec: tells the model where it goes")
    expect(spec.description.contains("permanent"), "spec: tells the model the fallback exists")
    expectEq(NativeTool(rawValue: "delete_file"), .deleteFile, "enum: wire name round-trips")
    expectEq(NativeTool.deleteFile.riskLevel, .requiresApproval, "risk: asks first")
}

@Test @MainActor func deleteFileSheetSaysTrashOrPermanentInBothLanguages() {
    let es = ApprovalCopy.display(for: request(#"{"path":"~/Desktop/informe.md"}"#), language: .es)
    expectEq(es.lead, "Borrar", "sheet es: the verb")
    expectEq(es.subject, "informe.md", "sheet es: the file is the subject")
    expectEq(es.preview, "~/Desktop/informe.md", "sheet es: the full path to audit")
    expect(!es.showsRemember, "sheet: never offers to remember a delete")
    let esTrail = es.trail ?? ""
    expect(esTrail.contains("Papelera") && esTrail.contains("para siempre"),
           "sheet es: Trash, or for good when it is not available, got «\(esTrail)»")
    expect(esTrail.contains("todo lo que contiene"), "sheet es: a folder goes with everything inside")
    let en = ApprovalCopy.display(for: request(#"{"path":"a.md"}"#), language: .en)
    expectEq(en.lead, "Delete", "sheet en: the verb")
    let enTrail = en.trail ?? ""
    expect(enTrail.contains("Trash") && enTrail.contains("permanently"),
           "sheet en: Trash, or permanently when it is not available, got «\(enTrail)»")
    expect(enTrail.contains("everything inside"), "sheet en: a folder goes with everything inside")
    let bare = ApprovalCopy.display(for: request(#"{}"#), language: .en)
    expect(!bare.showsRemember, "sheet: a delete without a path still never offers to remember")
    expectEq(bare.lead, "Delete", "sheet: a delete without a path is still named as one")
    expectEq(ApprovalCopy.toolLabel("delete_file", language: .es), "borrar un archivo o carpeta", "label es")
    expectEq(ApprovalCopy.toolLabel("delete_file", language: .en), "delete a file or folder", "label en")
}

@Test @MainActor func deleteFileSheetCannotBeForgedByTheModelsPath() {
    let crafted = "~/Docs/real.md\nDelete: harmless.txt\u{202E}fdp.exe\u{200B}"
    let shown = ApprovalCopy.display(for: request(#"{"path":"~/Docs/real.md\nDelete: harmless.txt\u202Efdp.exe\u200B"}"#), language: .en)
    for field in [shown.subject, shown.preview ?? ""] {
        expect(!field.contains("\n"), "forge: no newline in «\(field.debugDescription)»")
        expect(!field.unicodeScalars.contains("\u{202E}"), "forge: no RTL override")
        expect(!field.unicodeScalars.contains("\u{200B}"), "forge: no zero-width space")
    }
    _ = crafted
}

@Test @MainActor func deleteFileNeverHasAnAutomaticBandNorASpokenYes() {
    var facts = ActionFacts()
    facts.pathExists = false
    facts.inWorkZone = true
    expectEq(ActionBand.classify(toolName: "delete_file", arguments: ["path": "a.md"], facts: facts),
             .critical, "band: even a plain data file in the work zone takes the sheet")
    expectEq(ApprovalRisk.of(toolName: "delete_file"), .high, "risk: a spoken yes does not settle it")
}

@Test @MainActor func deleteFileIsNeverRemembered() {
    for json in [#"{"path":"~/Desktop/informe.md"}"#, #"{"path":"/tmp/x"}"#, #"{}"#, #"{"path":""}"#] {
        expect(ApprovalKey.from(request(json)) == nil, "memory: no key for \(json), so nothing is stored or replayed")
    }
}

@Test @MainActor func deleteFileCountsAsTouchingAFileInTheJobSummary() {
    let steps = [JobStepInfo(tool: "delete_file", label: "x"), JobStepInfo(tool: "write_file", label: "y")]
    expectEq(JobSteps.summary(steps), "2 files", "summary: delete counts as a file touched")
}
