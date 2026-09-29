import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

/// Wave 18-4a: the only place the app writes into another app's config
/// folder (ADR 007). Every test runs against a temp home, never the real one.

private let manifestName = "com.karen.companion.browser.json"
/// The installer refuses a path that does not exist, so the tests point at a
/// real executable. Symlinks are resolved (/var is one on macOS), so is the expectation.
private func makeExecutable(mode: Int = 0o755, under root: URL? = nil, named name: String = "Companion") -> URL {
    let dir = (root ?? FileManager.default.temporaryDirectory)
        .appendingPathComponent("nh-exe-\(UUID().uuidString.prefix(8))", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url
    } catch {
        Issue.record("could not create the test executable: \(error)")
        return dir
    }
}

private let exe = makeExecutable()
private let resolvedExe = exe.resolvingSymlinksInPath().path

private func makeHome(browsers: [String]) throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("nativehost-\(UUID().uuidString)", isDirectory: true)
    for path in browsers {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Application Support/\(path)"),
            withIntermediateDirectories: true)
    }
    return home
}

private func manifestURL(_ home: URL, _ browser: String) -> URL {
    home.appendingPathComponent("Library/Application Support/\(browser)/NativeMessagingHosts/\(manifestName)")
}

private func readJSON(_ url: URL) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return object as? [String: Any] ?? [:]
}

@Test func installWritesManifestWithPinnedOriginsAndPath() throws {
    let home = try makeHome(browsers: ["Google/Chrome"])
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = NativeHostInstaller(home: home, executable: exe)
    expectEq(try installer.install(), [.chrome], "instala en Chrome")
    let url = manifestURL(home, "Google/Chrome")
    let json = try readJSON(url)
    expectEq(json["name"] as? String, "com.karen.companion.browser", "name")
    expectEq(json["path"] as? String, resolvedExe, "path")
    expectEq(json["type"] as? String, "stdio", "type")
    expectEq(json["allowed_origins"] as? [String], BrowserPolicy.pinnedOrigins.sorted(), "origenes")
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    expectEq((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o644, "modo 0644")
}

@Test func onlyDetectedBrowsersGetAManifest() throws {
    let home = try makeHome(browsers: ["Comet"])
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = NativeHostInstaller(home: home, executable: exe)
    expectEq(installer.detected(), [.comet], "detectado")
    expectEq(try installer.install(), [.comet], "instalado")
    expect(!FileManager.default.fileExists(
        atPath: home.appendingPathComponent("Library/Application Support/Google").path),
        "no se crea la carpeta de un navegador ausente")
}

@Test func nothingDetectedWritesNothing() throws {
    let home = try makeHome(browsers: [])
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = NativeHostInstaller(home: home, executable: exe)
    expectEq(try installer.install(), [BrowserKind](), "nada que instalar")
    expectEq(installer.installed(), [BrowserKind](), "nada instalado")
}

@Test func removeDeletesAndSecondRemoveIsNoOp() throws {
    let home = try makeHome(browsers: ["Google/Chrome", "Comet"])
    defer { try? FileManager.default.removeItem(at: home) }
    let installer = NativeHostInstaller(home: home, executable: exe)
    _ = try installer.install()
    expectEq(installer.installed(), [.chrome, .comet], "ambos instalados")
    expectEq(try installer.remove(), [.chrome, .comet], "quitados")
    expectEq(installer.installed(), [BrowserKind](), "ya no hay manifiestos")
    expectEq(try installer.remove(), [BrowserKind](), "segunda vez no hace nada")
}

@Test func installOverwritesStalePath() throws {
    let home = try makeHome(browsers: ["Google/Chrome"])
    defer { try? FileManager.default.removeItem(at: home) }
    let old = makeExecutable()
    _ = try NativeHostInstaller(home: home, executable: old).install()
    _ = try NativeHostInstaller(home: home, executable: exe).install()
    expectEq(try readJSON(manifestURL(home, "Google/Chrome"))["path"] as? String, resolvedExe, "path actualizado")
}

@Test func symlinkAtDestinationIsRefused() throws {
    let home = try makeHome(browsers: ["Google/Chrome"])
    defer { try? FileManager.default.removeItem(at: home) }
    let dir = manifestURL(home, "Google/Chrome").deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let target = home.appendingPathComponent("victim.txt")
    try Data("keep".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: manifestURL(home, "Google/Chrome"), withDestinationURL: target)
    let installer = NativeHostInstaller(home: home, executable: exe)
    do {
        _ = try installer.install()
        Issue.record("debio rechazar el symlink")
    } catch {
        expectEq(error as? NativeHostInstaller.Failure, .symlinkAtDestination(.chrome), "error de symlink")
    }
    expectEq(try String(contentsOf: target, encoding: .utf8), "keep", "el destino del enlace no se toca")
    do {
        _ = try installer.remove()
        Issue.record("remove tampoco sigue el symlink")
    } catch {
        expectEq(error as? NativeHostInstaller.Failure, .symlinkAtDestination(.chrome), "remove rechaza")
    }
    expect(FileManager.default.fileExists(atPath: target.path), "victima intacta")
}

@Test func foreignFileWithSameFilenameIsNotDeleted() throws {
    let home = try makeHome(browsers: ["Google/Chrome"])
    defer { try? FileManager.default.removeItem(at: home) }
    let url = manifestURL(home, "Google/Chrome")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"name":"someone.else","path":"/x"}"#.utf8).write(to: url)
    let installer = NativeHostInstaller(home: home, executable: exe)
    expectEq(installer.installed(), [BrowserKind](), "no es nuestro")
    expectEq(try installer.remove(), [BrowserKind](), "no se quita")
    expect(FileManager.default.fileExists(atPath: url.path), "archivo ajeno intacto")
}

@Test func corruptFileIsNotDeleted() throws {
    let home = try makeHome(browsers: ["Comet"])
    defer { try? FileManager.default.removeItem(at: home) }
    let url = manifestURL(home, "Comet")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    let installer = NativeHostInstaller(home: home, executable: exe)
    expectEq(try installer.remove(), [BrowserKind](), "ilegible no es nuestro")
    expect(FileManager.default.fileExists(atPath: url.path), "sigue ahi")
}

// MARK: - review fixes (L1, M3, M-B)

@Test func manifestsLandAtTheLiteralPathsEachBrowserReads() throws {
    let home = try makeHome(browsers: ["Google/Chrome", "Comet"])
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try NativeHostInstaller(home: home, executable: exe).install()
    for relative in [
        "Library/Application Support/Google/Chrome/NativeMessagingHosts/com.karen.companion.browser.json",
        "Library/Application Support/Comet/NativeMessagingHosts/com.karen.companion.browser.json",
    ] {
        expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(relative).path), "literal: \(relative)")
    }
}

@Test func allowedOriginsIsExactlyTheOnePinnedExtension() throws {
    let home = try makeHome(browsers: ["Google/Chrome"])
    defer { try? FileManager.default.removeItem(at: home) }
    _ = try NativeHostInstaller(home: home, executable: exe).install()
    expectEq(try readJSON(manifestURL(home, "Google/Chrome"))["allowed_origins"] as? [String],
             ["chrome-extension://gaipfdnbliibnfchgcnamnjpfgkilnll/"], "origins: the pinned id and nothing else")
}

private func expectUnstable(_ executable: URL, _ label: String) throws {
    let home = try makeHome(browsers: ["Google/Chrome"])
    defer { try? FileManager.default.removeItem(at: home) }
    do {
        _ = try NativeHostInstaller(home: home, executable: executable).install()
        Issue.record("\(label): debio rechazar la ruta")
    } catch {
        expectEq(error as? NativeHostInstaller.Failure, .unstableExecutablePath, "\(label): error tipado")
    }
    expect(!FileManager.default.fileExists(atPath: manifestURL(home, "Google/Chrome").path), "\(label): no se escribio nada")
}

@Test func aRelativeExecutablePathIsRefused() throws {
    // `fileURLWithPath` would anchor it to the cwd; a plain URL keeps it relative, as a caller bug would.
    guard let relative = URL(string: "relative/Companion") else { Issue.record("fixture"); return }
    try expectUnstable(relative, "relative")
}

@Test func aMissingExecutableIsRefused() throws {
    try expectUnstable(URL(fileURLWithPath: "/Applications/DoesNotExist-\(UUID().uuidString)/Companion"), "missing")
}

@Test func aFileThatIsNotExecutableIsRefused() throws {
    try expectUnstable(makeExecutable(mode: 0o644), "0644")
}

@Test func aDirectoryIsNotAnExecutable() throws {
    try expectUnstable(FileManager.default.temporaryDirectory, "directory")
}

@Test func anAppTranslocationPathIsRefused() throws {
    // Gatekeeper's randomized read-only mount: the path stops existing after the next launch.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppTranslocation-\(UUID().uuidString.prefix(8))")
    let translocated = makeExecutable(under: root.appendingPathComponent("d/AppTranslocation"), named: "Companion")
    defer { try? FileManager.default.removeItem(at: root) }
    expect(translocated.path.contains("/AppTranslocation/"), "translocation: the fixture has the segment")
    try expectUnstable(translocated, "translocation")
}

@Test func aSymlinkToAnAppTranslocationPathIsRefusedAfterResolution() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tl-\(UUID().uuidString.prefix(8))")
    let real = makeExecutable(under: root.appendingPathComponent("x/AppTranslocation"), named: "Companion")
    let link = root.appendingPathComponent("link")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    try expectUnstable(link, "link to translocation")
}

@Test func aSymlinkedExecutableIsWrittenAsItsResolvedPath() throws {
    let home = try makeHome(browsers: ["Google/Chrome"])
    let link = home.appendingPathComponent("Companion-link")
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: exe)
    _ = try NativeHostInstaller(home: home, executable: link).install()
    expectEq(try readJSON(manifestURL(home, "Google/Chrome"))["path"] as? String, resolvedExe,
             "symlink: the manifest holds the target, not the link")
}
