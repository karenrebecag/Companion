import CompanionCore
import Foundation
import Testing

// Wave 10b. Validadores portados de Relay (`contracts/mod.rs`) más los dos
// casos que su review encontró: symlink a oculto y HOME sin canonicalizar.
@Test @MainActor func parentToolPolicyTests() throws {
    testAppNameAcceptsAndRejects()
    testHTTPURLAcceptsAndRejects()
    try testHomePathAcceptsInsideHome()
    try testHomePathRejectsOutsideHome()
    try testHomePathRejectsHidden()
    try testHomePathRejectsEscapeAfterResolving()
    try testHomePathRejectsSymlinkToHidden()
    try testHomePathCanonicalizesHome()
    try testHomePathMissingIsNotFound()
    try testHomePathRefusesLaunchers()
    testInputLengthCaps()
}

@MainActor func testAppNameAcceptsAndRejects() {
    for ok in ["Safari", "Visual Studio Code", "Notes.app", "  Music  "] {
        expect(code(of: { try ParentToolPolicy.appName(ok) }) == nil,
               "appName: acepta «\(ok)»")
    }
    expectEq(try? ParentToolPolicy.appName("Notes.app"), "Notes",
             "appName: quita el sufijo .app")
    expectEq(try? ParentToolPolicy.appName("  Music  "), "Music",
             "appName: recorta espacios")
    let long = String(repeating: "a", count: 65)
    for (bad, why) in [("", "vacío"), (long, "> 64"), ("a/b", "/"),
                       ("a\\b", "\\"), ("a;b", ";"), ("a\nb", "salto")] {
        expectEq(code(of: { try ParentToolPolicy.appName(bad) }),
                 "invalid_args", "appName: rechaza \(why)")
    }
}

@MainActor func testHTTPURLAcceptsAndRejects() {
    for ok in ["https://x", "http://localhost", "http://192.168.1.1",
               "https://example.com/a?b=c#d"] {
        expect(code(of: { try ParentToolPolicy.httpURL(ok) }) == nil,
               "httpURL: acepta \(ok)")
    }
    expectEq((try? ParentToolPolicy.httpURL("HTTP://X"))?.absoluteString,
             "http://x", "httpURL: normaliza esquema y host")
    for (bad, want) in [("file:///etc/passwd", "denied_url"),
                        ("javascript:alert(1)", "denied_url"),
                        ("ftp://x", "denied_url"),
                        ("https://a b", "invalid_args"),
                        ("", "invalid_args"),
                        ("example.com", "invalid_args")] {
        expectEq(code(of: { try ParentToolPolicy.httpURL(bad) }), want,
                 "httpURL: rechaza \(bad)")
    }
}

@MainActor func testHomePathAcceptsInsideHome() throws {
    let fx = try HomeFixture()
    try fx.touch("ok.txt")
    let got = try ParentToolPolicy.homePath("~/ok.txt", home: fx.home)
    expectEq(got.path, fx.canonical.appendingPathComponent("ok.txt").path,
             "homePath: ~/ok.txt devuelve la ruta canónica")
    let rel = try ParentToolPolicy.homePath("ok.txt", home: fx.home)
    expectEq(rel.path, got.path, "homePath: relativa se resuelve contra home")
    let abs = try ParentToolPolicy.homePath(got.path, home: fx.home)
    expectEq(abs.path, got.path, "homePath: absoluta bajo home se acepta")
}

@MainActor func testHomePathRejectsOutsideHome() throws {
    let fx = try HomeFixture()
    let err = code(of: { try ParentToolPolicy.homePath("/etc/passwd", home: fx.home) })
    expectEq(err, "denied_path", "homePath: fuera de home es denied_path")
}

@MainActor func testHomePathRejectsHidden() throws {
    let fx = try HomeFixture()
    try fx.mkdir(".ssh")
    try fx.touch(".ssh/id_rsa")
    let err = error(of: { try ParentToolPolicy.homePath("~/.ssh/id_rsa", home: fx.home) })
    expectEq(err?.code, "denied_path", "homePath: oculto es denied_path")
    expect(err?.message.lowercased().contains("hidden") == true,
           "homePath: el mensaje dice hidden")
}

/// `nested` es un symlink a un directorio FUERA de home. Léxicamente
/// `nested/../secret.txt` colapsa a `~/secret.txt` y pasa; resuelto, `..`
/// sube desde el destino real del symlink y sale de home.
@MainActor func testHomePathRejectsEscapeAfterResolving() throws {
    let fx = try HomeFixture()
    let outside = fx.root.appendingPathComponent("outside")
    try FileManager.default.createDirectory(
        at: outside.appendingPathComponent("dir"), withIntermediateDirectories: true)
    try Data("s".utf8).write(to: outside.appendingPathComponent("secret.txt"))
    try FileManager.default.createSymbolicLink(
        at: fx.home.appendingPathComponent("nested"),
        withDestinationURL: outside.appendingPathComponent("dir"))
    let err = code(of: {
        try ParentToolPolicy.homePath("~/nested/../secret.txt", home: fx.home)
    })
    expectEq(err, "denied_path", "homePath: el escape por symlink + .. se atrapa resuelto")
}

@MainActor func testHomePathRejectsSymlinkToHidden() throws {
    let fx = try HomeFixture()
    try fx.mkdir(".config")
    try fx.touch(".config/x")
    try FileManager.default.createSymbolicLink(
        at: fx.home.appendingPathComponent("link"),
        withDestinationURL: fx.home.appendingPathComponent(".config"))
    let err = error(of: { try ParentToolPolicy.homePath("~/link/x", home: fx.home) })
    expectEq(err?.code, "denied_path", "homePath: symlink a oculto es denied_path")
    expect(err?.message.lowercased().contains("hidden") == true,
           "homePath: y lo dice")
}

/// El test de Relay pasaba con un HOME plano y producción habría negado todo
/// con un HOME en volumen de red (symlink en medio): se canonicaliza home.
@MainActor func testHomePathCanonicalizesHome() throws {
    let fx = try HomeFixture()
    try fx.touch("ok.txt")
    let link = fx.root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(
        at: link, withDestinationURL: fx.root.appendingPathComponent("real"))
    let linkedHome = link.appendingPathComponent("home")
    let got = try ParentToolPolicy.homePath("~/ok.txt", home: linkedHome)
    expectEq(got.path, fx.canonical.appendingPathComponent("ok.txt").path,
             "homePath: home con symlink en medio acepta y canonicaliza")
}

@MainActor func testHomePathMissingIsNotFound() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    let err = code(of: {
        try ParentToolPolicy.homePath("~/Documents/nope.txt", home: fx.home)
    })
    expectEq(err, "not_found", "homePath: inexistente bajo padre válido es not_found")
    let hidden = code(of: {
        try ParentToolPolicy.homePath("~/.hidden/nope.txt", home: fx.home)
    })
    expectEq(hidden, "denied_path", "homePath: inexistente bajo oculto sigue siendo denied")
    let out = code(of: { try ParentToolPolicy.homePath("/nope/x", home: fx.home) })
    expectEq(out, "denied_path", "homePath: inexistente fuera sigue siendo denied")
}

/// Hallazgo del security-reviewer (2026-09-05): `NSWorkspace.open` EJECUTA
/// un `.command`, lanza un `.app` y sigue la URL guardada dentro de un
/// `.webloc`/`.inetloc` — una segunda puerta a `file://` o `javascript:` que
/// `httpURL` nunca ve. Solo documentos y carpetas.
@MainActor func testHomePathRefusesLaunchers() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Foo.app")
    for name in ["update.command", "run.tool", "x.terminal", "a.workflow",
                 "s.scpt", "s.applescript", "link.webloc", "link.inetloc"] {
        try fx.touch(name)
    }
    for name in ["Foo.app", "update.command", "run.tool", "x.terminal", "a.workflow",
                 "s.scpt", "s.applescript", "link.webloc", "link.inetloc",
                 "UPDATE.COMMAND"] {
        let err = error(of: { try ParentToolPolicy.homePath("~/\(name)", home: fx.home) })
        expectEq(err?.code, "denied_path", "homePath: \(name) es un lanzador, denied_path")
    }
    try fx.mkdir("Documents")
    try fx.touch("Documents/notas.md")
    expect(code(of: { try ParentToolPolicy.homePath("~/Documents", home: fx.home) }) == nil,
           "homePath: una carpeta sí")
    expect(code(of: { try ParentToolPolicy.homePath("~/Documents/notas.md", home: fx.home) }) == nil,
           "homePath: un documento sí")
}

@MainActor func testInputLengthCaps() {
    let long = String(repeating: "a", count: 5000)
    expectEq(code(of: { try ParentToolPolicy.httpURL("https://x/" + long) }), "invalid_args",
             "httpURL: tope de longitud")
    expectEq(code(of: { try ParentToolPolicy.homePath("~/" + long, home: URL(fileURLWithPath: "/tmp")) }),
             "invalid_args", "homePath: tope de longitud antes de tocar el disco")
}

// MARK: - helpers

private func code(of body: () throws -> Any) -> String? {
    error(of: body)?.code
}

private func error(of body: () throws -> Any) -> ContractError? {
    do {
        _ = try body()
        return nil
    } catch {
        return error as? ContractError
    }
}

/// `<root>/real/home` como HOME de prueba. `root` vive en el temp del
/// sistema, que en macOS ya es un symlink (`/var` → `/private/var`), así que
/// hasta el caso feliz ejercita la canonicalización.
struct HomeFixture {
    let root: URL
    let home: URL
    /// realpath(3), like the policy: Foundation's resolver drops `/private`.
    var canonical: URL {
        guard let real = realpath(home.path, nil) else { return home }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real))
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("parent-home-\(UUID().uuidString)")
        home = root.appendingPathComponent("real/home")
        try FileManager.default.createDirectory(
            at: home, withIntermediateDirectories: true)
    }

    func mkdir(_ rel: String) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(rel), withIntermediateDirectories: true)
    }

    func touch(_ rel: String) throws {
        try Data("x".utf8).write(to: home.appendingPathComponent(rel))
    }
}
