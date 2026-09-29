import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mcp-kc-\(UUID().uuidString)")
}

private func fileText(_ root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent("mcp.json"), encoding: .utf8)
}

/// 20c D6 (M5, spec R3): a bearer token in mcp.json is moved to the Keychain
/// under its host; the value is never changed, the file is rewritten without
/// it only after the Keychain took it, and a failed move loses nothing.
@Test func mcpTokenMigratesFromTheFileToTheKeychain() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(#"[{"label":"notas","url":"https://Notes.dev/mcp","authorization":"tok-1"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    let secrets = TestHostSecretStore()

    let loaded = MCPConfigFile.load(root: root, secrets: secrets)
    expectEq(loaded.first?.authorization, "tok-1", "migra: el token sigue llegando a la sesion")
    expectEq(try secrets.read(.mcpToken, host: "notes.dev"), "tok-1", "migra: el valor pasa intacto al llavero")
    expect(!(try fileText(root)).contains("tok-1"), "migra: el archivo ya no guarda el token")
    expect(try fileText(root).contains("notas"), "migra: el resto de la config se conserva")

    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, "tok-1",
             "migra: la segunda carga lo trae del llavero")
}

@Test func mcpTokenStaysInTheFileWhenTheKeychainRefuses() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(#"[{"label":"notas","url":"https://notes.dev/mcp","authorization":"tok-1"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    let secrets = TestHostSecretStore()
    secrets.failWrites = true

    let loaded = MCPConfigFile.load(root: root, secrets: secrets)
    expectEq(loaded.first?.authorization, "tok-1", "falla: la config que funcionaba sigue funcionando")
    expect(try fileText(root).contains("tok-1"), "falla: el archivo no se toca si el llavero no lo tomo")
}

@Test func mcpTokenIsBoundToItsHost() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    try MCPConfigFile.save(
        [MCPServerConfig(label: "notas", url: "https://notes.dev/mcp", authorization: "tok-1")],
        root: root, secrets: secrets)
    expect(!(try fileText(root)).contains("tok-1"), "save: el token nunca llega al archivo")
    expectEq(try secrets.read(.mcpToken, host: "notes.dev"), "tok-1", "save: va al llavero por host")

    // Someone repoints the entry at another host: the token does not follow.
    try Data(#"[{"label":"notas","url":"https://evil.example/mcp"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, nil,
             "host: el token de notes.dev no se manda a evil.example")
}

@Test func mcpSaveThrowsRatherThanWriteASecretInTheClear() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    secrets.failWrites = true
    #expect(throws: SecretStoreError.denied) {
        try MCPConfigFile.save(
            [MCPServerConfig(label: "n", url: "https://n.dev", authorization: "tok")],
            root: root, secrets: secrets)
    }
    expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("mcp.json").path),
           "save: sin llavero no se escribe el secreto en claro")

    #expect(throws: SecretStoreError.invalidHost) {
        try MCPConfigFile.save(
            [MCPServerConfig(label: "n", url: "not a url", authorization: "tok")],
            root: root, secrets: TestHostSecretStore())
    }
}

@Test func mcpRemovingAServerDropsItsToken() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    let a = MCPServerConfig(label: "a", url: "https://a.dev", authorization: "ta")
    let b = MCPServerConfig(label: "b", url: "https://b.dev", authorization: "tb")
    try MCPConfigFile.save([a, b], root: root, secrets: secrets)
    try MCPConfigFile.save([MCPServerConfig(label: "b", url: "https://b.dev")], root: root, secrets: secrets)
    expectEq(try secrets.read(.mcpToken, host: "a.dev"), nil, "quitar: el token del servidor quitado se borra")
    expectEq(try secrets.read(.mcpToken, host: "b.dev"), "tb", "quitar: el del que queda sigue")
}
