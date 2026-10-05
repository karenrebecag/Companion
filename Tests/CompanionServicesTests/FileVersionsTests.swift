import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// PR4b: the copy before (and after) a save lives in a private store, never next
// to the user's file, and never stops the save.

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fv-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private final class FileVersionsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double
    /// Added after every read, for tests that cannot advance the clock between two snapshots themselves.
    private let tick: Double
    init(_ start: Double, tick: Double = 0) { seconds = start; self.tick = tick }
    func advance(_ by: Double) { lock.lock(); seconds += by; lock.unlock() }
    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        defer { seconds += tick }
        return Date(timeIntervalSince1970: seconds)
    }
}

private func store(
    _ root: URL, versions: Int = 20, bytes: Int = 50 * 1024 * 1024, age: TimeInterval = 30 * 86_400,
    total: Int = 1 << 30, clock: FileVersionsTestClock = FileVersionsTestClock(1_790_000_000)
) -> FileVersions {
    FileVersions(root: root, maxVersions: versions, maxBytes: bytes, maxAge: age, maxTotalBytes: total,
                 now: { clock.now() })
}

private func remove(_ url: URL) {
    do { try FileManager.default.removeItem(at: url) } catch {}
}

private func write(_ text: String, to path: String) throws {
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

private func permissions(_ url: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

@Test func aSnapshotStoresTheBytesInAPrivateFolder() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("libro.xlsx").path
    try write("datos", to: file)
    let root = dir.appendingPathComponent("store")
    guard case .saved(let copy) = store(root).snapshot(file, trigger: .preSave) else {
        Issue.record("snapshot: debe guardar")
        return
    }
    expectEq(try String(contentsOf: copy, encoding: .utf8), "datos", "snapshot: los bytes del original")
    expectEq(try permissions(copy), 0o600, "snapshot: archivo 0600")
    expectEq(try permissions(copy.deletingLastPathComponent()), 0o700, "snapshot: carpeta 0700")
    expectEq(try permissions(root), 0o700, "snapshot: raiz 0700")
    expect(!copy.path.hasPrefix(dir.path + "/libro"), "snapshot: no junto al archivo del usuario")
}

@Test func aSymlinkSharesTheHistoryOfItsTarget() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let real = dir.appendingPathComponent("real.xlsx").path
    try write("real", to: real)
    let link = dir.appendingPathComponent("enlace.xlsx").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
    let versions = store(dir.appendingPathComponent("store"))
    _ = versions.snapshot(link, trigger: .preSave)
    expectEq(versions.versions(of: real).count, 1, "enlace: la historia es la del destino")
    guard let stored = versions.versions(of: real).first?.url else { Issue.record("enlace: sin version"); return }
    expectEq(try String(contentsOf: stored, encoding: .utf8), "real", "enlace: los bytes son los del destino")
    expectEq(try FileManager.default.attributesOfItem(atPath: stored.path)[.type] as? FileAttributeType, .typeRegular,
             "enlace: la copia es un archivo regular, no un enlace")
}

@Test func nothingToKeepForAMissingFileOrANonRegularOne() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let versions = store(dir.appendingPathComponent("store"))
    expectEq(versions.snapshot(dir.path + "/no-existe.pdf", trigger: .preSave), .noPrevious, "falta: nada que perder")
    expectEq(versions.snapshot(dir.path, trigger: .preSave), .noPrevious, "carpeta: no es un archivo regular")
}

@Test func aCopyOverTheCapIsNotStoredAndSaysSo() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("grande.pdf").path
    try write("12345678901", to: file)
    let versions = store(dir.appendingPathComponent("store"), bytes: 10)
    expectEq(versions.snapshot(file, trigger: .preSave), .tooLarge(11), "tope: 11 bytes sobre 10")
    expectEq(versions.versions(of: file).count, 0, "tope: no se guardo nada")
}

@Test func onlyTheNewestVersionsOfAFileStay() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    let clock = FileVersionsTestClock(1_790_000_000)
    let versions = store(dir.appendingPathComponent("store"), versions: 3, clock: clock)
    for index in 1...5 {
        try write("v\(index)", to: file)
        _ = versions.snapshot(file, trigger: .preSave)
        clock.advance(1)
    }
    let kept = try versions.versions(of: file).map { try String(contentsOf: $0.url, encoding: .utf8) }
    expectEq(kept, ["v3", "v4", "v5"], "conteo: quedan las 3 mas nuevas, de la mas vieja a la mas nueva")
}

@Test func theDefaultKeepsTwentyVersionsPerFile() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    let clock = FileVersionsTestClock(1_790_000_000)
    let versions = FileVersions(root: dir.appendingPathComponent("store"), now: { clock.now() })
    try write("x", to: file)
    for _ in 1...22 {
        _ = versions.snapshot(file, trigger: .postSave)
        clock.advance(1)
    }
    expectEq(versions.versions(of: file).count, 20, "defecto: 20 versiones por archivo")
}

@Test func aVersionOlderThanThirtyDaysExpires() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    let other = dir.appendingPathComponent("b.pdf").path
    try write("viejo", to: file)
    try write("otro", to: other)
    let clock = FileVersionsTestClock(1_790_000_000)
    let versions = store(dir.appendingPathComponent("store"), clock: clock)
    _ = versions.snapshot(file, trigger: .preSave)
    clock.advance(31 * 86_400)
    _ = versions.snapshot(other, trigger: .preSave)
    expectEq(versions.versions(of: file).count, 0, "edad: a los 31 dias la version de otro archivo expira")
    expectEq(versions.versions(of: other).count, 1, "edad: la nueva queda")
}

@Test func theGlobalCapPrunesTheOldestAcrossFiles() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let a = dir.appendingPathComponent("a.pdf").path
    let b = dir.appendingPathComponent("b.pdf").path
    try write("0123456789", to: a)
    try write("abcdefghij", to: b)
    let clock = FileVersionsTestClock(1_790_000_000)
    let versions = store(dir.appendingPathComponent("store"), total: 25, clock: clock)
    _ = versions.snapshot(a, trigger: .preSave)
    clock.advance(1)
    _ = versions.snapshot(b, trigger: .preSave)
    clock.advance(1)
    _ = versions.snapshot(b, trigger: .postSave)
    expectEq(versions.versions(of: a).count, 0, "tope global: lo mas viejo se poda primero")
    expectEq(versions.versions(of: b).count, 2, "tope global: 20 bytes caben en 25")
}

@Test func theTriggerIsRecordedForListing() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    try write("v1", to: file)
    let clock = FileVersionsTestClock(1_790_000_000)
    let versions = store(dir.appendingPathComponent("store"), clock: clock)
    _ = versions.snapshot(file, trigger: .preSave)
    clock.advance(1)
    _ = versions.snapshot(file, trigger: .postSave)
    expectEq(versions.versions(of: file).map(\.trigger), [.preSave, .postSave], "disparador: pre y post quedan anotados")
}

@Test func anUnwritableRootFailsWithoutThrowing() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let blocker = dir.appendingPathComponent("not-a-folder").path
    try write("x", to: blocker)
    let file = dir.appendingPathComponent("a.pdf").path
    try write("v1", to: file)
    expectEq(store(URL(fileURLWithPath: blocker + "/store")).snapshot(file, trigger: .preSave), .failed,
             "raiz inservible: falla en silencio, sin lanzar")
}

// MARK: - Through the tools

private struct FakeDocuments: DocumentRendering {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        try Data("%PDF-fake".utf8).write(to: url)
        return DocumentReceipt(pages: 1, bytes: 9)
    }
}

private final class FakeSheets: SpreadsheetDriving, @unchecked Sendable {
    let path: String
    var written = false
    init(path: String) { self.path = path }
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { path }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        written = true
        return SheetWriteReceipt(readBack: [["1"]])
    }
}

private let doc = #"{"title":"X","blocks":[{"type":"paragraph","text":"hola"}]}"#

private func unwritableRoot(in dir: URL) throws -> URL {
    let blocker = dir.appendingPathComponent("blocker").path
    try write("x", to: blocker)
    return URL(fileURLWithPath: blocker + "/store")
}

@Test func overwritingADocumentKeepsBeforeAndAfterAndNeverTouchesTheFolder() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let root = dir.appendingPathComponent("store")
    let file = dir.appendingPathComponent("q3.pdf").path
    try write("ORIGINAL", to: file)
    let versions = store(root, clock: FileVersionsTestClock(1_790_000_000, tick: 1))
    let runner = NativeToolRunner(workdir: dir.path, places: nil, documents: FakeDocuments(), versions: versions)
    let result = try await runner.execute(tool: "create_document", arguments: ["path": "q3.pdf", "document": doc],
                                          approved: true)
    expect(result.ok, "documento: se sobrescribe")
    expect(result.output.contains("a previous version was kept"), "documento: dice que se guardo la anterior")
    expect(!result.output.contains(root.path) && !result.output.contains("store"), "documento: ninguna ruta del almacen")
    let kept = versions.versions(of: file)
    expectEq(kept.map(\.trigger), [.preSave, .postSave], "documento: pre y post")
    expectEq(try kept.map { try String(contentsOf: $0.url, encoding: .utf8) }, ["ORIGINAL", "%PDF-fake"],
             "documento: la anterior intacta y la nueva")
    let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("-backup-") }
    expectEq(siblings, [], "documento: ninguna copia -backup- junto al original")
}

@Test func aNewDocumentSaysNothingAboutAPreviousVersion() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let runner = NativeToolRunner(workdir: dir.path, places: nil, documents: FakeDocuments(),
                                  versions: store(dir.appendingPathComponent("store")))
    let result = try await runner.execute(tool: "create_document", arguments: ["path": "nuevo.pdf", "document": doc],
                                          approved: true)
    expect(result.ok && !result.output.contains("previous version"), "documento nuevo: sin mencion de version")
}

@Test func anUnwritableStoreStillLetsTheOverwriteProceed() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let root = try unwritableRoot(in: dir)
    let file = dir.appendingPathComponent("q3.pdf").path
    try write("ORIGINAL", to: file)
    let runner = NativeToolRunner(workdir: dir.path, places: nil, documents: FakeDocuments(),
                                  versions: store(root))
    let result = try await runner.execute(tool: "create_document", arguments: ["path": "q3.pdf", "document": doc],
                                          approved: true)
    expect(result.ok, "fail-open: el documento se escribe")
    expectEq(try String(contentsOfFile: file, encoding: .utf8), "%PDF-fake", "fail-open: el archivo tiene lo nuevo")
    expect(result.output.contains("no previous version could be kept"), "fail-open: lo dice")
    expect(!result.output.contains(root.path), "fail-open: sin rutas del almacen")
}

@Test func aTooLargePreviousFileIsOverwrittenAndTheOutputSaysWhy() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("q3.pdf").path
    try write("0123456789ABC", to: file)
    let runner = NativeToolRunner(workdir: dir.path, places: nil, documents: FakeDocuments(),
                                  versions: store(dir.appendingPathComponent("store"), bytes: 10))
    let result = try await runner.execute(tool: "create_document", arguments: ["path": "q3.pdf", "document": doc],
                                          approved: true)
    expect(result.ok && result.output.contains("no previous version could be kept"), "grande: no se guardo")
    expect(result.output.contains("50 MB"), "grande: dice el tope")
}

@Test func aSheetWriteKeepsOnePreWriteVersionAndNeverAddsASibling() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let root = dir.appendingPathComponent("store")
    let book = dir.appendingPathComponent("libro.xlsx").path
    try write("LIBRO", to: book)
    let versions = store(root)
    let sheets = FakeSheets(path: book)
    let runner = NativeToolRunner(workdir: dir.path, places: nil, sheets: sheets, versions: versions)
    let result = try await runner.execute(
        tool: "sheet_write",
        arguments: ["app": "excel", "range": "A1", "values": "[[1]]", "workbook": book], approved: true)
    expect(result.ok && sheets.written, "hoja: se escribe")
    expect(result.output.contains("a previous version"), "hoja: dice que se guardo la anterior")
    expect(!result.output.contains(root.path) && !result.output.contains("-backup-"), "hoja: sin rutas ni -backup-")
    expectEq(versions.versions(of: book).map(\.trigger), [.preSave], "hoja: solo pre; Companion no manda Save")
    let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("-backup-") }
    expectEq(siblings, [], "hoja: ninguna copia -backup- junto al libro")
}

@Test func anUnwritableStoreStillLetsASheetWriteProceed() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let book = dir.appendingPathComponent("libro.xlsx").path
    try write("LIBRO", to: book)
    let sheets = FakeSheets(path: book)
    let runner = NativeToolRunner(workdir: dir.path, places: nil, sheets: sheets,
                                  versions: store(try unwritableRoot(in: dir)))
    let result = try await runner.execute(
        tool: "sheet_write",
        arguments: ["app": "excel", "range": "A1", "values": "[[1]]", "workbook": book], approved: true)
    expect(result.ok && sheets.written, "hoja fail-open: se escribe igual")
    expect(result.output.contains("no previous version could be kept"), "hoja fail-open: lo dice")
}

// MARK: - Review round

@Test func theNewestCopySurvivesACapSmallerThanOneFile() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    try write("0123456789", to: file)
    for clock in [FileVersionsTestClock(1_790_000_000, tick: 1), FileVersionsTestClock(1_790_000_000)] {
        let versions = store(dir.appendingPathComponent("store-\(UUID().uuidString)"), total: 5, clock: clock)
        guard case .saved(let url) = versions.snapshot(file, trigger: .preSave) else {
            Issue.record("tope diminuto: debe devolver .saved"); return
        }
        expect(FileManager.default.fileExists(atPath: url.path), "tope diminuto: la copia prometida existe")
        expectEq(versions.versions(of: file).count, 1, "tope diminuto: queda exactamente la nueva")
        _ = versions.snapshot(file, trigger: .postSave)
        expectEq(versions.versions(of: file).count, 1, "tope diminuto: la siguiente reemplaza a la anterior")
    }
}

@Test func twoSnapshotsInTheSameInstantBothSurviveIntact() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    let versions = store(dir.appendingPathComponent("store"), clock: FileVersionsTestClock(1_790_000_000))
    try write("uno", to: file)
    _ = versions.snapshot(file, trigger: .preSave)
    try write("dos", to: file)
    _ = versions.snapshot(file, trigger: .preSave)
    let kept = try versions.versions(of: file).map { try String(contentsOf: $0.url, encoding: .utf8) }
    expectEq(Set(kept), ["uno", "dos"], "mismo instante: dos versiones, ninguna pisada")
}

@Test func pruningNeverTouchesWhatTheStoreDidNotMake() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let root = dir.appendingPathComponent("store")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let foreignFile = root.appendingPathComponent("notas.txt")
    try write("mio", to: foreignFile.path)
    let foreignDir = root.appendingPathComponent("carpeta-ajena")
    try FileManager.default.createDirectory(at: foreignDir, withIntermediateDirectories: true)
    // A link named like a store folder must be left alone, and what it points at too.
    let outside = dir.appendingPathComponent("fuera")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let victim = outside.appendingPathComponent("1-preSave-aaaaaaaa-viejo.pdf")
    try write("no me borres", to: victim.path)
    let link = root.appendingPathComponent(String(repeating: "a", count: 24))
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    let file = dir.appendingPathComponent("a.pdf").path
    try write("x", to: file)
    _ = store(root).snapshot(file, trigger: .preSave)
    expect(FileManager.default.fileExists(atPath: foreignFile.path), "ajeno: un archivo suelto sigue ahi")
    expect(FileManager.default.fileExists(atPath: foreignDir.path), "ajeno: una carpeta vacia que no es nuestra sigue ahi")
    expect(FileManager.default.fileExists(atPath: victim.path), "enlace: lo que apunta fuera no se borra")
    expect(FileManager.default.fileExists(atPath: link.path), "enlace: el enlace sigue ahi")
}

@Test func anEmptyStoreFolderOfAnotherFileIsSweptButNotTheFreshOne() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let root = dir.appendingPathComponent("store")
    let stale = root.appendingPathComponent(String(repeating: "b", count: 24))
    try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_789_999_000)],
                                          ofItemAtPath: stale.path)
    let file = dir.appendingPathComponent("a.pdf").path
    try write("x", to: file)
    guard case .saved(let url) = store(root).snapshot(file, trigger: .preSave) else { Issue.record("sin copia"); return }
    expect(!FileManager.default.fileExists(atPath: stale.path), "barrido: la carpeta vacia nuestra se quita")
    expect(FileManager.default.fileExists(atPath: url.path), "barrido: la carpeta de la copia nueva queda")
}

// MARK: - Failures around the save

private struct FailingDocuments: DocumentRendering {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        throw DocumentError.unsupportedFormat
    }
}

/// Locks the store's folders mid-render, so the post snapshot cannot be written.
private struct LockingDocuments: DocumentRendering {
    let root: URL
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        try Data("%PDF-fake".utf8).write(to: url)
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                                  ofItemAtPath: root.appendingPathComponent(name).path)
        }
        return DocumentReceipt(pages: 1, bytes: 9)
    }
}

@Test func aFailedRenderKeepsThePreVersionAndTakesNoPostSnapshot() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("q3.pdf").path
    try write("ORIGINAL", to: file)
    let versions = store(dir.appendingPathComponent("store"), clock: FileVersionsTestClock(1_790_000_000, tick: 1))
    let runner = NativeToolRunner(workdir: dir.path, places: nil, documents: FailingDocuments(), versions: versions)
    let result = try await runner.execute(tool: "create_document", arguments: ["path": "q3.pdf", "document": doc],
                                          approved: true)
    expect(!result.ok, "render fallido: no es ok")
    expectEq(versions.versions(of: file).map(\.trigger), [.preSave], "render fallido: solo la previa")
}

@Test func aFailedPostSnapshotDoesNotFailTheSave() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let root = dir.appendingPathComponent("store")
    let file = dir.appendingPathComponent("q3.pdf").path
    try write("ORIGINAL", to: file)
    let versions = store(root, clock: FileVersionsTestClock(1_790_000_000, tick: 1))
    let runner = NativeToolRunner(workdir: dir.path, places: nil, documents: LockingDocuments(root: root),
                                  versions: versions)
    defer {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
            do { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent(name).path) } catch {}
        }
    }
    let result = try await runner.execute(tool: "create_document", arguments: ["path": "q3.pdf", "document": doc],
                                          approved: true)
    expect(result.ok, "post fallido: el guardado sigue ok")
    expectEq(try String(contentsOfFile: file, encoding: .utf8), "%PDF-fake", "post fallido: el archivo tiene lo nuevo")
    expectEq(versions.versions(of: file).map(\.trigger), [.preSave], "post fallido: solo queda la previa")
}

// MARK: - Nothing resolves to the real store

@Test func runnersBuiltWithoutAStoreNeverResolveToTheRealOne() {
    let native = NativeToolRunner(workdir: nil, places: nil)
    let parent = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []))
    expect(native.versions == nil, "guarda: NativeToolRunner por defecto no tiene almacen")
    expect(parent.versions == nil, "guarda: ParentToolRunner por defecto no tiene almacen")
    expect(parent.nativeRunner.versions == nil, "guarda: el runner nativo del padre tampoco")
}

@Test func theStandardRootIsOnlyReachedByAskingForIt() {
    let support = URL(fileURLWithPath: "/tmp/fv-support")
    expectEq(FileVersions.standard(appSupport: support).rootPath, "/tmp/fv-support/Companion/file-versions",
             "standard: Companion/file-versions bajo Application Support")
}

// MARK: - Second review round

private struct ApprovingApprovals: ApprovalsProvider {
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        ApprovalResponse(requestId: approval.requestId, approved: true)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { true }
    func remembered(_ approval: ApprovalRequest) async -> Bool? { nil }
}

/// One tool call, then a plain answer: the loop must not write twice.
private final class OneShotProvider: ChatProvider, @unchecked Sendable {
    let name: String
    let arguments: String
    init(name: String, arguments: String) { self.name = name; self.arguments = arguments }
    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        let answered = history.contains { $0.role == .tool }
        return AsyncThrowingStream { continuation in
            continuation.yield(answered ? .text("listo")
                               : .toolCalls([ToolCallRef(id: "c1", name: name, arguments: arguments)]))
            continuation.finish()
        }
    }
    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

@Test @MainActor func theSpecialistLaneSnapshotsThroughTheStoreItWasGiven() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("informe.pdf").path
    try write("ORIGINAL", to: file)
    let versions = store(dir.appendingPathComponent("store"), clock: FileVersionsTestClock(1_790_000_000, tick: 1))
    let args = "{\"path\":\"informe.pdf\",\"document\":\"{\\\"title\\\":\\\"x\\\",\\\"blocks\\\":[{\\\"type\\\":\\\"paragraph\\\",\\\"text\\\":\\\"hola\\\"}]}\"}"
    let executor = NativeExecutor(
        descriptor: ExecutorCatalog.native,
        chatProvider: OneShotProvider(name: "create_document", arguments: args),
        config: Config(workdir: dir.path), approvals: ApprovingApprovals(),
        documents: FakeDocuments(), versions: versions)
    let (stream, sink) = AsyncStream<JobEvent>.makeStream()
    let drain = Task { for await _ in stream {} }
    _ = try await executor.run(JobRequest(id: "j", goal: "g", context: ""), events: sink)
    sink.finish()
    await drain.value
    expectEq(versions.versions(of: file).map(\.trigger), [.preSave, .postSave], "especialista: pre y post en el almacen dado")
    expectEq(try String(contentsOf: versions.versions(of: file)[0].url, encoding: .utf8), "ORIGINAL",
             "especialista: la previa es el original")
}

@Test func aFreshEmptyFolderIsNotSweptButAnOldOneIs() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let root = dir.appendingPathComponent("store")
    let clock = FileVersionsTestClock(1_790_000_000)
    let young = root.appendingPathComponent(String(repeating: "c", count: 24))
    let old = root.appendingPathComponent(String(repeating: "d", count: 24))
    for (folder, age) in [(young, 5.0), (old, 120.0)] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_790_000_000 - age)],
                                              ofItemAtPath: folder.path)
    }
    let file = dir.appendingPathComponent("a.pdf").path
    try write("x", to: file)
    _ = store(root, clock: clock).snapshot(file, trigger: .preSave)
    expect(FileManager.default.fileExists(atPath: young.path), "carrera: la carpeta vacia recien creada sobrevive")
    expect(!FileManager.default.fileExists(atPath: old.path), "carrera: la vacia y vieja se barre")
}

@Test func aFileOfExactlyTheCapIsStoredAndOneByteMoreIsNot() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    let versions = store(dir.appendingPathComponent("store"), bytes: 10)
    try write("0123456789", to: file)
    guard case .saved = versions.snapshot(file, trigger: .preSave) else { Issue.record("limite: 10 de 10 se guarda"); return }
    try write("0123456789A", to: file)
    expectEq(versions.snapshot(file, trigger: .preSave), .tooLarge(11), "limite: 11 de 10 no")
}

@Test func anEntryExactlyAsOldAsTheMaxAgeSurvivesAndOneSecondOlderDoesNot() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let a = dir.appendingPathComponent("a.pdf").path
    let b = dir.appendingPathComponent("b.pdf").path
    try write("a", to: a)
    try write("b", to: b)
    let clock = FileVersionsTestClock(1_790_000_000)
    let versions = store(dir.appendingPathComponent("store"), age: 100, clock: clock)
    _ = versions.snapshot(a, trigger: .preSave)
    clock.advance(100)
    _ = versions.snapshot(b, trigger: .preSave)
    expectEq(versions.versions(of: a).count, 1, "edad: justo maxAge sobrevive")
    clock.advance(1)
    _ = versions.snapshot(b, trigger: .postSave)
    expectEq(versions.versions(of: a).count, 0, "edad: maxAge + 1 s se quita")
}

private final class ThrowingSheets: SpreadsheetDriving, @unchecked Sendable {
    let path: String
    init(path: String) { self.path = path }
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { path }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        throw SheetError.appFailed
    }
}

@Test func aSheetWriteThatThrowsKeepsThePreVersionAndSurfacesTheFailure() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let book = dir.appendingPathComponent("libro.xlsx").path
    try write("LIBRO", to: book)
    let versions = store(dir.appendingPathComponent("store"))
    let runner = NativeToolRunner(workdir: dir.path, places: nil, sheets: ThrowingSheets(path: book), versions: versions)
    let result = try await runner.execute(
        tool: "sheet_write",
        arguments: ["app": "excel", "range": "A1", "values": "[[1]]", "workbook": book], approved: true)
    expect(!result.ok && result.output.hasPrefix("app_failed"), "hoja que falla: el fallo sale")
    expectEq(versions.versions(of: book).map(\.trigger), [.preSave], "hoja que falla: la previa queda")
}
