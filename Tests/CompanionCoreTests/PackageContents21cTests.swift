import CompanionTestKit
import Foundation
import Testing

// 21c S3: what may ship inside Companion.app. scripts/package-contents.sh is
// sourced by bundle.sh (the copy) and package-smoke.sh (the audit); these run
// its functions directly on throwaway trees. A hook once wrote a stray
// `Users/.../.git/claude-review.json` that a whole-folder copy shipped.

@Test func packageContents21cTests() throws {
    try testAllowlistIsTheTrackedExtensionMinusDocsAndTests()
    try testCopyShipsOnlyTheAllowlist()
    try testCopyFailsWhenAListedFileIsMissing()
    try testCopyRejectsASymlinkedSource()
    try testStraysReportsAnythingOutsideTheAllowlist()
    try testStraysFlagsASymlinkAtAnAllowlistedPath()
    try testStraysFailsClosedWhenTheListingFails()
    try testAppScanFlagsLeaksAnywhereInTheApp()
    try testAppScanFailsClosed()
    try testResourceFolderMatchesGitExactly()
}

/// Runs `snippet` with scripts/package-contents.sh sourced; `args` are $1...
private func contentsLib(_ snippet: String, _ args: [String] = []) throws -> (status: Int32, output: String) {
    let program = #"set -euo pipefail; . "$0"; "# + snippet
    return try runProcess("/bin/bash", ["-c", program, repoPath("scripts/package-contents.sh")] + args,
                          env: ["PATH": "/usr/bin:/bin"])
}

private func lines(_ text: String) -> [String] { text.split(separator: "\n").map(String.init) }

private func files(under root: URL) throws -> [String] {
    let base = root.resolvingSymlinksInPath().path + "/"
    let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
    var found: [String] = []
    while let url = walker?.nextObject() as? URL {
        if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { continue }
        found.append(String(url.resolvingSymlinksInPath().path.dropFirst(base.count)))
    }
    return found.sorted()
}

private func allowlist() throws -> [String] {
    lines(try contentsLib(#"printf '%s\n' $BROWSER_EXTENSION_FILES"#).output).sorted()
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// Source tree with every real extension file plus the stray that shipped.
private func extensionSourceWithStray() throws -> URL {
    let root = try scriptTempRoot("ext-src")
    let src = root.appendingPathComponent("browser")
    try FileManager.default.copyItem(atPath: repoPath("Extensions/browser"), toPath: src.path)
    try write("{}", to: src.appendingPathComponent("Users/k/Desktop/companion-next/.git/claude-review.json"))
    return root
}

private func copiedExtension() throws -> (root: URL, dst: URL) {
    let root = try extensionSourceWithStray()
    let dst = root.appendingPathComponent("BrowserExtension")
    let ran = try contentsLib(#"browser_extension_copy "$1" "$2""#, [root.appendingPathComponent("browser").path, dst.path])
    expectEq(ran.status, 0, "21c item 6: la copia termina (\(ran.output))")
    return (root, dst)
}

/// `<bundle>/<folder>:Sources/<target>/<folder>` for every `.copy` in Package.swift.
private func packageCopyResources() throws -> [String] {
    let manifest = scriptText("Package.swift")
    let target = try NSRegularExpression(pattern: #"name: "(\w+)"[^)]*?resources: \[([^\]]*)\]"#)
    let copy = try NSRegularExpression(pattern: #"\.copy\("([^"]+)"\)"#)
    var found: [String] = []
    for match in target.matches(in: manifest, range: NSRange(manifest.startIndex..., in: manifest)) {
        guard let name = Range(match.range(at: 1), in: manifest), let list = Range(match.range(at: 2), in: manifest) else { continue }
        let resources = String(manifest[list])
        for item in copy.matches(in: resources, range: NSRange(resources.startIndex..., in: resources)) {
            guard let folder = Range(item.range(at: 1), in: resources) else { continue }
            let t = manifest[name], f = resources[folder]
            found.append("Companion_\(t).bundle/\(f):Sources/\(t)/\(f)")
        }
    }
    return found.sorted()
}

// MARK: - Extension allowlist

func testAllowlistIsTheTrackedExtensionMinusDocsAndTests() throws {
    let tracked = lines(try runProcess("/usr/bin/git", ["-C", repoPath(""), "ls-files", "--", "Extensions/browser"],
                                       env: ["PATH": "/usr/bin:/bin"]).output)
        .map { String($0.dropFirst("Extensions/browser/".count)) }
        .filter { $0 != "README.md" && !$0.hasPrefix("test/") }.sorted()
    expect(!tracked.isEmpty, "21c item 6: git ve la extension")
    let listed = try allowlist()
    expectEq(listed, tracked, "21c item 6: la lista es exactamente lo trackeado de la extension, sin README ni test/")
    let manifest = scriptText("Extensions/browser/manifest.json")
    expect(manifest.contains(#""service_worker": "background.js""#) && listed.contains("background.js"),
           "21c item 6: el service worker del manifest viaja")
}

func testCopyShipsOnlyTheAllowlist() throws {
    let (root, dst) = try copiedExtension()
    defer { removeScriptTemp(root) }
    expectEq(try files(under: dst), try allowlist(), "21c item 6: solo la lista llega a la app; ni el stray, ni README, ni test/")
}

func testCopyFailsWhenAListedFileIsMissing() throws {
    let root = try extensionSourceWithStray()
    defer { removeScriptTemp(root) }
    let src = root.appendingPathComponent("browser")
    try FileManager.default.removeItem(at: src.appendingPathComponent("background.js"))
    let ran = try contentsLib(#"browser_extension_copy "$1" "$2""#,
                              [src.path, root.appendingPathComponent("BrowserExtension").path])
    expect(ran.status != 0, "21c item 6: un archivo de la lista que falta rompe la copia, no se omite")
}

func testCopyRejectsASymlinkedSource() throws {
    for (label, relative) in [("archivo", "manifest.json"), ("carpeta padre", "lib")] {
        let root = try extensionSourceWithStray()
        defer { removeScriptTemp(root) }
        let src = root.appendingPathComponent("browser")
        let real = root.appendingPathComponent("elsewhere-\(relative)")
        try FileManager.default.moveItem(at: src.appendingPathComponent(relative), to: real)
        try FileManager.default.createSymbolicLink(at: src.appendingPathComponent(relative), withDestinationURL: real)
        let dst = root.appendingPathComponent("BrowserExtension")
        let ran = try contentsLib(#"browser_extension_copy "$1" "$2""#, [src.path, dst.path])
        expect(ran.status != 0, "21c item 2: un symlink en la fuente (\(label)) rompe la copia, no se sigue")
        expect(ran.output.contains("symlink"), "21c item 2: \(label): el error dice por que (\(ran.output))")
    }
}

func testStraysReportsAnythingOutsideTheAllowlist() throws {
    let (root, dst) = try copiedExtension()
    defer { removeScriptTemp(root) }
    let clean = try contentsLib(#"browser_extension_strays "$1""#, [dst.path])
    expectEq(clean.status, 0, "21c item 6: el detector corre")
    expectEq(clean.output, "", "21c item 6: la copia por lista no tiene strays")

    try write("{}", to: dst.appendingPathComponent("Users/k/.git/claude-review.json"))
    try FileManager.default.createDirectory(at: dst.appendingPathComponent("empty"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: dst.appendingPathComponent("lib/link.js").path,
                                               withDestinationPath: "/etc/hosts")
    try write("x", to: dst.appendingPathComponent("README.md"))
    let dirty = lines(try contentsLib(#"browser_extension_strays "$1""#, [dst.path]).output)
    for stray in ["Users/k/.git/claude-review.json", "empty/", "lib/link.js", "README.md"] {
        expect(dirty.contains(stray), "21c item 6: el detector nombra \(stray) (\(dirty))")
    }
}

func testStraysFlagsASymlinkAtAnAllowlistedPath() throws {
    let (root, dst) = try copiedExtension()
    defer { removeScriptTemp(root) }
    let manifest = dst.appendingPathComponent("manifest.json")
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.createSymbolicLink(atPath: manifest.path, withDestinationPath: "/etc/hosts")
    let ran = try contentsLib(#"browser_extension_strays "$1""#, [dst.path])
    expect(lines(ran.output).contains("manifest.json"),
           "21c item 2: manifest.json -> /etc/hosts se reporta aunque el nombre este en la lista (\(ran.output))")
}

func testStraysFailsClosedWhenTheListingFails() throws {
    let missing = try contentsLib(#"browser_extension_strays "$1""#, ["/nonexistent-21c-\(UUID().uuidString)"])
    expect(missing.status != 0, "21c item 3: si find falla, el detector falla en vez de no imprimir nada")

    let (root, dst) = try copiedExtension()
    defer {
        do { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.appendingPathComponent("lib").path) }
        catch { Issue.record("21c: no se pudo restaurar permisos: \(error)") }
        removeScriptTemp(root)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dst.appendingPathComponent("lib").path)
    let unreadable = try contentsLib(#"browser_extension_strays "$1""#, [dst.path])
    expect(unreadable.status != 0, "21c item 3: una carpeta ilegible dentro de la extension hace fallar el detector")
}

// MARK: - Whole-app scan

func testAppScanFlagsLeaksAnywhereInTheApp() throws {
    let root = try scriptTempRoot("app-scan")
    defer { removeScriptTemp(root) }
    let app = root.appendingPathComponent("Companion.app")
    let resources = app.appendingPathComponent("Contents/Resources")
    try write("<plist/>", to: app.appendingPathComponent("Contents/Info.plist"))
    try write("# skill", to: resources.appendingPathComponent("X.bundle/Skills/a/SKILL.md"))
    try FileManager.default.createSymbolicLink(atPath: resources.appendingPathComponent("inside").path,
                                               withDestinationPath: "X.bundle/Skills/a/SKILL.md")
    try write("\u{0}\u{1}binary /Users/k/x", to: resources.appendingPathComponent("font.otf"))
    let clean = try contentsLib(#"app_forbidden_entries "$1""#, [app.path])
    expectEq(clean.status, 0, "21c item 1: el escaneo corre (\(clean.output))")
    expectEq(clean.output, "", "21c item 1: una app limpia (symlink interno, binario con /Users/) no reporta nada")

    try write("{}", to: resources.appendingPathComponent("X.bundle/Skills/.git/claude-review.json"))
    try write("", to: resources.appendingPathComponent("X.bundle/.DS_Store"))
    try write("K=1", to: resources.appendingPathComponent(".env.local"))
    try write("{}", to: resources.appendingPathComponent("claude-review.json"))
    try write("see /Users/karen/project", to: resources.appendingPathComponent("X.bundle/Skills/a/notes.md"))
    try FileManager.default.createSymbolicLink(atPath: resources.appendingPathComponent("out").path,
                                               withDestinationPath: "/etc/hosts")
    try FileManager.default.createSymbolicLink(atPath: resources.appendingPathComponent("dangling").path,
                                               withDestinationPath: "nope/nothing")
    let dirty = try contentsLib(#"app_forbidden_entries "$1""#, [app.path])
    let reported = lines(dirty.output)
    for leak in ["Contents/Resources/X.bundle/Skills/.git", "Contents/Resources/X.bundle/.DS_Store",
                 "Contents/Resources/.env.local", "Contents/Resources/claude-review.json",
                 "Contents/Resources/out", "Contents/Resources/dangling",
                 "Contents/Resources/X.bundle/Skills/a/notes.md"] {
        expect(reported.contains { $0 == leak || $0.hasPrefix(leak + " ") },
               "21c item 1: el escaneo nombra \(leak) (\(dirty.output))")
    }
    expect(!reported.contains { $0.hasPrefix("Contents/Resources/inside") },
           "21c item 1: un symlink que queda dentro de la app no es fuga")
}

func testAppScanFailsClosed() throws {
    let ran = try contentsLib(#"app_forbidden_entries "$1""#, ["/nonexistent-21c-\(UUID().uuidString)"])
    expect(ran.status != 0, "21c item 1: sin app que listar, el escaneo falla")
}

// MARK: - Resource folders against git

func testResourceFolderMatchesGitExactly() throws {
    let source = "Sources/CompanionServices/Skills"
    let tracked = lines(try runProcess("/usr/bin/git", ["-C", repoPath(""), "ls-files", "--", source],
                                       env: ["PATH": "/usr/bin:/bin"]).output)
    expect(!tracked.isEmpty, "21c item 1: git ve las skills")
    let root = try scriptTempRoot("res-folder")
    defer { removeScriptTemp(root) }
    let shipped = root.appendingPathComponent("Skills")
    for path in tracked {
        let target = shipped.appendingPathComponent(String(path.dropFirst(source.count + 1)))
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: repoPath(path), toPath: target.path)
    }
    let run = { try contentsLib(#"resource_folder_strays "$1" "$2" "$3""#, [shipped.path, repoPath(""), source]) }
    let clean = try run()
    expectEq(clean.status, 0, "21c item 1: la comparacion corre (\(clean.output))")
    expectEq(clean.output, "", "21c item 1: una copia exacta de lo trackeado no reporta nada")

    try write("{}", to: shipped.appendingPathComponent(".git/claude-review.json"))
    try write("x", to: shipped.appendingPathComponent("extra.md"))
    let first = String(tracked[0].dropFirst(source.count + 1))
    try FileManager.default.removeItem(at: shipped.appendingPathComponent(first))
    let dirty = lines(try run().output)
    for line in [".git/claude-review.json", "extra.md", "falta: \(first)"] {
        expect(dirty.contains(line), "21c item 1: la comparacion nombra \(line) (\(dirty))")
    }

    let copies = try packageCopyResources()
    let folders = lines(try contentsLib(#"printf '%s\n' $RESOURCE_FOLDERS"#).output).sorted()
    expect(!copies.isEmpty, "21c item 1: Package.swift declara recursos .copy")
    expectEq(folders, copies, "21c item 1: RESOURCE_FOLDERS cubre exactamente los .copy de Package.swift")

    let nothing = try contentsLib(#"resource_folder_strays "$1" "$2" "$3""#,
                                  [shipped.path, repoPath(""), "Sources/NoSuchFolder21c"])
    expect(nothing.status != 0, "21c item 1: sin archivos trackeados en la fuente, la comparacion falla cerrada")
}
