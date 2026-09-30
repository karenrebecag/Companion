import CompanionCore
import CompanionServices
import Darwin
import Foundation
import Testing

// Wave 18-2 (§8-7, §9). The channel between the relay's socket and the
// tools: one extension, authenticated by hello, calls answered by id.
// Real Unix sockets, like BridgeListenerTests.

/// Blocking reads run on a GCD thread: many suites in parallel each parking a
/// cooperative-pool thread in `read` starve the actors under test.
extension PosixTestClient {
    func line() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: self.readLine()) }
        }
    }

    func eof() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: self.waitForEOF()) }
        }
    }
}

let browserTestToken = "test-token-0123456789"

struct BrowserRig {
    let dir: URL
    let listener: BridgeListener
    let channel: BrowserChannel
    let presence: BrowserPresence
    let socketPath: String
    let accepted: Box<BridgeConnection>

    func client() throws -> PosixTestClient { try PosixTestClient(path: socketPath) }
}

/// `attachDetached: false` hands the accepted connection to the test, which
/// attaches it inside a `Log.capturing` scope (detached tasks lose the capture).
func makeBrowserRig(helloDeadline: Duration = .seconds(5), attachDetached: Bool = true) throws -> BrowserRig {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("brc-\(UUID().uuidString.prefix(8))")
    let presence = BrowserPresence()
    let channel = BrowserChannel(presence: presence, token: { browserTestToken }, helloDeadline: helloDeadline)
    let accepted = Box<BridgeConnection>()
    let listener = BridgeListener(
        directory: dir, socketName: "browser.sock", tokenName: "browser.token"
    ) { connection in
        if attachDetached {
            Task.detached { await channel.attach(connection) }
        } else {
            accepted.set(connection)
        }
    }
    try listener.start()
    return BrowserRig(dir: dir, listener: listener, channel: channel, presence: presence,
               socketPath: dir.appendingPathComponent("browser.sock").path, accepted: accepted)
}

func browserHello(token: String = browserTestToken, protocolVersion: Int = 1, id: Int = 1) -> String {
    #"{"id":\#(id),"method":"hello","params":{"extension":"gaipfdnbliibnfchgcnamnjpfgkilnll","browser":"comet","version":"0.1.0","protocol":\#(protocolVersion),"token":"\#(token)"}}"#
}

func browserWaitFor(timeout: TimeInterval = 2, _ probe: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if probe() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return probe()
}

/// Connects, says hello, and waits for the reply, leaving a live session.
func browserConnected(_ rig: BrowserRig) async throws -> PosixTestClient {
    let client = try rig.client()
    try client.send(browserHello())
    let reply = (await client.line())
    expect(reply?.contains(#""ok":true"#) == true, "helper: hello accepted")
    _ = await browserWaitFor { rig.presence.connected }
    return client
}

func browserCallID(_ line: String?) -> Int? {
    guard let line, let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object["id"] as? Int
}

func browserTabsReply(_ id: Int) -> String {
    #"{"id":\#(id),"result":{"tabs":[{"id":12,"title":"Inbox","url":"https://mail.example/","active":true}]}}"#
}

@Test func helloWithTheRightTokenIsAcceptedAndPublishesPresence() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    expect(!rig.presence.connected, "hello: nobody before the handshake")
    let client = try rig.client()
    defer { client.close() }
    try client.send(browserHello(id: 7))
    let reply = (await client.line())
    expectEq(reply, #"{"id":7,"result":{"ok":true}}"#, "hello: helloOK echoes the id")
    expect(await browserWaitFor { rig.presence.connected }, "hello: presence is connected")
    expectEq(rig.presence.browser, .comet, "hello: presence carries the browser")
}

@Test func helloWithABadTokenGetsBadTokenAndClose() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try rig.client()
    defer { client.close() }
    try client.send(browserHello(token: "wrong"))
    let reply = (await client.line())
    expect(reply?.contains(BridgeCode.badToken) == true, "bad token: bad_token error")
    expect((await client.eof()), "bad token: the connection closes")
    expect(!rig.presence.connected, "bad token: presence stays disconnected")
}

@Test func aTokenThatIsAPrefixOfTheRealOneIsRejected() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try rig.client()
    defer { client.close() }
    try client.send(browserHello(token: String(browserTestToken.dropLast())))
    expect((await client.line())?.contains(BridgeCode.badToken) == true, "prefix token: rejected")
    expect((await client.eof()), "prefix token: closed")
}

@Test func unsupportedProtocolVersionIsRejected() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try rig.client()
    defer { client.close() }
    try client.send(browserHello(protocolVersion: 2))
    expect((await client.line())?.contains(BridgeCode.badToken) == true, "protocol 2: rejected")
    expect((await client.eof()), "protocol 2: closed")
    expect(!rig.presence.connected, "protocol 2: not connected")
}

@Test func aFirstFrameThatIsNotHelloIsRejected() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try rig.client()
    defer { client.close() }
    try client.send(browserTabsReply(1))
    expect((await client.line())?.contains(BridgeCode.badToken) == true, "no hello first: rejected")
    expect((await client.eof()), "no hello first: closed")
}

@Test func silenceAfterConnectingClosesAtTheHelloDeadline() async throws {
    // The client waits 2 s for EOF (PosixTestClient's receive timeout): a full second of margin over the deadline.
    let rig = try makeBrowserRig(helloDeadline: .seconds(1))
    defer { rig.listener.stop() }
    let client = try rig.client()
    defer { client.close() }
    expect((await client.eof()), "deadline: closed with no hello")
    expect(!rig.presence.connected, "deadline: never connected")
}

@Test func aHelloInsideTheDeadlineIsNotClosedLater() async throws {
    let rig = try makeBrowserRig(helloDeadline: .seconds(1))
    defer { rig.listener.stop() }
    let started = Date()
    let client = try await browserConnected(rig)
    defer { client.close() }
    expect(Date().timeIntervalSince(started) < 1, "deadline: the hello landed inside the deadline (the premise of the test)")
    // Watches until the hello timer's moment has passed: an authenticated session must still be there.
    let outlived = await browserWaitFor(timeout: 1.5) { !rig.presence.connected }
    expect(!outlived, "deadline: an authenticated session outlives the hello timer")
}

@Test func aSecondExtensionWhileOneIsConnectedGetsBusy() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let first = try await browserConnected(rig)
    defer { first.close() }
    let second = try rig.client()
    defer { second.close() }
    expect((await second.line())?.contains(BridgeCode.busy) == true, "second: busy")
    expect(rig.presence.connected, "second: the first stays connected")
}

@Test func aCallAndItsReplyRoundtripById() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }

    let pending = Task { await rig.channel.send(.tabs, timeout: .seconds(5)) }
    let line = (await client.line())
    expect(line?.contains(#""name":"browser_tabs""#) == true, "roundtrip: the call names the tool")
    guard let id = browserCallID(line) else { expect(false, "roundtrip: call has an id"); return }
    try client.send(browserTabsReply(id))
    let result = await pending.value
    let expected = BrowserInbound.tabs(id: id, [BrowserTab(id: 12, title: "Inbox", url: "https://mail.example/", active: true)])
    expectEq(result, .success(expected), "roundtrip: the reply resumes the caller")
}

@Test func idsAreMonotonicAndRepliesMatchTheirOwnCall() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }

    let first = Task { await rig.channel.send(.tabs, timeout: .seconds(5)) }
    let firstID = browserCallID((await client.line()))
    let second = Task { await rig.channel.send(.tabs, timeout: .seconds(5)) }
    let secondID = browserCallID((await client.line()))
    guard let firstID, let secondID else { expect(false, "ids: both calls have ids"); return }
    expect(secondID > firstID, "ids: monotonic")
    // Answered out of order: each caller still gets its own reply.
    try client.send(#"{"id":\#(secondID),"result":{"done":"second"}}"#)
    try client.send(browserTabsReply(firstID))
    let firstResult = await first.value
    let secondResult = await second.value
    expectEq(secondResult, .failure(ContractError(code: BridgeCode.badFrame, message: "Unexpected reply for browser_tabs")),
             "ids: a done reply to tabs is a bad_frame, not delivered as tabs")
    if case .success(.tabs(let id, _)) = firstResult { expectEq(id, firstID, "ids: first got its own reply") }
    else { expect(false, "ids: first got a tabs reply") }
}

@Test func aCallThatTimesOutFailsWithTimeoutAndItsLateReplyIsDropped() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }

    let slow = Task { await rig.channel.send(.tabs, timeout: .milliseconds(100)) }
    guard let lateID = browserCallID((await client.line())) else { expect(false, "timeout: call has an id"); return }
    let result = await slow.value
    if case .failure(let error) = result { expectEq(error.code, BridgeCode.timeout, "timeout: code") }
    else { expect(false, "timeout: expected a failure") }

    try client.send(browserTabsReply(lateID))
    let next = Task { await rig.channel.send(.tabs, timeout: .seconds(5)) }
    guard let nextID = browserCallID((await client.line())) else { expect(false, "timeout: next call has an id"); return }
    expect(nextID != lateID, "timeout: the next call has a fresh id")
    try client.send(browserTabsReply(nextID))
    if case .success(.tabs(let id, _)) = await next.value { expectEq(id, nextID, "timeout: the next call is unaffected by the late reply") }
    else { expect(false, "timeout: the next call succeeds") }
    expect(rig.presence.connected, "timeout: the session survives")
}

@Test func aReplyRacingItsTimeoutResumesTheCallerExactlyOnce() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }
    // A double resume of a CheckedContinuation traps the whole process, so
    // simply surviving many near-simultaneous reply/timeout pairs is the test.
    for _ in 0 ..< 25 {
        let call = Task { await rig.channel.send(.tabs, timeout: .milliseconds(20)) }
        guard let id = browserCallID((await client.line())) else { expect(false, "race: call has an id"); return }
        try await Task.sleep(nanoseconds: 20_000_000)
        try client.send(browserTabsReply(id))
        _ = await call.value
    }
    expect(rig.presence.connected, "race: still connected after 25 racing calls")
}

@Test func anErrorReplyFailsTheCallWithTheExtensionsCode() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }
    let call = Task { await rig.channel.send(.click(tab: 12, generation: 3, element: 9), timeout: .seconds(5)) }
    guard let id = browserCallID((await client.line())) else { expect(false, "error reply: call has an id"); return }
    try client.send(#"{"id":\#(id),"error":{"code":"stale_id","message":"element 9 is gone"}}"#)
    expectEq(await call.value, .failure(ContractError(code: BridgeCode.staleId, message: "element 9 is gone")),
             "error reply: code and message reach the caller")
}

@Test func disconnectFailsEveryPendingCallWithNotConnectedAndClearsPresence() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)

    let first = Task { await rig.channel.send(.tabs, timeout: .seconds(30)) }
    let second = Task { await rig.channel.send(.read(tab: 1, selector: nil), timeout: .seconds(30)) }
    _ = (await client.line())
    _ = (await client.line())
    client.close()

    for result in [await first.value, await second.value] {
        if case .failure(let error) = result { expectEq(error.code, BridgeCode.notConnected, "disconnect: not_connected") }
        else { expect(false, "disconnect: pending calls must fail") }
    }
    expect(await browserWaitFor { !rig.presence.connected }, "disconnect: presence cleared")
    if case .failure(let error) = await rig.channel.send(.tabs, timeout: .seconds(1)) {
        expectEq(error.code, BridgeCode.notConnected, "disconnect: later sends fail fast")
    } else { expect(false, "disconnect: later sends fail") }
}

@Test func sendBeforeAnyExtensionIsNotConnected() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    if case .failure(let error) = await rig.channel.send(.tabs, timeout: .seconds(1)) {
        expectEq(error.code, BridgeCode.notConnected, "no extension: not_connected")
    } else { expect(false, "no extension: must fail") }
}

@Test func aNewExtensionCanConnectAfterTheFirstLeaves() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let first = try await browserConnected(rig)
    first.close()
    expect(await browserWaitFor { !rig.presence.connected }, "reconnect: first is gone")
    let second = try await browserConnected(rig)
    defer { second.close() }
    expect(rig.presence.connected, "reconnect: the second session is live")
    let call = Task { await rig.channel.send(.tabs, timeout: .seconds(5)) }
    guard let id = browserCallID((await second.line())) else { expect(false, "reconnect: call has an id"); return }
    try second.send(browserTabsReply(id))
    if case .success = await call.value {} else { expect(false, "reconnect: calls work on the new session") }
}

@Test func anInboundCallFromTheExtensionIsRejectedAndNeverExecuted() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }
    try client.send(#"{"id":5,"method":"call","params":{"name":"click","arguments":{}}}"#)
    let reply = (await client.line())
    expect(reply?.contains(BridgeCode.unknownMethod) == true, "inbound call: unknown_method")
    expect(rig.presence.connected, "inbound call: the session is not torn down")
}

@Test func aSecondHelloAfterAuthenticationIsRefused() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }
    try client.send(browserHello(id: 2))
    expect((await client.line())?.contains(BridgeCode.badFrame) == true, "second hello: bad_frame")
}

@Test func anOversizedCommandIsRefusedBeforeItIsWritten() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }
    let text = String(repeating: "x", count: BrowserWire.maxLineBytes)
    let result = await rig.channel.send(.type(tab: 1, generation: 1, element: 1, text: text), timeout: .seconds(1))
    if case .failure(let error) = result { expectEq(error.code, BridgeCode.frameTooLarge, "oversize: frame_too_large") }
    else { expect(false, "oversize: must fail") }
    expect(rig.presence.connected, "oversize: the session survives")
}

@Test func garbageAfterHelloGetsAnErrorAndTheSessionSurvives() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }
    try client.send("not json")
    expect((await client.line())?.contains(BridgeCode.badFrame) == true, "garbage: bad_frame")
    expect(rig.presence.connected, "garbage: still connected")
}

@Test func logsCarryToolCodeOriginAndCharCountButNeverPageText() async throws {
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("brc-log-\(UUID().uuidString.prefix(8)).log")
    defer { do { try FileManager.default.removeItem(at: logURL) } catch {} }
    let secret = "SECRET-PAGE-TEXT-4242"
    try await Log.capturing(to: logURL) {
        let rig = try makeBrowserRig(attachDetached: false)
        defer { rig.listener.stop() }
        let client = try rig.client()
        defer { client.close() }
        _ = await browserWaitFor { rig.accepted.get() != nil }
        guard let accepted = rig.accepted.get() else { return }
        Task { await rig.channel.attach(accepted) }
        try client.send(browserHello())
        _ = (await client.line())
        _ = await browserWaitFor { rig.presence.connected }
        let call = Task { await rig.channel.send(.read(tab: 12, selector: nil), timeout: .seconds(5)) }
        guard let id = browserCallID((await client.line())) else { return }
        let page = #"{"id":\#(id),"result":{"page":{"tab":12,"origin":"https://bank.example","url":"https://bank.example/a","title":"\#(secret)","text":"\#(secret)","generation":1,"truncated":false,"elements":[]}}}"#
        try client.send(page)
        _ = await call.value
    }
    let log = try String(contentsOf: logURL, encoding: .utf8)
    expect(!log.contains(secret), "logs: page text never reaches the log")
    expect(log.contains("tool=browser_read"), "logs: the tool is named")
    expect(!log.contains("bank.example") && !log.contains("origin="), "logs: neither origin nor host is named")
    expect(log.contains("chars=\(secret.count)"), "logs: only a char count of the text")
}
