import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 20d B. The runner reads the disk and the sheet itself: the band never
// rests on what the model said about the target.

private final class Sheets: SpreadsheetDriving, @unchecked Sendable {
    let rows: [[String]]
    let fails: Bool
    init(rows: [[String]], fails: Bool = false) { self.rows = rows; self.fails = fails }
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { "/tmp/libro.xlsx" }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] {
        if fails { throw SheetError.workbookChanged }
        return rows
    }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        SheetWriteReceipt(backupPath: "/tmp/b.xlsx", readBack: [])
    }
}

private struct Documents: DocumentRendering {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        DocumentReceipt(pages: 1, bytes: 1)
    }
}

@Test func nativeActionBandTests() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nab-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let root = dir.resolvingSymlinksInPath().path
    let runner = NativeToolRunner(
        workdir: root, places: nil, documents: Documents(), sheets: Sheets(rows: [["", ""]]))

    let fresh = await runner.actionBand(tool: "create_document", arguments: ["path": "Brief.pdf"])
    expectEq(fresh, .act, "documento nuevo dentro de la carpeta: hacer")
    try Data("x".utf8).write(to: dir.appendingPathComponent("Brief.pdf"))
    let taken = await runner.actionBand(tool: "create_document", arguments: ["path": "Brief.pdf"])
    expectEq(taken, .critical, "documento que ya existe: pisarlo es crítico")
    let outside = await runner.actionBand(tool: "write_file", arguments: ["path": "/etc/nope.txt", "content": "x"])
    expectEq(outside, .critical, "fuera de la carpeta: crítico")
    let newFile = await runner.actionBand(tool: "write_file", arguments: ["path": "notes.txt", "content": "x"])
    expectEq(newFile, .act, "archivo nuevo en la carpeta: hacer")
    let edit = await runner.actionBand(tool: "edit_file", arguments: ["path": "notes.txt"])
    expectEq(edit, .critical, "editar siempre modifica lo que hay")
    let shell = await runner.actionBand(tool: "run_shell", arguments: ["command": "ls"])
    expectEq(shell, .critical, "shell: crítico")

    let link = dir.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/tmp")
    let viaLink = await runner.actionBand(tool: "write_file", arguments: ["path": "escape/x.txt", "content": "x"])
    expectEq(viaLink, .critical, "un symlink que sale de la carpeta: crítico")

    // A visible link into a hidden folder is judged by where it lands.
    let hidden = dir.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        atPath: dir.appendingPathComponent("cmds").path, withDestinationPath: hidden.path)
    let viaHidden = await runner.actionBand(tool: "write_file", arguments: ["path": "cmds/x.md", "content": "x"])
    expectEq(viaHidden, .critical, "un enlace visible hacia una carpeta oculta: crítico")
    let slash = NativeToolRunner(workdir: "/", places: nil)
    let atRoot = await slash.actionBand(tool: "write_file", arguments: ["path": "/tmp/nuevo-\(UUID().uuidString).txt", "content": "x"])
    expectEq(atRoot, .critical, "workdir /: no es una zona")

    // A dangling link is something already there, not a new name.
    try FileManager.default.createSymbolicLink(
        atPath: dir.appendingPathComponent("dangling.pdf").path, withDestinationPath: "/tmp/no-such-\(UUID().uuidString).pdf")
    let dangling = await runner.actionBand(tool: "create_document", arguments: ["path": "dangling.pdf"])
    expectEq(dangling, .critical, "symlink colgante: no es un nombre nuevo")

    // The default workdir is the whole home: a new file there can be a tool's config.
    let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
    let wide = NativeToolRunner(workdir: home, places: nil, documents: Documents())
    let inHome = await wide.actionBand(tool: "write_file", arguments: ["path": "\(home)/nuevo-\(UUID().uuidString).txt", "content": "x"])
    expectEq(inHome, .critical, "workdir = home: nada corre sin hoja")
    let narrow = NativeToolRunner(workdir: "\(home)/Documents", places: nil, documents: Documents())
    let library = await narrow.actionBand(
        tool: "write_file", arguments: ["path": "\(home)/Library/Application Support/Claude/x.json", "content": "x"])
    expectEq(library, .critical, "Library: nunca")
    let support = SkillsLocation.standard().root.path
    let appOwned = NativeToolRunner(workdir: home + "/Documents", places: nil, skills: SkillsLocation.standard())
    for path in ["memory/notes/x.md", "skills/custom/foo/skill.md", "Knowledge/foo/references/a.md"] {
        let planted = await appOwned.actionBand(tool: "write_file", arguments: ["path": "\(support)/\(path)", "content": "x"])
        expectEq(planted, .critical, "carpeta de la app: \(path)")
    }

    let range = ["range": "A1:B1", "values": "[[1,2]]"]
    let empty = await runner.actionBand(tool: "sheet_write", arguments: range)
    expectEq(empty, .act, "celdas vacías: solo agrega")
    let busy = NativeToolRunner(workdir: root, places: nil, sheets: Sheets(rows: [["", "Total"]]))
    let occupied = await busy.actionBand(tool: "sheet_write", arguments: range)
    expectEq(occupied, .critical, "celdas con valor: pisa")
    let broken = NativeToolRunner(workdir: root, places: nil, sheets: Sheets(rows: [], fails: true))
    let unread = await broken.actionBand(tool: "sheet_write", arguments: range)
    expectEq(unread, .critical, "rango que no se pudo leer: sube")
    let badRange = await runner.actionBand(tool: "sheet_write", arguments: ["range": "zz", "values": "[]"])
    expectEq(badRange, .critical, "rango inválido: sube")
}
