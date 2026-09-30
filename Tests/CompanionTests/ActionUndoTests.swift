import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 20d B. The way back is mechanical and exact: a file the action made
// goes to the Trash, cells it filled (they were empty) are emptied. Anything
// that no longer matches what the action left is the user's now, so it is
// refused, not guessed.

private final class Sheets: SpreadsheetDriving, @unchecked Sendable {
    let lock = NSLock()
    var written: [(String, [[SheetCell]], String)] = []
    var front = "/tmp/libro.xlsx"
    var shown = [["", ""], ["", ""]]
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { front }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { shown }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        lock.withLock { written.append((range.a1, cells, workbook)) }
        return SheetWriteReceipt(backupPath: "/tmp/b.xlsx", readBack: [])
    }
}

private final class Trashed: @unchecked Sendable {
    let lock = NSLock()
    var urls: [URL] = []
}

private struct Boom: Error {}

private func trashStep(_ url: URL) throws -> UndoReceipt.Undo {
    let info = try FileManager.default.attributesOfItem(atPath: url.path)
    return .trash(path: url.path, size: (info[.size] as? NSNumber)?.intValue ?? 0,
                  modified: info[.modificationDate] as? Date ?? Date())
}

@Test func actionUndoTests() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("undo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let file = dir.appendingPathComponent("Brief.pdf")
    try Data("x".utf8).write(to: file)

    let trashed = Trashed()
    let sheets = Sheets()
    let undoer = ActionUndoer(sheets: sheets, trash: { url in trashed.lock.withLock { trashed.urls.append(url) } })

    let step = try trashStep(file)
    let ok = await undoer.undo(step)
    expect(ok && trashed.urls == [file], "deshacer: un archivo intacto va a la Papelera")

    try Data("editado por la usuaria".utf8).write(to: file)
    let edited = await undoer.undo(step)
    expect(!edited && trashed.urls.count == 1, "deshacer: un archivo que ya cambió es de la usuaria, se queda")

    let gone = await undoer.undo(.trash(path: dir.appendingPathComponent("nada.pdf").path, size: 0, modified: Date()))
    expect(!gone, "deshacer: un archivo que ya no está no es un éxito")
    let relative = await undoer.undo(.trash(path: "Brief.pdf", size: 1, modified: Date()))
    expect(!relative && trashed.urls.count == 1, "deshacer: solo rutas absolutas")
    let folder = try trashStep(dir)
    let notFile = await undoer.undo(folder)
    expect(!notFile && trashed.urls.count == 1, "deshacer: una carpeta no se manda a la Papelera")

    let failing = ActionUndoer(sheets: sheets, trash: { _ in throw Boom() })
    try Data("x".utf8).write(to: file)
    let refused = await failing.undo(try trashStep(file))
    expect(!refused, "deshacer: si la Papelera falla, no es un éxito")

    let expected = [["", ""], ["", ""]]
    let cleared = await undoer.undo(.clearCells(app: .excel, range: "A1:B2", workbook: "/tmp/libro.xlsx", expected: expected))
    expect(cleared, "celdas: se vacían")
    expectEq(sheets.written.first?.0, "A1:B2", "celdas: el rango de la acción")
    expectEq(sheets.written.first?.1, [[.empty, .empty], [.empty, .empty]], "celdas: todas vacías")

    sheets.shown = [["lo escribió la usuaria", ""], ["", ""]]
    let typedOver = await undoer.undo(.clearCells(app: .excel, range: "A1:B2", workbook: "/tmp/libro.xlsx", expected: expected))
    expect(!typedOver && sheets.written.count == 1, "celdas: si la usuaria escribió encima, no se borra")

    sheets.shown = expected
    sheets.front = "/tmp/otro.xlsx"
    let other = await undoer.undo(.clearCells(app: .excel, range: "A1", workbook: "/tmp/libro.xlsx", expected: [[""]]))
    expect(!other && sheets.written.count == 1, "celdas: otro libro al frente, no se toca")
    let badRange = await undoer.undo(.clearCells(app: .excel, range: "zz", workbook: "/tmp/libro.xlsx", expected: []))
    expect(!badRange, "celdas: rango inválido")
}
