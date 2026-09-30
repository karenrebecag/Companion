import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 20c D4 follow-up: the sheet backup is a real copy of the real file,
// never overwrites another, and a write whose read-back fails says so honestly.

private func scratch() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sb-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath().path
}

private let moment = Date(timeIntervalSince1970: 1_790_000_000)

@Test func aSymlinkedWorkbookBacksUpTheRealData() throws {
    let dir = try scratch()
    let real = dir + "/real.xlsx"
    try "datos reales".write(toFile: real, atomically: true, encoding: .utf8)
    let link = dir + "/enlace.xlsx"
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
    let backup = try DocumentBackup.copy(of: link, at: moment)
    let attributes = try FileManager.default.attributesOfItem(atPath: backup)
    expect(attributes[.type] as? FileAttributeType == .typeRegular, "copia: un archivo real, no un enlace")
    expectEq(try String(contentsOfFile: backup, encoding: .utf8), "datos reales", "copia: con los datos del libro")
    expect(backup.hasPrefix(dir + "/real-backup-"), "copia: junto al archivo real")
}

@Test func aSecondBackupInTheSameSecondGetsASuffix() throws {
    let dir = try scratch()
    let file = dir + "/libro.xlsx"
    try "v1".write(toFile: file, atomically: true, encoding: .utf8)
    let first = try DocumentBackup.copy(of: file, at: moment)
    try "v2".write(toFile: file, atomically: true, encoding: .utf8)
    let second = try DocumentBackup.copy(of: file, at: moment)
    expect(first != second && second.hasSuffix("-2.xlsx"), "copia: la segunda del mismo segundo lleva -2")
    expectEq(try String(contentsOfFile: first, encoding: .utf8), "v1", "copia: la primera no se pisa")
    expectEq(try String(contentsOfFile: second, encoding: .utf8), "v2", "copia: la segunda guarda su versión")
}

private struct UnverifiedSheets: SpreadsheetDriving {
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { "/tmp/l.xlsx" }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        SheetWriteReceipt(backupPath: "/tmp/l-backup-x.xlsx", readBack: [], readBackUnavailable: true)
    }
}

@Test func aWriteWithoutReadBackIsNotReportedAsNotWritten() async throws {
    let runner = NativeToolRunner(workdir: FileManager.default.temporaryDirectory.path, places: nil,
                                  documents: nil, sheets: UnverifiedSheets())
    let result = try await runner.execute(
        tool: "sheet_write",
        arguments: ["app": "excel", "range": "A1", "values": "[[1]]", "workbook": "/tmp/l.xlsx"], approved: true)
    expect(result.ok, "recibo: la escritura ocurrió")
    expect(!result.output.contains("nothing was written"), "recibo: no dice que no se escribió")
    expect(result.output.contains("/tmp/l-backup-x.xlsx"), "recibo: nombra la copia")
    expect(result.output.contains("could not be read back"), "recibo: dice que la relectura no fue posible")
}
