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
    expectEq(shell, .act, "ls: lectura, sin hoja")
    let destructive = await runner.actionBand(tool: "run_shell", arguments: ["command": "rm -rf x"])
    expectEq(destructive, .critical, "rm: sigue pidiendo hoja")

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

/// A cloned repo's .git/config can make `git status` run a program
/// (core.fsmonitor). The runner reads that config before letting git act.
@Test func gitReadsActOnlyWhenTheRepoConfigIsInert() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitband-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let root = dir.resolvingSymlinksInPath().path
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    git.arguments = ["init", "-q", root]
    try git.run()
    git.waitUntilExit()
    let runner = NativeToolRunner(
        workdir: root, places: nil, documents: Documents(), sheets: Sheets(rows: [["", ""]]))

    let clean = await runner.actionBand(tool: "run_shell", arguments: ["command": "git status"])
    expectEq(clean, .act, "repo recien creado: git status sin hoja")

    let config = URL(fileURLWithPath: root).appendingPathComponent(".git/config")
    let base = try String(contentsOf: config, encoding: .utf8)
    let hostile = base + "[core]\n\tfsmonitor = /tmp/pwn.sh\n"
    try hostile.write(to: config, atomically: true, encoding: .utf8)
    let armed = await runner.actionBand(tool: "run_shell", arguments: ["command": "git status"])
    expectEq(armed, .critical, "core.fsmonitor en el repo: git status pide hoja")

    let ls = await runner.actionBand(tool: "run_shell", arguments: ["command": "ls"])
    expectEq(ls, .act, "la config de git no toca a ls")

    // Each section that can name a program, and an include that could hide one.
    for (section, body) in [("filter \"x\"", "clean = /tmp/pwn.sh"), ("diff \"x\"", "textconv = /tmp/pwn.sh"),
                            ("include", "path = /tmp/other.cfg"), ("core", "pager = /tmp/pwn.sh"),
                            ("alias", "st = !/tmp/pwn.sh"), ("includeIf \"gitdir:/\"", "path = /tmp/x.cfg"),
                            ("core", "sshCommand = /tmp/pwn.sh"), ("core", "hooksPath = /tmp/hooks"),
                            ("user", "name = \"a\\n[core]\\n\\tfsmonitor = /tmp/pwn.sh\""),
                            ("core", "= sin clave")] {
        try (base + "[\(section)]\n\t\(body)\n").write(to: config, atomically: true, encoding: .utf8)
        let band = await runner.actionBand(tool: "run_shell", arguments: ["command": "git diff"])
        expectEq(band, .critical, "\(section) en el repo: git diff pide hoja")
    }
}

@Test func gitReadsActOutsideARepo() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nogit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let runner = NativeToolRunner(
        workdir: dir.resolvingSymlinksInPath().path, places: nil, documents: Documents(),
        sheets: Sheets(rows: [["", ""]]))
    let band = await runner.actionBand(tool: "run_shell", arguments: ["command": "git status"])
    expectEq(band, .act, "fuera de un repo no hay config local que ejecute nada")
}

@Test func gitReadsStillActWithAnOrdinaryClone() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clone-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: dir) } catch {} }
    let root = dir.resolvingSymlinksInPath().path
    for args in [["init", "-q"], ["remote", "add", "origin", "https://github.com/a/b.git"],
                 ["config", "branch.main.remote", "origin"], ["config", "branch.main.merge", "refs/heads/main"],
                 ["config", "user.name", "Karen"]] {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = args
        git.currentDirectoryURL = dir
        try git.run()
        git.waitUntilExit()
    }
    let runner = NativeToolRunner(workdir: root, places: nil, documents: Documents(), sheets: Sheets(rows: [["", ""]]))
    let band = await runner.actionBand(tool: "run_shell", arguments: ["command": "git log --oneline"])
    expectEq(band, .act, "un clon normal (remote, branch, user) sigue sin hoja")
}
