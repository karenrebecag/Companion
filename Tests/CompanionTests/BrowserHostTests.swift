import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 18-3c/4b. The browser host is the app's lifecycle for the browser
// listener: it starts only when the user already connected a browser (X12)
// and its tool lists follow the extension's presence.

private func sandbox() throws -> (home: URL, dir: URL, exe: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bh-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let dir = root.appendingPathComponent("b", isDirectory: true)
    try FileManager.default.createDirectory(
        at: home.appendingPathComponent("Library/Application Support/Comet"), withIntermediateDirectories: true)
    let exe = root.appendingPathComponent("Companion")
    try Data("#!/bin/sh\n".utf8).write(to: exe)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    return (home, dir, exe)
}

private func makeHost(_ box: (home: URL, dir: URL, exe: URL), executable: URL? = nil) -> BrowserHost {
    BrowserHost(
        directory: box.dir,
        installer: NativeHostInstaller(home: box.home, executable: executable ?? box.exe),
        language: { .en })
}

private func socketExists(_ box: (home: URL, dir: URL, exe: URL)) -> Bool {
    FileManager.default.fileExists(atPath: box.dir.appendingPathComponent("browser.sock").path)
}

@Test func hostDoesNotListenAtLaunchWithoutAManifest() throws {
    let box = try sandbox()
    let host = makeHost(box)
    host.startIfInstalled()
    defer { host.stop() }
    #expect(!socketExists(box), "nothing installed: nothing listens")
    expectEq(host.status, .notInstalled, "status")
}

@Test func hostListensAtLaunchWhenAManifestIsInstalled() throws {
    let box = try sandbox()
    _ = try NativeHostInstaller(home: box.home, executable: box.exe).install()
    let host = makeHost(box)
    host.startIfInstalled()
    defer { host.stop() }
    #expect(socketExists(box), "installed: listens without lending hands")
    expectEq(host.status, .disconnected, "installed and no extension yet")
}

@Test func connectInstallsAndStartsThenRemoveUndoesBoth() throws {
    let box = try sandbox()
    let host = makeHost(box)
    defer { host.stop() }
    expectEq(host.connect(), .done, "connect")
    #expect(socketExists(box))
    expectEq(host.status, .disconnected, "status after connect")
    expectEq(host.remove(), .done, "remove")
    #expect(!socketExists(box), "remove stops the listener")
    expectEq(host.status, .notInstalled, "status after remove")
}

@Test func connectAsksToMoveTheAppWhenThePathIsUnstable() throws {
    let box = try sandbox()
    let host = makeHost(box, executable: URL(fileURLWithPath: "/AppTranslocation/x/Companion"))
    expectEq(host.connect(), .moveApp, "translocated")
    #expect(!socketExists(box), "a failed install never starts the listener")
}

@Test func connectWithNoBrowserInstalledSaysSo() throws {
    let box = try sandbox()
    try FileManager.default.removeItem(at: box.home.appendingPathComponent("Library/Application Support/Comet"))
    let host = makeHost(box)
    expectEq(host.connect(), .noBrowser, "no browser folder")
    #expect(!socketExists(box))
}

@Test func statusReportsTheConnectedBrowser() throws {
    let box = try sandbox()
    _ = try NativeHostInstaller(home: box.home, executable: box.exe).install()
    let host = makeHost(box)
    host.presence.set(.comet)
    expectEq(host.status, .connected(.comet), "connected")
    host.presence.set(nil)
    expectEq(host.status, .disconnected, "dropped")
}

@Test func conversationHasBrowserToolsOnlyWhileConnected() throws {
    let box = try sandbox()
    let host = makeHost(box)
    let parent = StubTools(names: ["open_app"])
    let tools = host.conversationTools(parent: parent, apps: StubTools(names: ["slack_post"]))
    func names() -> Set<String> { Set(tools.specs(.en).map(\.name)) }
    #expect(names().isDisjoint(with: BrowserTool.allCases.map(\.rawValue)), "no extension: no browser tools")
    host.presence.set(.chrome)
    #expect(BrowserTool.allCases.allSatisfy { names().contains($0.rawValue) }, "connected: all five")
}

@Test func bridgeGetsBrowserToolsButNotTheAppTools() throws {
    let box = try sandbox()
    let host = makeHost(box)
    host.presence.set(.chrome)
    let parent = StubTools(names: ["open_app"])
    let appOnly = StubTools(names: ["slack_post"])
    let bridge = host.bridgeTools(parent: parent)
    let conversation = host.conversationTools(parent: parent, apps: appOnly)
    #expect(bridge.specs(.en).contains { $0.name == "browser_read" })
    #expect(!bridge.handles("slack_post"), "the bridge does not inherit the connected apps")
    #expect(conversation.handles("slack_post"))
}

// MARK: - Security review: M4, L2, live connection

private func foreignExecutable(in box: (home: URL, dir: URL, exe: URL)) throws -> URL {
    let other = box.exe.deletingLastPathComponent().appendingPathComponent("worktree-build")
    try Data("#!/bin/sh\n".utf8).write(to: other)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: other.path)
    return other
}

private func cometManifest(_ box: (home: URL, dir: URL, exe: URL)) -> URL {
    box.home.appendingPathComponent(
        "Library/Application Support/Comet/NativeMessagingHosts/com.karen.companion.browser.json")
}

@Test func aManifestPointingAtAnotherBuildDoesNotStartTheListener() throws {
    let box = try sandbox()
    _ = try NativeHostInstaller(home: box.home, executable: try foreignExecutable(in: box)).install()
    let host = makeHost(box)
    host.startIfInstalled()
    defer { host.stop() }
    #expect(!socketExists(box), "a stale or foreign manifest is not ours to start on")
    expectEq(host.status, .notInstalled, "and it is not shown as installed")
}

@Test func aManifestWithWidenedOriginsOrAnotherTypeDoesNotStartTheListener() throws {
    for (key, value) in [("allowed_origins", ["chrome-extension://evil/"] as Any), ("type", "http" as Any)] {
        let box = try sandbox()
        _ = try NativeHostInstaller(home: box.home, executable: box.exe).install()
        let url = cometManifest(box)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object[key] = value
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let host = makeHost(box)
        host.startIfInstalled()
        defer { host.stop() }
        #expect(!socketExists(box), "\(key) changed: not ours")
    }
}

@Test func removeStopsTheListenerEvenWhenALaterBrowserFails() throws {
    let box = try sandbox()
    try FileManager.default.createDirectory(
        at: box.home.appendingPathComponent("Library/Application Support/Google/Chrome"),
        withIntermediateDirectories: true)
    let host = makeHost(box)
    defer { host.stop() }
    expectEq(host.connect(), .done, "connect")
    let comet = cometManifest(box)
    let target = box.home.appendingPathComponent("victim.json")
    try FileManager.default.removeItem(at: comet)
    try Data("keep".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: comet, withDestinationURL: target)
    expectEq(host.remove(), .symlink, "the symlink is reported")
    #expect(!socketExists(box), "Chrome's manifest was removed, so the listener stops")
}

@Test func removeClosesTheLiveExtensionConnection() async throws {
    let box = try sandbox()
    let host = makeHost(box)
    defer { host.stop() }
    expectEq(host.connect(), .done, "connect")
    let token = try String(contentsOf: box.dir.appendingPathComponent("browser.token"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let client = try PosixTestClient(path: box.dir.appendingPathComponent("browser.sock").path)
    defer { client.close() }
    try client.send(browserHello(token: token))
    _ = await client.line()
    #expect(await browserWaitFor { host.presence.connected }, "the extension is connected")
    let tools = host.conversationTools(parent: StubTools(names: []), apps: StubTools(names: []))
    #expect(tools.specs(.en).contains { $0.name == "browser_read" }, "its tools are offered")
    expectEq(host.remove(), .done, "remove")
    #expect(await browserWaitFor { !host.presence.connected }, "removing the link drops the live connection")
    #expect(tools.specs(.en).isEmpty, "and its tools are withdrawn")
}

private struct StubTools: ParentToolExecuting {
    let names: [String]
    func specs(_ language: AppLanguage) -> [ToolSpec] {
        names.map { ToolSpec(name: $0, description: "", properties: [], required: []) }
    }
    func handles(_ name: String) -> Bool { names.contains(name) }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "", tool: name)
    }
}
