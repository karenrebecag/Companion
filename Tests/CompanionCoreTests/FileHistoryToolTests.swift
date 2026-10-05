import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// PR4c: list_file_history reads, restore_file_version overwrites the user's
// file with an old one, so it always takes the sheet and is never remembered.

private func request(_ json: String) -> ApprovalRequest {
    ApprovalRequest(requestId: "r", toolName: "restore_file_version", summary: "", inputJSON: json)
}

@Test @MainActor func theHistoryToolsHaveTheirContracts() {
    let list = NativeTool.listFileHistory.spec
    expectEq(list.name, "list_file_history", "list: wire name")
    expect(list.properties.map(\.name) == ["path"] && list.required == ["path"], "list: only a path")
    expectEq(NativeTool.listFileHistory.riskLevel, .safe, "list: read-only, no sheet")
    let restore = NativeTool.restoreFileVersion.spec
    expectEq(restore.name, "restore_file_version", "restore: wire name")
    expect(restore.properties.map(\.name) == ["path", "version"] && restore.required == ["path", "version"],
           "restore: a path and a version id")
    expect(restore.description.contains("list_file_history"), "restore: tells the model where ids come from")
    expectEq(NativeTool.restoreFileVersion.riskLevel, .requiresApproval, "restore: asks first")
    expectEq(NativeTool(rawValue: "restore_file_version"), .restoreFileVersion, "restore: wire name round-trips")
}

@Test @MainActor func theRestoreSheetSaysWhatItReplacesInBothLanguages() {
    let json = #"{"path":"~/Desktop/informe.pdf","version":"a1b2c3d4"}"#
    let es = ApprovalCopy.display(for: request(json), language: .es)
    expectEq(es.lead, "Restaurar", "sheet es: the verb")
    expectEq(es.subject, "informe.pdf", "sheet es: the file is the subject")
    expectEq(es.preview, "~/Desktop/informe.pdf", "sheet es: the full path to audit")
    expect(!es.showsRemember, "sheet: never offers to remember a restore")
    let esTrail = es.trail ?? ""
    expect(esTrail.contains("versión anterior") && esTrail.contains("copia"),
           "sheet es: an older version replaces it, and a copy of the current one is kept, got «\(esTrail)»")
    let en = ApprovalCopy.display(for: request(json), language: .en)
    expectEq(en.lead, "Restore", "sheet en: the verb")
    let enTrail = en.trail ?? ""
    expect(enTrail.contains("earlier version") && enTrail.contains("copy"),
           "sheet en: an earlier version replaces it, and a copy of the current one is kept, got «\(enTrail)»")
    let bare = ApprovalCopy.display(for: request("{}"), language: .en)
    expect(!bare.showsRemember && bare.lead == "Restore", "sheet: no path is still named as a restore")
}

@Test @MainActor func theRestoreSheetCannotBeForgedByThePath() {
    let shown = ApprovalCopy.display(
        for: request(#"{"path":"~/Docs/real.md\nRestore: harmless.txt‮fdp.exe​","version":"x"}"#), language: .en)
    for field in [shown.subject, shown.preview ?? ""] {
        expect(!field.contains("\n"), "forge: no newline in «\(field.debugDescription)»")
        expect(!field.unicodeScalars.contains("\u{202E}"), "forge: no RTL override")
        expect(!field.unicodeScalars.contains("\u{200B}"), "forge: no zero-width space")
    }
}

@Test @MainActor func restoreNeverActsAloneNorIsRemembered() {
    var facts = ActionFacts()
    facts.pathExists = true
    facts.inWorkZone = true
    expectEq(ActionBand.classify(toolName: "restore_file_version", arguments: ["path": "a.md"], facts: facts),
             .critical, "band: always the sheet")
    for json in [#"{"path":"~/a.pdf","version":"a1b2c3d4"}"#, "{}"] {
        expect(ApprovalKey.from(request(json)) == nil, "memory: no key for \(json)")
    }
}

@Test @MainActor func theHistoryToolsAreLocalOnlyForTheBridge() {
    for name in ["list_file_history", "restore_file_version"] {
        expect(BridgeScope.isLocalOnly(name) && !BridgeScope.allows(name), "bridge: \(name) stays with the user")
        expect(ParentTool.ownsRequest(name), "parent: a switched turn drops the \(name) request")
    }
}

@Test @MainActor func theRestoreSheetSaysWhichVersionOrThatTheAssistantChose() {
    let chosen = #"{"path":"~/a.pdf","version":"x","restore_when":"2026-10-04T12:00:00Z, pre-save"}"#
    expect((ApprovalCopy.display(for: request(chosen), language: .en).trail ?? "").contains("2026-10-04T12:00:00Z, pre-save"),
           "sheet en: the resolved version")
    expect((ApprovalCopy.display(for: request(chosen), language: .es).trail ?? "").contains("2026-10-04T12:00:00Z, pre-save"),
           "sheet es: the resolved version")
    let unresolved = ApprovalCopy.display(for: request(#"{"path":"~/a.pdf","version":"x"}"#), language: .en)
    expect((unresolved.trail ?? "").contains("assistant chose"), "sheet en: says the assistant chose it")
    let es = ApprovalCopy.display(for: request(#"{"path":"~/a.pdf","version":"x"}"#), language: .es)
    expect((es.trail ?? "").contains("asistente"), "sheet es: says the assistant chose it")
    let link = ApprovalCopy.display(
        for: request(#"{"path":"link.pdf","version":"x","restore_real":"/Users/k/Docs/real.pdf"}"#), language: .en)
    expectEq(link.subject, "real.pdf", "sheet: the real file name")
    expect((link.preview ?? "").contains("link.pdf") && (link.preview ?? "").contains("/Users/k/Docs/real.pdf"),
           "sheet: both paths shown")
}
