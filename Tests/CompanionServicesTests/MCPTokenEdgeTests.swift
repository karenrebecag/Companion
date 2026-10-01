import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mcp-edge-\(UUID().uuidString)")
}

private func put(_ json: String, in root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(json.utf8).write(to: root.appendingPathComponent("mcp.json"))
}

private func fileText(_ root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent("mcp.json"), encoding: .utf8)
}

/// Review D6 (code HIGH / security LOW): a save that could not copy the
/// host-only token to its server must not then delete the only copy.
@Test func aSaveWhoseKeychainRefusesTheMoveKeepsTheHostOnlyToken() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try put(#"[{"label":"a","url":"https://tools.dev/a"}]"#, in: root)
    let secrets = TestHostSecretStore()
    try secrets.write(.mcpToken, host: "tools.dev", value: "old-host-token")
    secrets.failWrites = true

    try MCPConfigFile.save(
        [MCPServerConfig(label: "a", url: "https://tools.dev/a")], root: root, secrets: secrets)
    secrets.failWrites = false
    expectEq(try secrets.read(.mcpToken, host: "tools.dev"), "old-host-token",
             "the host-only token is still there: the move failed")
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, "old-host-token",
             "and it still resolves on the next load")
}

@Test func aSaveRetiresTheHostOnlyTokenOnceItsServerHasItsOwn() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    try secrets.write(.mcpToken, host: "tools.dev", value: "old-host-token")
    try MCPConfigFile.save(
        [MCPServerConfig(label: "a", url: "https://tools.dev/a")], root: root, secrets: secrets)
    expectEq(try secrets.read(.mcpToken, host: "tools.dev"), nil, "the host-only copy is retired")
    expectEq(try secrets.read(.mcpToken, host: "tools.dev/a"), "old-host-token", "after moving to the server")
}

@Test func aSaveKeepsTheHostOnlyTokenWhileOneServerOfTheHostIsStuck() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    try secrets.write(.mcpToken, host: "tools.dev", value: "old-host-token")
    secrets.failWrites = true
    try MCPConfigFile.save(
        [MCPServerConfig(label: "a", url: "https://tools.dev/a"),
         MCPServerConfig(label: "b", url: "https://tools.dev/b", authorization: nil)],
        root: root, secrets: secrets)
    secrets.failWrites = false
    expectEq(try secrets.read(.mcpToken, host: "tools.dev"), "old-host-token", "one stuck server keeps the host copy")
}

/// Review D6 (code MEDIUM): a token is never attached to a plain-http URL,
/// whether it came from the file or from the Keychain.
@Test func aTokenInTheFileForAnHttpServerIsNeitherServedNorStored() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try put(#"[{"label":"n","url":"http://notes.dev/mcp","authorization":"tok-1"}]"#, in: root)
    let secrets = TestHostSecretStore()
    let loaded = MCPConfigFile.load(root: root, secrets: secrets)
    expectEq(loaded.first?.authorization, nil, "http: the token is not sent")
    expectEq(secrets.count, 0, "http: nothing is stored under a key that https would share")
    expect(try fileText(root).contains("tok-1"), "http: the file is left as it was")
}

@Test func aKeychainTokenIsNotServedWhenTheUrlIsDowngradedToHttp() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    try MCPConfigFile.save(
        [MCPServerConfig(label: "n", url: "https://notes.dev/mcp", authorization: "tok-1")],
        root: root, secrets: secrets)
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, "tok-1", "https still serves it")
    try put(#"[{"label":"n","url":"http://notes.dev/mcp"}]"#, in: root)
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, nil,
             "a downgrade to http does not get the token in the clear")
}

@Test func savingAnHttpServerWithATokenFailsAndLeavesTheFile() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = #"[{"label":"keep","url":"https://keep.dev"}]"#
    try put(original, in: root)
    #expect(throws: SecretStoreError.invalidHost) {
        try MCPConfigFile.save(
            [MCPServerConfig(label: "n", url: "http://notes.dev/mcp", authorization: "tok")],
            root: root, secrets: TestHostSecretStore())
    }
    expectEq(try fileText(root), original, "the file is untouched")
}

@Test func savingABadUrlWithATokenLeavesTheFileUntouched() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = #"[{"label":"keep","url":"https://keep.dev"}]"#
    try put(original, in: root)
    #expect(throws: SecretStoreError.invalidHost) {
        try MCPConfigFile.save(
            [MCPServerConfig(label: "n", url: "not a url", authorization: "tok")],
            root: root, secrets: TestHostSecretStore())
    }
    expectEq(try fileText(root), original, "the file is untouched")
}

@Test func aStrippedSaveKeepsTheTokenAlreadyInTheKeychain() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    try MCPConfigFile.save(
        [MCPServerConfig(label: "n", url: "https://notes.dev/mcp", authorization: "tok-1")],
        root: root, secrets: secrets)
    try MCPConfigFile.save([MCPServerConfig(label: "n2", url: "https://notes.dev/mcp")], root: root, secrets: secrets)
    expectEq(try secrets.read(.mcpToken, host: "notes.dev/mcp"), "tok-1", "nil does not mean clear")
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, "tok-1", "and it still serves")
}

@Test func aTokenHandEditedIntoTheFileReplacesTheKeychainOneOnLoad() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    try secrets.write(.mcpToken, host: "notes.dev/mcp", value: "old")
    try put(#"[{"label":"n","url":"https://notes.dev/mcp","authorization":"new"}]"#, in: root)
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).first?.authorization, "new", "the new one wins")
    expectEq(try secrets.read(.mcpToken, host: "notes.dev/mcp"), "new", "and replaces the stored one")
    expect(!(try fileText(root)).contains("new\""), "and leaves the file")
}

@Test func removingOneOfTwoServersOnAHostDropsOnlyItsToken() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = TestHostSecretStore()
    let docs = MCPServerConfig(label: "docs", url: "https://tools.dev/docs", authorization: "td")
    let crm = MCPServerConfig(label: "crm", url: "https://tools.dev/crm", authorization: "tc")
    try MCPConfigFile.save([docs, crm], root: root, secrets: secrets)
    try MCPConfigFile.save([MCPServerConfig(label: "docs", url: "https://tools.dev/docs")], root: root, secrets: secrets)
    expectEq(try secrets.read(.mcpToken, host: "tools.dev/crm"), nil, "the removed server's token goes")
    expectEq(try secrets.read(.mcpToken, host: "tools.dev/docs"), "td", "its sibling's stays")
}
