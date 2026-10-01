import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 18b. The idle sweep runs on the host's own timer, and stops with it.

private struct NoTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { false }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "", tool: name)
    }
}

private func startedHost(channel: FakeBrowserChannel, clock: LeaseClock) throws -> BrowserHost {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sw-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    try FileManager.default.createDirectory(
        at: home.appendingPathComponent("Library/Application Support/Comet"), withIntermediateDirectories: true)
    let executable = root.appendingPathComponent("Companion")
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let host = BrowserHost(
        directory: root.appendingPathComponent("b", isDirectory: true),
        installer: NativeHostInstaller(home: home, executable: executable),
        language: { .en }, commanding: channel, sweepEvery: .milliseconds(10), now: { clock.now })
    host.presence.set(.chrome)
    guard host.connect() == .done else { throw SweepSetupError() }
    return host
}

private struct SweepSetupError: Error {}

private func releases(_ channel: FakeBrowserChannel) -> Int {
    channel.sent.map(\.command).filter { if case .release = $0 { return true }; return false }.count
}

private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<400 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

private let tab12 = #"{"tab":12}"#

@Test func theHostsTimerGivesBackATabIdleForTenMinutes() async throws {
    let channel = FakeBrowserChannel(
        pages: [crmPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false)])
    let clock = LeaseClock()
    let host = try startedHost(channel: channel, clock: clock)
    defer { host.stop() }
    let conversation = host.conversationTools(parent: NoTools(), apps: NoTools())
    _ = await conversation.execute(name: "browser_take", argumentsJSON: tab12)
    expectEq(releases(channel), 0, "nothing is given back while the tab is warm")
    clock.advance(BrowserLease.idleRelease + 1)
    let arrived = await eventually { releases(channel) == 1 }
    expect(arrived, "a release frame arrives without anyone calling a tool")
}

@Test func stoppingTheHostEndsTheSweep() async throws {
    let channel = FakeBrowserChannel(
        pages: [crmPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false)])
    let clock = LeaseClock()
    let host = try startedHost(channel: channel, clock: clock)
    let conversation = host.conversationTools(parent: NoTools(), apps: NoTools())
    _ = await conversation.execute(name: "browser_take", argumentsJSON: tab12)
    host.stop()
    clock.advance(BrowserLease.idleRelease + 1)
    try await Task.sleep(for: .milliseconds(150))
    expectEq(releases(channel), 0, "a stopped host sweeps no more")
}
