import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 20d B. Every path that skips the sheet is a security seam: it skips it
// only for an act-band call, and a "no" the user asked to remember wins.

private final class Sheets: SpreadsheetDriving, @unchecked Sendable {
    let cells: [[String]]
    init(cells: [[String]]) { self.cells = cells }
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { "/tmp/libro.xlsx" }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { cells }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        SheetWriteReceipt(readBack: [])
    }
}

private actor Answers: ApprovalsProvider {
    private let memory: Bool?
    private(set) var asked = 0
    init(memory: Bool?) { self.memory = memory }
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        asked += 1
        return ApprovalResponse(requestId: approval.requestId, approved: false)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { true }
    func remembered(_ approval: ApprovalRequest) async -> Bool? { memory }
}

private final class Shown: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}

private struct NoDocuments: DocumentRendering {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        DocumentReceipt(pages: 1, bytes: 1)
    }
}

private let write = ToolCallRef(id: "1", name: "sheet_write", arguments: #"{"app":"excel","range":"A1","values":"[[1]]"}"#)

private func runner(cells: [[String]]) -> ParentToolRunner {
    ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []), sheets: Sheets(cells: cells))
}

@Test func guardActsTests() async {
    let free = Answers(memory: nil)
    let shown = Shown()
    let guardFree = ParentToolGuard(approvals: free, onRequest: { _ in shown.bump() })
    let onFree = await guardFree.verdict(write, said: "", language: .es, tools: runner(cells: [[""]]), parked: nil)
    expect(onFree.denial == nil && onFree.answer == nil, "guardia: celdas libres, sin hoja")
    expect(await free.asked == 0 && shown.value == 0, "guardia: celdas libres, nada se pidió ni se mostró")

    let busy = Answers(memory: nil)
    let guardBusy = ParentToolGuard(approvals: busy, onRequest: { _ in shown.bump() })
    let onBusy = await guardBusy.verdict(write, said: "", language: .es, tools: runner(cells: [["ya hay"]]), parked: nil)
    expect(onBusy.denial != nil, "guardia: celdas con valor, la hoja se pide y aquí se niega")
    expect(await busy.asked == 1 && shown.value == 1, "guardia: celdas con valor, la hoja sí sale")

    let refused = Answers(memory: false)
    let guardRefused = ParentToolGuard(approvals: refused)
    let onRefused = await guardRefused.verdict(write, said: "", language: .es, tools: runner(cells: [[""]]), parked: nil)
    expect(onRefused.denial != nil, "guardia: un no recordado gana aunque las celdas estén libres")

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ga-\(UUID().uuidString)")
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {}
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let doc = ToolCallRef(id: "d", name: "create_document", arguments:
        #"{"path":"informe.pdf","document":"{\"title\":\"x\",\"blocks\":[]}"}"#)
    let docs = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []), workdir: dir.path,
                                documents: NoDocuments(), sheets: nil)
    let newDoc = await ParentToolGuard(approvals: Answers(memory: nil))
        .verdict(doc, said: "", language: .es, tools: docs, parked: nil)
    expect(newDoc.denial == nil && newDoc.answer == nil, "guardia: documento nuevo, sin hoja")
    let remembered = await ParentToolGuard(approvals: Answers(memory: false))
        .verdict(doc, said: "", language: .es, tools: docs, parked: nil)
    expect(remembered.denial != nil, "guardia: un no recordado gana también en un documento nuevo")

    let composite = CompositeParentTools([runner(cells: [[""]])])
    expect(await composite.actsWithoutSheet(write), "compuesto: reenvía al runner que maneja la tool")
    expect(!(await composite.actsWithoutSheet(ToolCallRef(id: "2", name: "run_shell", arguments: "{}"))),
           "compuesto: una tool que nadie maneja no se salta la hoja")
    expect(!(await runner(cells: [[""]]).actsWithoutSheet(ToolCallRef(id: "3", name: "open_url", arguments: #"{"url":"https://x.com"}"#))),
           "runner: solo sheet_write usa el atajo asíncrono")
}
