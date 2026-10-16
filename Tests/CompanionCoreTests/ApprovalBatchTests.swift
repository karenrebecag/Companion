@testable import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The coalescer: one sheet for the sheets of one step, and the "siempre" that
// is bounded to a host and a kind of action.

private func request(_ id: String, tool: String = "write_file", json: String = #"{"path":"a.md"}"#,
                     isMCP: Bool = false) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: tool, summary: "s-\(id)", inputJSON: json, isMCP: isMCP)
}

@Test func aSingleActionKeepsItsOwnSheet() {
    expect(ApprovalBatch.make(members: [request("a")], requestId: "b") == nil,
           "batch: una sola accion conserva su hoja")
}

@Test func twoOrMoreActionsShareOneSheetAndKeepTheirOwnIds() {
    let members = [request("a"), request("b", tool: "app:slack:send", json: #"{"channel":"ventas"}"#)]
    guard let batch = ApprovalBatch.make(members: members, requestId: "batch") else {
        Issue.record("batch: dos acciones deben juntarse en una hoja")
        return
    }
    expectEq(batch.requestId, "batch", "batch: la hoja tiene su propio id")
    expectEq(batch.members.map(\.requestId), ["a", "b"], "batch: cada accion conserva su id para su ticket")
    let display = ApprovalCopy.display(for: batch, language: .es)
    expectEq(display.subject, "2 acciones esperan tu permiso", "batch: la hoja cuenta las acciones")
    expect(display.preview?.contains("• ") == true, "batch: la lista se ve dentro de la hoja")
    expect(!display.showsRemember, "batch: no hay 'recordar' sobre una lista")
}

@Test func mcpRequestsNeverFoldIntoAList() {
    let members = [request("a"), request("b", isMCP: true)]
    expect(ApprovalBatch.make(members: members, requestId: "batch") == nil,
           "batch: una peticion MCP no entra en una lista que no se puede auditar")
}

// MARK: - Always allow

@Test func alwaysAllowIsBoundedToUploadsToOneHost() {
    let upload = request("u", tool: "browser_set_files", json: #"{"host":"Drive.Google.com","bytes":10}"#)
    expectEq(AlwaysAllowRule.from(upload), AlwaysAllowRule(tool: "browser_set_files", host: "drive.google.com"),
             "always: el host se guarda en minusculas")
    expect(AlwaysAllowRule.from(request("w")) == nil, "always: escribir un archivo no es una regla de host")
    expect(AlwaysAllowRule.from(request("o", tool: ParentTool.openURL.rawValue,
                                        json: #"{"url":"https://a.test/?q=payload"}"#)) == nil,
           "always: abrir una direccion nunca se recuerda, su query es la salida")
    expect(AlwaysAllowRule.from(request("m", tool: "browser_set_files", json: #"{"host":"a.test"}"#,
                                        isMCP: true)) == nil,
           "always: una peticion MCP nunca tiene regla")
}

@Test func theListAllowsOnlyWhatWasKeptAndRevokesCleanly() {
    let drive = AlwaysAllowRule(tool: "browser_set_files", host: "drive.google.com")
    let open = AlwaysAllowRule(tool: ParentTool.openURL.rawValue, host: "atomchat.io")
    let list = AlwaysAllowList().adding(drive).adding(drive).adding(open)
    expectEq(list.rules.count, 2, "always: una regla repetida cuenta una vez")
    expect(list.allows(request("u", tool: "browser_set_files", json: #"{"host":"drive.google.com"}"#)),
           "always: la regla cubre la subida a ese host")
    expect(!list.allows(request("u2", tool: "browser_set_files", json: #"{"host":"evil.test"}"#)),
           "always: otro host no queda cubierto")
    expect(!list.removing(drive).allows(request("u3", tool: "browser_set_files", json: #"{"host":"drive.google.com"}"#)),
           "always: quitar la regla vuelve a preguntar")
}

// Security review of #333: a shared sheet never hides what it approves.

@Test func onlyConfirmsSharedAndMCPStaysAloneWithItsWholePreview() {
    expect(ApprovalBatch.shareable(.confirm, isMCP: false), "batch: un confirm comparte hoja")
    expect(!ApprovalBatch.shareable(.critical, isMCP: false), "batch: un critical pide su propia hoja")
    expect(!ApprovalBatch.shareable(.confirm, isMCP: true), "batch: un MCP pide su propia hoja")
}

@Test func theSharedSheetShowsEachMembersWholePreviewNotItsCappedTitle() {
    let longPath = "/Users/karen/Documents/" + String(repeating: "informe-largo-", count: 12) + ".md"
    let member = request("a", tool: "write_file", json: #"{"path":"\#(longPath)"}"#)
    let other = request("b", tool: "write_file", json: #"{"path":"/Users/karen/a.md"}"#)
    guard let batch = ApprovalBatch.make(members: [member, other], requestId: "batch") else {
        Issue.record("batch: dos confirms deben juntarse")
        return
    }
    let preview = ApprovalCopy.display(for: batch, language: .en).preview ?? ""
    let memberPreview = ApprovalCopy.display(for: member, language: .en).preview ?? ""
    expect(memberPreview.count > 80, "batch: el preview de prueba supera el tope del titulo")
    expect(preview.contains(memberPreview), "batch: la hoja compartida muestra el preview completo de cada accion")
}
