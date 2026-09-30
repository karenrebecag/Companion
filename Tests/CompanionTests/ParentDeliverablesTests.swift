import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 20b D2 (spec 20b §3): the chat and the voice reach create_document,
// sheet_read and sheet_write themselves — with Claude Code installed every
// delegation leaves the native lane, so the tools were unreachable. The
// writes ask through a ticket; the MCP bridge never sees any of the three.

private struct FakeDocuments: DocumentRendering {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        try Data("%PDF-fake".utf8).write(to: url)
        return DocumentReceipt(pages: 1, bytes: 9)
    }
}

private final class FakeSheets: SpreadsheetDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _writes = 0
    private var _path = "/tmp/libro.xlsx"
    var writes: Int { lock.withLock { _writes } }
    var path: String {
        get { lock.withLock { _path } }
        set { lock.withLock { _path = newValue } }
    }
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { path }
    var blank = false
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { blank ? [[""]] : [["Mes", "Ventas"]] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        lock.withLock { _writes += 1 }
        return SheetWriteReceipt(backupPath: "/tmp/libro-backup.xlsx", readBack: [["1"]])
    }
}

@Test @MainActor func parentDeliverablesTests() async throws {
    testTheToolsFollowTheirBacking()
    await testASheetReadNeedsNoSheet()
    try await testANewDocumentIsDeliveredWithoutTheSheet()
    try await testADocumentRunsOnlyWithItsTicket()
    await testAnAppendOnlySheetWriteSkipsTheSheet()
    await testASheetWriteRunsOnlyWithItsTicket()
    await testASheetWriteNamesItsApp()
    await testASheetWriteIsBoundToTheWorkbookItShowed()
    await testTheBridgeNeverSeesTheDeliverables()
    testTheParentOwnsItsDeliverableRequests()
}

private let documentArgs = #"{"path":"informe.pdf","document":"{\"title\":\"x\",\"blocks\":[{\"type\":\"paragraph\",\"text\":\"hola\"}]}"}"#
private let writeArgs = #"{"app":"excel","range":"A1","values":"[[1]]"}"#

private func workdir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pd-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func runner(workdir: String? = nil, sheets: FakeSheets = FakeSheets()) -> ParentToolRunner {
    ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []),
                     workdir: workdir, documents: FakeDocuments(), sheets: sheets)
}

@MainActor func testTheToolsFollowTheirBacking() {
    let bare = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []))
    let names = Set(bare.specs(.es).map(\.name))
    for tool in NativeTool.parentDeliverables {
        expect(!names.contains(tool.rawValue) && !bare.handles(tool.rawValue),
               "padre: sin backing no se ofrece \(tool.rawValue)")
    }
    let backed = runner()
    let offered = Set(backed.specs(.es).map(\.name))
    for tool in NativeTool.parentDeliverables {
        expect(offered.contains(tool.rawValue) && backed.handles(tool.rawValue),
               "padre: con backing se ofrece \(tool.rawValue)")
    }
}

@MainActor func testASheetReadNeedsNoSheet() async {
    let r = runner()
    let call = ToolCallRef(id: "1", name: "sheet_read", arguments: #"{"range":"A1:B1"}"#)
    expect(r.approval(for: call, said: "") == nil, "sheet_read: leer no pide hoja")
    let out = await r.execute(name: "sheet_read", argumentsJSON: #"{"range":"A1:B1"}"#)
    expect(out.ok && out.output.contains("Ventas"), "sheet_read: el padre lee el libro abierto")
}

@MainActor func testADocumentRunsOnlyWithItsTicket() async throws {
    let dir = try workdir()
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let r = runner(workdir: dir.path)
    let file = dir.appendingPathComponent("informe.pdf").path
    // Wave 20d B: only replacing a file asks, so the file is already there.
    try Data("previo".utf8).write(to: URL(fileURLWithPath: file))

    let skipped = await r.execute(name: "create_document", argumentsJSON: documentArgs)
    expect(!skipped.ok && (try? String(contentsOfFile: file, encoding: .utf8)) == "previo",
           "create_document: sin pasar por la hoja no pisa nada")

    let call = ToolCallRef(id: "2", name: "create_document", arguments: documentArgs)
    guard let request = r.approval(for: call, said: "hazme un pdf") else {
        return expect(false, "create_document: pide la hoja")
    }
    expectEq(request.toolName, "create_document", "create_document: la hoja lleva el nombre de la tool")
    let denied = await r.execute(name: "create_document", argumentsJSON: documentArgs)
    expect(!denied.ok, "create_document: pedida pero no concedida, no escribe")

    guard let again = r.approval(for: call, said: "") else { return expect(false, "create_document: hoja otra vez") }
    r.granted(again)
    let done = await r.execute(name: "create_document", argumentsJSON: documentArgs)
    expect(done.ok && FileManager.default.fileExists(atPath: file), "create_document: con el sí, escribe en la carpeta")

    let replay = await r.execute(name: "create_document", argumentsJSON: documentArgs)
    expect(!replay.ok, "create_document: el ticket se gasta una vez")
}

private final class Receipts: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UndoReceipt] = []
    var all: [UndoReceipt] { lock.withLock { items } }
    func add(_ receipt: UndoReceipt) { lock.withLock { items.append(receipt) } }
}

@MainActor func testANewDocumentIsDeliveredWithoutTheSheet() async throws {
    let dir = try workdir()
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let heard = Receipts()
    let r = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []),
                             workdir: dir.path, documents: FakeDocuments(), sheets: FakeSheets(),
                             onAct: { heard.add($0) })
    let call = ToolCallRef(id: "n", name: "create_document", arguments: documentArgs)
    expect(await r.actsWithoutSheet(call), "documento nuevo: sin hoja")
    let done = await r.execute(name: "create_document", argumentsJSON: documentArgs)
    expect(done.ok && FileManager.default.fileExists(atPath: dir.appendingPathComponent("informe.pdf").path),
           "documento nuevo: se entrega")
    expectEq(heard.all.map(\.kind), [.created], "documento nuevo: avisa a la isla")
    expectEq(heard.all.first?.subject, "informe.pdf", "documento nuevo: con su nombre")
    let again = ToolCallRef(id: "m", name: "create_document", arguments: documentArgs)
    expect(!(await r.actsWithoutSheet(again)), "documento que ya existe: pisarlo pide la hoja")
    expect(r.approval(for: again, said: "") != nil, "documento que ya existe: la hoja existe")
    let replaced = await r.execute(name: "create_document", argumentsJSON: documentArgs)
    expect(!replaced.ok, "documento que ya existe: sin el sí no se pisa")
}

@MainActor func testAnAppendOnlySheetWriteSkipsTheSheet() async {
    let sheets = FakeSheets()
    sheets.blank = true
    let heard = Receipts()
    let r = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []),
                             workdir: nil, documents: FakeDocuments(), sheets: sheets,
                             onAct: { heard.add($0) })
    let call = ToolCallRef(id: "e", name: "sheet_write", arguments: writeArgs)
    let acts = await r.actsWithoutSheet(call)
    expect(acts, "sheet_write en celdas vacías: sin hoja")
    let done = await r.execute(name: "sheet_write", argumentsJSON: writeArgs)
    expect(done.ok && sheets.writes == 1, "sheet_write en celdas vacías: escribe")
    expectEq(heard.all.first?.undo, .clearCells(app: .excel, range: "A1", workbook: "/tmp/libro.xlsx", expected: [[""]]),
             "sheet_write en celdas vacías: el recibo vacía lo que llenó, y guarda cómo quedó")

    let busy = FakeSheets()
    let rb = runner(sheets: busy)
    let asks = await rb.actsWithoutSheet(call)
    expect(!asks, "sheet_write sobre celdas con valor: pide la hoja")
    let refused = await rb.execute(name: "sheet_write", argumentsJSON: writeArgs)
    expect(!refused.ok && busy.writes == 0, "sheet_write sobre celdas con valor: sin ticket no escribe")
}

@MainActor func testASheetWriteRunsOnlyWithItsTicket() async {
    let sheets = FakeSheets()
    let r = runner(sheets: sheets)
    let skipped = await r.execute(name: "sheet_write", argumentsJSON: writeArgs)
    expect(!skipped.ok && sheets.writes == 0, "sheet_write: sin hoja no toca el libro")

    let call = ToolCallRef(id: "3", name: "sheet_write", arguments: writeArgs)
    guard let asked = r.approval(for: call, said: "") else { return expect(false, "sheet_write: pide la hoja") }
    let request = await r.bound(asked)
    r.granted(request)
    let other = await r.execute(name: "sheet_write", argumentsJSON: #"{"app":"excel","range":"B9","values":"[[1]]"}"#)
    expect(!other.ok && sheets.writes == 0, "sheet_write: el sí vale para esa escritura exacta, no para otra")
    let done = await r.execute(name: "sheet_write", argumentsJSON: writeArgs)
    expect(done.ok && sheets.writes == 1, "sheet_write: con el sí, escribe una vez")
}

@MainActor func testTheBridgeNeverSeesTheDeliverables() async {
    let session = BridgeSession(
        tools: runner(), guard: ParentToolGuard(approvals: nil),
        token: { "tok" }, language: { .en }, accessibility: { true }, onAction: { _ in })
    let hello = await session.handle(line: #"{"id":1,"method":"hello","params":{"token":"tok","client":"t","protocol":1}}"#)
    for tool in NativeTool.parentDeliverables {
        expect(!hello.reply.contains("\"\(tool.rawValue)\""), "puente: hello no lista \(tool.rawValue)")
        let call = await session.handle(
            line: #"{"id":2,"method":"call","params":{"name":"\#(tool.rawValue)","arguments":{}}}"#)
        expect(call.reply.contains(BridgeCode.unknownTool), "puente: \(tool.rawValue) no existe por MCP")
    }
    expect(NativeTool.parentDeliverables.allSatisfy { BridgeScope.isLocalOnly($0.rawValue) },
           "puente: la lista local cubre cada entregable")
}

func testTheParentOwnsItsDeliverableRequests() {
    expect(ParentTool.ownsRequest("sheet_write"), "cambio de conversación: una hoja del padre para sheet_write se suelta")
    expect(ParentTool.ownsRequest("look"), "cambio de conversación: las de siempre también")
    expect(!ParentTool.ownsRequest("write_file"), "cambio de conversación: la de un encargo sobrevive")
}

/// Security review 20b (MEDIUM): without an app the target is resolved when
/// it runs, so the user could approve one workbook and write another.
@MainActor func testASheetWriteNamesItsApp() async {
    let sheets = FakeSheets()
    let r = runner(sheets: sheets)
    let args = #"{"range":"A1","values":"[[1]]"}"#
    let call = ToolCallRef(id: "4", name: "sheet_write", arguments: args)
    expect(r.approval(for: call, said: "") == nil, "sheet_write sin app: no hay hoja que aprobar")
    let out = await r.execute(name: "sheet_write", argumentsJSON: args)
    expect(!out.ok && out.output.hasPrefix("invalid_args") && sheets.writes == 0,
           "sheet_write sin app: se rechaza pidiendo la app, sin tocar el libro")
}

/// Wave 20c D4 (H4): the sheet names the workbook and what it would write, and
/// a workbook swapped after the yes never receives the write.
@MainActor func testASheetWriteIsBoundToTheWorkbookItShowed() async {
    let sheets = FakeSheets()
    let r = runner(sheets: sheets)
    let call = ToolCallRef(id: "5", name: "sheet_write", arguments: writeArgs)
    guard let asked = r.approval(for: call, said: "") else { return expect(false, "sheet_write: pide la hoja") }
    let request = await r.bound(asked)
    let shown = ApprovalCopy.display(for: request, language: .en)
    expect(shown.preview?.contains("/tmp/libro.xlsx") == true, "sheet_write: la hoja nombra el libro")

    r.granted(request)
    sheets.path = "/tmp/otro.xlsx"
    let swapped = await r.execute(name: "sheet_write", argumentsJSON: writeArgs)
    expect(!swapped.ok && sheets.writes == 0, "sheet_write: libro cambiado tras el sí, no escribe")

    let fresh = FakeSheets()
    let r2 = runner(sheets: fresh)
    guard let second = r2.approval(for: call, said: "") else { return expect(false, "sheet_write: hoja otra vez") }
    r2.granted(second)
    let unbound = await r2.execute(name: "sheet_write", argumentsJSON: writeArgs)
    expect(!unbound.ok && fresh.writes == 0, "sheet_write: un sí que la hoja no ató a un libro no escribe")

    let r3 = runner(sheets: fresh)
    guard let third = r3.approval(for: call, said: "") else { return expect(false, "sheet_write: hoja otra vez") }
    r3.granted(await r3.bound(third))
    let done = await r3.execute(name: "sheet_write", argumentsJSON: writeArgs)
    expect(done.ok && fresh.writes == 1, "sheet_write: el mismo libro de la hoja, escribe")
}
