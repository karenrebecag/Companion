import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
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
    expectEq(try secrets.read(.mcpToken, host: "notes.dev/mcp"), "tok-1", "migra: el valor pasa intacto al llavero")
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
    expectEq(try secrets.read(.mcpToken, host: "notes.dev/mcp"), "tok-1", "save: va al llavero por host")

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
    expectEq(try secrets.read(.mcpToken, host: "a.dev/"), nil, "quitar: el token del servidor quitado se borra")
    expectEq(try secrets.read(.mcpToken, host: "b.dev/"), "tb", "quitar: el del que queda sigue")
}

/// Review D6 (code HIGH): the token is bound to the SERVER, not only its
/// host. Two servers on one host with different tokens used to overwrite each
/// other, and the last one won for both.
@Test func twoServersOnOneHostKeepTheirOwnTokens() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    let docs = MCPServerConfig(label: "docs", url: "https://tools.dev/docs/mcp", authorization: "tok-docs")
    let crm = MCPServerConfig(label: "crm", url: "https://tools.dev/crm/mcp", authorization: "tok-crm")
    try MCPConfigFile.save([docs, crm], root: root, secrets: secrets)

    func tokens(_ list: [MCPServerConfig]) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: list.map { ($0.label, $0.authorization) })
    }
    let loaded = MCPConfigFile.load(root: root, secrets: secrets)
    expectEq(tokens(loaded)["docs"] ?? nil, "tok-docs", "mismo host: docs conserva su token")
    expectEq(tokens(loaded)["crm"] ?? nil, "tok-crm", "mismo host: crm conserva su token")

    try MCPConfigFile.save(loaded, root: root, secrets: secrets)
    let again = MCPConfigFile.load(root: root, secrets: secrets)
    expectEq(tokens(again)["docs"] ?? nil, "tok-docs", "load-save-load: docs sigue con el suyo")
    expectEq(tokens(again)["crm"] ?? nil, "tok-crm", "load-save-load: crm sigue con el suyo")
}

@Test func aTokenIsNotServedToAnotherPathOrHost() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    try MCPConfigFile.save(
        [MCPServerConfig(label: "docs", url: "https://tools.dev/docs/mcp", authorization: "tok-docs")],
        root: root, secrets: secrets)
    try Data(#"[{"label":"other","url":"https://tools.dev/other/mcp"},{"label":"evil","url":"https://evil.example/docs/mcp"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    let loaded = MCPConfigFile.load(root: root, secrets: secrets)
    expectEq(loaded.map(\.authorization), [nil, nil], "otro path u otro host no reciben el token de docs")
}

@Test func aHostOnlyTokenFromBeforeStillResolvesAndMovesToTheServer() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(#"[{"label":"a","url":"https://tools.dev/a"},{"label":"b","url":"https://tools.dev/b"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    let secrets = TestHostSecretStore()
    try secrets.write(.mcpToken, host: "tools.dev", value: "old-host-token")

    let loaded = MCPConfigFile.load(root: root, secrets: secrets)
    expectEq(loaded.map(\.authorization), ["old-host-token", "old-host-token"],
             "migra: el token ligado solo al host sigue sirviendo a sus servidores")
    expectEq(try secrets.read(.mcpToken, host: "tools.dev"), nil,
             "migra: la copia solo-host se retira cuando cada servidor tiene la suya")
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).map(\.authorization),
             ["old-host-token", "old-host-token"], "migra: la segunda carga sale de las ligadas al servidor")

    try Data(#"[{"label":"a","url":"https://tools.dev/a"},{"label":"new","url":"https://tools.dev/new"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).map(\.authorization), ["old-host-token", nil],
             "migra: un servidor nuevo en ese host no hereda el token viejo")
}

@Test func aHostOnlyTokenSurvivesAFailedMove() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(#"[{"label":"a","url":"https://tools.dev/a"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    let secrets = TestHostSecretStore()
    try secrets.write(.mcpToken, host: "tools.dev", value: "old-host-token")
    secrets.failWrites = true
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, "old-host-token",
             "falla: si el llavero no deja mover, el token viejo sigue sirviendo")
    secrets.failWrites = false
    expectEq(try secrets.read(.mcpToken, host: "tools.dev"), "old-host-token", "falla: y no se borra")
}
