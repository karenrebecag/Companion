import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D4 follow-up: a write whose read-back fails says so honestly.

private struct UnverifiedSheets: SpreadsheetDriving {
    let path: String
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { path }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        SheetWriteReceipt(readBack: [], readBackUnavailable: true)
    }
}

@Test func aWriteWithoutReadBackIsNotReportedAsNotWritten() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sb-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let book = dir.appendingPathComponent("l.xlsx").path
    try "LIBRO".write(toFile: book, atomically: true, encoding: .utf8)
    let store = FileVersions(root: dir.appendingPathComponent("store"))
    let runner = NativeToolRunner(workdir: dir.path, places: nil,
                                  documents: nil, sheets: UnverifiedSheets(path: book), versions: store)
    let result = try await runner.execute(
        tool: "sheet_write",
        arguments: ["app": "excel", "range": "A1", "values": "[[1]]", "workbook": book], approved: true)
    expect(result.ok, "recibo: la escritura ocurrió")
    expect(!result.output.contains("nothing was written"), "recibo: no dice que no se escribió")
    expect(result.output.contains("could not be read back"), "recibo: dice que la relectura no fue posible")
    expect(result.output.contains("a previous version was kept"), "recibo: sin relectura tambien dice la version")
}

private struct UnsavedSheets: SpreadsheetDriving {
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { throw SheetError.unsavedDocument }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        SheetWriteReceipt(readBack: [])
    }
}

@Test func anUnsavedWorkbookIsRefusedWithTheNewHint() async throws {
    let runner = NativeToolRunner(workdir: FileManager.default.temporaryDirectory.path, places: nil,
                                  documents: nil, sheets: UnsavedSheets())
    let result = try await runner.execute(
        tool: "sheet_write",
        arguments: ["app": "excel", "range": "A1", "values": "[[1]]", "workbook": "/tmp/l.xlsx"], approved: true)
    expect(!result.ok && result.output.hasPrefix("unsaved_document"), "sin guardar: se rechaza")
    expect(result.output.contains("a previous version kept") && !result.output.contains("backup"),
           "sin guardar: el texto habla de versiones, no de copias")
}
