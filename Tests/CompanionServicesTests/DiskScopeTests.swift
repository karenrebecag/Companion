import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// The file tools reach the whole disk (docs/DECISIONS.md, 2026-10-16): what
// stays closed, what each action costs, and how macOS privacy answers.

private func scratchDir() throws -> String {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("disk-\(UUID().uuidString)").resolvingSymlinksInPath().path
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

@Test func readsAFileOutsideAnyGrantedFolderWithoutAsking() async throws {
    let elsewhere = try scratchDir()
    let work = try scratchDir()
    defer {
        do { try FileManager.default.removeItem(atPath: elsewhere) } catch {}
        do { try FileManager.default.removeItem(atPath: work) } catch {}
    }
    try "hola".write(toFile: elsewhere + "/x.txt", atomically: true, encoding: .utf8)
    let runner = NativeToolRunner(workdir: work, places: nil)
    let read = try await runner.execute(tool: "read_file", arguments: ["path": elsewhere + "/x.txt"], approved: false)
    expect(read.ok && read.output == "hola", "read: \(read.output)")
    let listed = try await runner.execute(tool: "list_directory", arguments: ["path": elsewhere], approved: false)
    expect(listed.ok && listed.output.contains("x.txt"), "list: \(listed.output)")
    let band = await runner.actionBand(tool: "read_file", arguments: ["path": elsewhere + "/x.txt"])
    expectEq(band, .act, "leer no pregunta")
}

@Test func readsWithoutAnyWorkdirAtAll() async throws {
    let elsewhere = try scratchDir()
    defer { do { try FileManager.default.removeItem(atPath: elsewhere) } catch {} }
    try "hola".write(toFile: elsewhere + "/x.txt", atomically: true, encoding: .utf8)
    let runner = NativeToolRunner(workdir: nil, places: nil)
    let read = try await runner.execute(tool: "read_file", arguments: ["path": elsewhere + "/x.txt"], approved: false)
    expect(read.ok, "sin carpeta concedida: \(read.output)")
}

@Test func systemAndCredentialPathsStayClosed() async throws {
    let runner = NativeToolRunner(workdir: nil, places: nil)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let closed = [
        "/etc/passwd", "/private/etc/hosts", "/System/Library/CoreServices/SystemVersion.plist",
        "/usr/bin/true", home + "/.ssh/id_rsa", home + "/.aws/credentials",
        home + "/.config/gcloud/credentials.db", home + "/Library/Keychains/login.keychain-db",
        home + "/Library/Application Support/Companion/memory/x.md",
    ]
    for path in closed {
        let read = try await runner.execute(tool: "read_file", arguments: ["path": path], approved: false)
        expect(!read.ok && read.output.contains("protected location"), "read \(path): \(read.output)")
        let listed = try await runner.execute(tool: "list_directory", arguments: ["path": path], approved: false)
        expect(!listed.ok && listed.output.contains("protected location"), "list \(path): \(listed.output)")
    }
}

@Test func aDotDotCannotWalkIntoAProtectedPath() async throws {
    let work = try scratchDir()
    defer { do { try FileManager.default.removeItem(atPath: work) } catch {} }
    let runner = NativeToolRunner(workdir: work, places: nil)
    let read = try await runner.execute(
        tool: "read_file", arguments: ["path": "../../../../../../../../etc/passwd"], approved: false)
    expect(!read.ok && read.output.contains("protected location"), read.output)
}

@Test func creatingConfirmsOverwritingAndDeletingAreCritical() async throws {
    let elsewhere = try scratchDir()
    defer { do { try FileManager.default.removeItem(atPath: elsewhere) } catch {} }
    let runner = NativeToolRunner(workdir: nil, places: nil, documents: nil)
    let fresh = elsewhere + "/nuevo.txt"
    let created = await runner.actionBand(tool: "write_file", arguments: ["path": fresh, "content": "x"])
    expectEq(created, .confirm, "archivo nuevo: confirmar")
    try "x".write(toFile: fresh, atomically: true, encoding: .utf8)
    let overwritten = await runner.actionBand(tool: "write_file", arguments: ["path": fresh, "content": "y"])
    expectEq(overwritten, .critical, "sobrescribir: crítico")
    let edited = await runner.actionBand(tool: "edit_file", arguments: ["path": fresh])
    expectEq(edited, .critical, "editar: crítico")
    let deleted = await runner.actionBand(tool: "delete_file", arguments: ["path": fresh])
    expectEq(deleted, .critical, "borrar: crítico")
    expectEq(QAApprovalPolicy.decide(band: deleted, tool: "delete_file"), .ownerCheck, "en QA borrar pide Touch ID")
    expectEq(QAApprovalPolicy.decide(band: created, tool: "write_file"), .act, "en QA crear pasa")
}

@Test func theFreeDiskDoesNotRelaxLibraryOrTheAppsOwnFolders() {
    let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
    expect(NativeToolRunner.isAppOwned(home + "/Library/Preferences/x.plist", home: home, appRoot: nil), "Library")
    expect(!NativeToolRunner.isAppOwned(home + "/Desktop/x.txt", home: home, appRoot: nil), "Desktop es normal")
}

@Test func aPrivacyDenialAsksForFullDiskAccess() {
    let eperm = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
    let wrapped = NSError(
        domain: NSCocoaErrorDomain, code: 257, userInfo: [NSUnderlyingErrorKey: eperm])
    for error in [eperm, wrapped] {
        let result = NativeToolRunner.fullDiskAccessFailure(error)
        expect(result?.ok == false && result?.output.hasPrefix("full_disk_access_required") == true,
               "TCC: \(String(describing: result?.output))")
        expect(result?.output.contains("Full Disk Access") == true, "dice dónde activarlo")
    }
    let plainPermission = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
    expect(NativeToolRunner.fullDiskAccessFailure(plainPermission) == nil, "un chmod no es TCC")
}
