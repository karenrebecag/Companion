import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 20-2/20-3 (spec 20 §6.4, §6.6): the tools ask first, write only inside
// the working folder, verify before reporting, and are not offered without
// something behind them.

private struct FakeDocuments: DocumentRendering {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        try Data("%PDF-fake".utf8).write(to: url)
        return DocumentReceipt(pages: 1, bytes: 9)
    }
}

private final class FakeSheets: SpreadsheetDriving, @unchecked Sendable {
    var app: SheetApp? = .numbers
    var written: [[SheetCell]]?
    var failure: SheetError?
    func active() async -> SheetApp? { app }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] {
        if let failure { throw failure }
        return [["a", "1"]]
    }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]]) async throws -> SheetWriteReceipt {
        if let failure { throw failure }
        written = cells
        return SheetWriteReceipt(backupPath: "/tmp/libro-backup.numbers", readBack: [["a", "1"]])
    }
}

@Test @MainActor func deliverableToolsTests() async {
    testWithoutBackingTheToolsAreNotOffered()
    await testADocumentAsksFirstAndStaysInTheFolder()
    await testADocumentIsVerifiedAndReported()
    await testABadDocumentIsExplained()
    await testASheetWriteAsksAndFitsTheRange()
    await testSheetFailuresNameTheWayOut()
    testTheSheetApprovalShowsTheCells()
    testTheAppleEventScriptsCarryOnlyLiterals()
    testThePrintedPaletteIsTheUIPalette()
}

private func folder() -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deliv-\(UUID().uuidString)")
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {}
    return dir.path
}

private let doc = #"{"title":"X","blocks":[{"type":"paragraph","text":"hola"}]}"#

@MainActor func testWithoutBackingTheToolsAreNotOffered() {
    let bare = NativeToolRunner(workdir: folder(), places: nil)
    for tool in [NativeTool.createDocument, .sheetRead, .sheetWrite] {
        expect(!bare.availableTools.contains(tool), "sin respaldo: \(tool.rawValue) no se ofrece")
    }
    let full = NativeToolRunner(workdir: folder(), places: nil, documents: FakeDocuments(), sheets: FakeSheets())
    for tool in [NativeTool.createDocument, .sheetRead, .sheetWrite] {
        expect(full.availableTools.contains(tool), "con respaldo: \(tool.rawValue) se ofrece")
    }
    expectEq(NativeTool.createDocument.riskLevel, .requiresApproval, "documento: escribe, pide permiso")
    expectEq(NativeTool.sheetWrite.riskLevel, .requiresApproval, "hoja: escribir pide permiso")
    expectEq(NativeTool.sheetRead.riskLevel, .safe, "hoja: leer no")
}

@MainActor func testADocumentAsksFirstAndStaysInTheFolder() async {
    let dir = folder()
    let runner = NativeToolRunner(workdir: dir, places: nil, documents: FakeDocuments())
    do {
        let denied = try await runner.execute(tool: "create_document",
                                              arguments: ["path": "a.pdf", "document": doc], approved: false)
        expect(!denied.ok, "documento: sin aprobación no se escribe")
        expect(!FileManager.default.fileExists(atPath: dir + "/a.pdf"), "documento: nada en disco")
        let outside = try await runner.execute(tool: "create_document",
                                               arguments: ["path": "/etc/x.pdf", "document": doc], approved: true)
        expect(!outside.ok, "documento: fuera de la carpeta de trabajo se rechaza")
    } catch {
        expect(false, "documento: no debe lanzar (\(error))")
    }
}

@MainActor func testADocumentIsVerifiedAndReported() async {
    let dir = folder()
    let runner = NativeToolRunner(workdir: dir, places: nil, documents: FakeDocuments())
    do {
        let result = try await runner.execute(tool: "create_document",
                                              arguments: ["path": "informes/q3.pdf", "document": doc], approved: true)
        expect(result.ok, "documento: se crea")
        expect(result.output.contains("q3.pdf") && result.output.contains("1 page"), "documento: el recibo dice ruta y páginas")
        expect(FileManager.default.fileExists(atPath: dir + "/informes/q3.pdf"), "documento: crea la subcarpeta")
    } catch {
        expect(false, "documento: no debe lanzar (\(error))")
    }
}

@MainActor func testABadDocumentIsExplained() async {
    let runner = NativeToolRunner(workdir: folder(), places: nil, documents: FakeDocuments())
    do {
        let wrongExt = try await runner.execute(tool: "create_document",
                                                arguments: ["path": "a.docx", "document": doc], approved: true)
        expect(wrongExt.output.hasPrefix("invalid_args"), "documento: .docx fuera de 20 se explica")
        let noBlocks = try await runner.execute(tool: "create_document",
                                                arguments: ["path": "a.pdf", "document": "{}"], approved: true)
        expect(noBlocks.output.hasPrefix("invalid_args"), "documento: un JSON vacío se explica")
    } catch {
        expect(false, "documento: no debe lanzar (\(error))")
    }
}

@MainActor func testASheetWriteAsksAndFitsTheRange() async {
    let sheets = FakeSheets()
    let runner = NativeToolRunner(workdir: folder(), places: nil, sheets: sheets)
    do {
        let denied = try await runner.execute(tool: "sheet_write",
                                              arguments: ["range": "A1:B1", "values": #"[["a",1]]"#], approved: false)
        expect(!denied.ok && sheets.written == nil, "hoja: sin aprobación no se toca")
        let wrong = try await runner.execute(tool: "sheet_write",
                                             arguments: ["range": "A1:B2", "values": #"[["a",1]]"#], approved: true)
        expect(wrong.output.hasPrefix("invalid_args") && sheets.written == nil, "hoja: forma equivocada no se escribe")
        let ok = try await runner.execute(tool: "sheet_write",
                                          arguments: ["range": "A1:B1", "values": #"[["a",1]]"#], approved: true)
        expect(ok.ok, "hoja: se escribe")
        expect(ok.output.contains("Backup") && ok.output.contains("Read back"), "hoja: el recibo trae copia y relectura")
        expectEq(sheets.written?.first, [.text("a"), .number(1)], "hoja: las celdas llegan tipadas")
    } catch {
        expect(false, "hoja: no debe lanzar (\(error))")
    }
}

@MainActor func testSheetFailuresNameTheWayOut() async {
    let sheets = FakeSheets()
    let runner = NativeToolRunner(workdir: folder(), places: nil, sheets: sheets)
    do {
        sheets.app = nil
        let none = try await runner.execute(tool: "sheet_read", arguments: ["range": "A1"], approved: false)
        expect(none.output.hasPrefix("no_open_document"), "hoja: sin libro abierto lo dice")
        sheets.app = .excel
        sheets.failure = .needsPermission
        let perm = try await runner.execute(tool: "sheet_read", arguments: ["range": "A1"], approved: false)
        expect(perm.output.hasPrefix("needs_permission"), "hoja: sin Automatización dice dónde darla")
        sheets.failure = .unsavedDocument
        let unsaved = try await runner.execute(tool: "sheet_write",
                                               arguments: ["range": "A1", "values": #"[["x"]]"#], approved: true)
        expect(unsaved.output.hasPrefix("unsaved_document"), "hoja: sin guardar no hay copia, y lo dice")
    } catch {
        expect(false, "hoja: no debe lanzar (\(error))")
    }
}

@MainActor func testTheSheetApprovalShowsTheCells() {
    let detail = ChatCopy.approvalDetail(tool: "sheet_write",
                                         inputJSON: #"{"range":"b2:c2","values":"[[\"Total\",\"=SUM(B3:B9)\"]]","app":"excel"}"#)
    expect(detail.contains("B2:C2") && detail.contains("SUM"), "hoja: la hoja de aprobación muestra rango y celdas")
}

@MainActor func testTheAppleEventScriptsCarryOnlyLiterals() {
    guard let range = SheetRange(a1: "A1:B1") else { return expect(false, "rango") }
    let hostile: [[SheetCell]] = [[.text("\" & (do shell script \"x\") & \""), .number(2)]]
    let excel = AppleEventSheets.writeScript(.excel, range: range, cells: hostile)
    expect(excel.contains("set formula of range \"A1:B1\""), "Excel: un solo set sobre el rango")
    expect(excel.contains(#"{{"\" & (do shell script \"x\") & \"", 2}}"#),
           "Excel: el texto hostil viaja entero dentro de un literal escapado")
    let numbers = AppleEventSheets.writeScript(.numbers, range: range, cells: hostile)
    expectEq(numbers.components(separatedBy: "set value of cell").count - 1, 2, "Numbers: una línea por celda")
    expect(numbers.contains("workbooks") == false && excel.contains("workbooks"),
           "Excel cuenta workbooks; Numbers cuenta documents")
}

@MainActor func testThePrintedPaletteIsTheUIPalette() {
    expectEq(DocumentTheme.ink, Palette.textPrimary.hex, "PDF: la tinta es la de la UI")
    expectEq(DocumentTheme.muted, Palette.textSecondary.hex, "PDF: el texto secundario también")
    expectEq(DocumentTheme.border, Palette.borderDefault.hex, "PDF: los filetes también")
    expectEq(DocumentTheme.surface, Palette.surfaceSecondary.hex, "PDF: la superficie también")
    expectEq(DocumentTheme.success, Palette.statusGreen.hex, "PDF: verde")
    expectEq(DocumentTheme.warning, Palette.statusOrange.hex, "PDF: naranja")
    expectEq(DocumentTheme.danger, Palette.statusRed.hex, "PDF: rojo")
    expectEq(DocumentTheme.link, Palette.link.hex, "PDF: azul")
}
