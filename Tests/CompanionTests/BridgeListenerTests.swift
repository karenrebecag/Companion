import CompanionCore
import CompanionServices
import Darwin
import Foundation
import Testing

// Wave 17 (spec §5, fila 12 transporte, §9-1/2/3). Sockets reales bajo
// `$TMPDIR`, ruta corta (104 bytes de `sun_path`): permisos, una conexión
// activa, límite de línea, y que `stop()` limpia ambos archivos.
@Test @MainActor func bridgeListenerTests() async throws {
    try await testSocketAndTokenPermissions()
    try await testHelloRoundTripThroughASession()
    try await testSecondClientWhileFirstConnectedGetsBusy()
    try await testOversizedLineGetsFrameTooLargeAndCloses()
    try await testInvalidUTF8LineGetsBadFrameAndConnectionStaysOpen()
    try await testSessionApprovedAfterClientLeftDoesNotExecute()
    try testStopRemovesBothFiles()
    try await testStartAfterStopServesOnTheNewSocket()
}

private func tempBridgeDirectory() -> URL {
    // uuid.prefix(8): the sandbox's own $TMPDIR is already long, and
    // sockaddr_un.sun_path caps at 104 bytes.
    FileManager.default.temporaryDirectory
        .appendingPathComponent("bridge-\(UUID().uuidString.prefix(8))")
}

private func posixPermissions(_ path: String) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    return ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777
}

/// Polls until the accept loop (a background thread) has handed a
/// connection to `probe`, or the deadline passes.
private func waitForConnection(
    timeout: TimeInterval = 2, _ probe: @escaping @Sendable () -> BridgeConnection?
) async -> BridgeConnection? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let connection = probe() { return connection }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return probe()
}

/// Polls a plain boolean condition (a lock-guarded fake's recorded state),
/// giving up after `timeout` rather than hanging the suite.
private func pollUntil(timeout: TimeInterval = 2, _ probe: @escaping @Sendable () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !probe(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

// MARK: - 1. permissions

@MainActor func testSocketAndTokenPermissions() async throws {
    let dir = tempBridgeDirectory()
    let listener = BridgeListener(directory: dir) { _ in }
    try listener.start()
    defer { listener.stop() }

    expectEq(try posixPermissions(dir.path), 0o700, "directory: 0700")
    expectEq(try posixPermissions(dir.appendingPathComponent("bridge.sock").path), 0o600,
              "socket: 0600")
    let tokenPath = dir.appendingPathComponent("bridge.token").path
    expectEq(try posixPermissions(tokenPath), 0o600, "token file: 0600")

    let tokenContents = try String(contentsOfFile: tokenPath, encoding: .utf8)
    expectEq(tokenContents.count, 64, "token: 64 hex characters")
    expect(tokenContents.allSatisfy(\.isHexDigit), "token: hex only")
    expectEq(listener.token, tokenContents, "token: the property matches the file")
}

// MARK: - 2. a hello round trip through a real BridgeSession

@MainActor func testHelloRoundTripThroughASession() async throws {
    let dir = tempBridgeDirectory()
    let box = Box<BridgeConnection>()
    let listener = BridgeListener(directory: dir) { connection in box.set(connection) }
    try listener.start()
    defer { listener.stop() }

    let session = BridgeSession(
        tools: FakeParentTools(), guard: ParentToolGuard(),
        token: { listener.token }, language: { .en }, accessibility: { true })

    let client = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
    defer { client.close() }
    let connection = await waitForConnection { box.get() }
    expect(connection != nil, "hello: the listener accepted the client")
    guard let connection else { return }
    // Detached: a plain `Task {}` here would inherit this test's MainActor
    // isolation and never get to run its first hop, because the very next
    // line blocks the MainActor thread in a synchronous POSIX `read` —
    // self-deadlock until the client's 2 s receive timeout gives up.
    Task.detached { await session.serve(connection) }

    try client.send(
        #"{"id":1,"method":"hello","params":{"token":"\#(listener.token)","client":"claude-code","protocol":1}}"#)
    let reply = client.readLine()
    expect(reply?.contains("\"session\"") == true, "hello: reply carries a session id")
}

// MARK: - 3. one active connection

@MainActor func testSecondClientWhileFirstConnectedGetsBusy() async throws {
    let dir = tempBridgeDirectory()
    let box = Box<BridgeConnection>()
    let listener = BridgeListener(directory: dir) { connection in box.set(connection) }
    try listener.start()
    defer { listener.stop() }

    let first = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
    defer { first.close() }
    _ = await waitForConnection { box.get() }

    let second = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
    let reply = second.readLine()
    expect(reply?.contains(BridgeCode.busy) == true, "second client: a busy error line")
    expect(second.waitForEOF(), "second client: then EOF")
    second.close()
}

// MARK: - line limit

@MainActor func testOversizedLineGetsFrameTooLargeAndCloses() async throws {
    let dir = tempBridgeDirectory()
    let box = Box<BridgeConnection>()
    let listener = BridgeListener(directory: dir) { connection in box.set(connection) }
    try listener.start()
    defer { listener.stop() }

    let client = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
    defer { client.close() }
    let connection = await waitForConnection { box.get() }
    expect(connection != nil, "oversized: the listener accepted the client")

    try client.send(String(repeating: "x", count: 70_000))
    let reply = client.readLine()
    expect(reply?.contains(BridgeCode.frameTooLarge) == true, "oversized: frame_too_large")
    expect(client.waitForEOF(), "oversized: the connection closes")
}

/// Security review 2026-09-28 (MEDIUM): a line that fails UTF-8 decoding
/// used to be consumed silently — no reply, so the shim would wait on that
/// request's id forever. Now it gets an id-less `bad_frame` line and the
/// connection stays open for the next (valid) line.
@MainActor func testInvalidUTF8LineGetsBadFrameAndConnectionStaysOpen() async throws {
    let dir = tempBridgeDirectory()
    let box = Box<BridgeConnection>()
    let listener = BridgeListener(directory: dir) { connection in box.set(connection) }
    try listener.start()
    defer { listener.stop() }

    let session = BridgeSession(
        tools: FakeParentTools(), guard: ParentToolGuard(),
        token: { listener.token }, language: { .en }, accessibility: { true })

    let client = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
    defer { client.close() }
    let connection = await waitForConnection { box.get() }
    expect(connection != nil, "bad utf8: the listener accepted the client")
    guard let connection else { return }
    Task.detached { await session.serve(connection) }

    try client.sendRaw([0xFF, 0xFE, 0x0A])
    let badFrameReply = client.readLine()
    expect(badFrameReply?.contains(BridgeCode.badFrame) == true, "bad utf8: a bad_frame error line")

    try client.send(
        #"{"id":1,"method":"hello","params":{"token":"\#(listener.token)","client":"claude-code","protocol":1}}"#)
    let helloReply = client.readLine()
    expect(helloReply?.contains("\"session\"") == true,
           "bad utf8: the connection stays usable — hello still works")
}

/// Security review 2026-09-28 (MEDIUM): if the peer disconnects while the
/// session-open sheet is up (a plain EOF, not "Stop hands"), an approve
/// answer that arrives afterward used to still `beginTurn()` and execute
/// the action on a connection nobody is reading from any more.
@MainActor func testSessionApprovedAfterClientLeftDoesNotExecute() async throws {
    let dir = tempBridgeDirectory()
    let box = Box<BridgeConnection>()
    let listener = BridgeListener(directory: dir) { connection in box.set(connection) }
    try listener.start()
    defer { listener.stop() }

    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(park: true)
    let session = BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { listener.token }, language: { .en }, accessibility: { true })

    let client = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
    defer { client.close() }
    let connection = await waitForConnection { box.get() }
    expect(connection != nil, "M4: the listener accepted the client")
    guard let connection else { return }
    Task.detached { await session.serve(connection) }

    try client.send(
        #"{"id":1,"method":"hello","params":{"token":"\#(listener.token)","client":"claude-code","protocol":1}}"#)
    _ = client.readLine()
    try client.send(#"{"id":2,"method":"call","params":{"name":"look","arguments":{}}}"#)
    await pollUntil { !approvals.requests.isEmpty }

    // The client leaves while the sheet is up — a plain EOF, not stop().
    // `connection.close()` directly (rather than the socket's own EOF
    // detection) makes the moment of disconnect deterministic for the test.
    connection.close()

    let requestId = approvals.requests.first!.requestId
    _ = await approvals.resolve(requestId: requestId, approved: true)

    let deadline = Date().addingTimeInterval(2)
    while await session.state != .idle, Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }

    expect(tools.executeCalls.isEmpty, "M4: nothing executed after the client left")
    expect(await session.state == .idle, "M4: state idle — connectionClosed already ran")
}

// MARK: - 5. stop() cleans up

func testStopRemovesBothFiles() throws {
    let dir = tempBridgeDirectory()
    let listener = BridgeListener(directory: dir) { _ in }
    try listener.start()
    let sockPath = dir.appendingPathComponent("bridge.sock").path
    let tokenPath = dir.appendingPathComponent("bridge.token").path
    expect(FileManager.default.fileExists(atPath: sockPath), "before stop: socket exists")
    expect(FileManager.default.fileExists(atPath: tokenPath), "before stop: token exists")

    listener.stop()

    expect(!FileManager.default.fileExists(atPath: sockPath), "after stop: socket removed")
    expect(!FileManager.default.fileExists(atPath: tokenPath), "after stop: token removed")
}

// MARK: - 6. start() after stop() on the same instance

/// Code review 2026-09-28 (MEDIUM): `BridgeHost` keeps ONE listener for the
/// app's lifetime and flips it with the "Prestar las manos" toggle, so
/// start→stop→start on the same instance is a user-reachable path nothing
/// exercised. The second cycle must accept a client on the new socket, hand
/// it a fresh token, and serve a `hello` end to end.
@MainActor func testStartAfterStopServesOnTheNewSocket() async throws {
    let dir = tempBridgeDirectory()
    let box = Box<BridgeConnection>()
    let listener = BridgeListener(directory: dir) { connection in box.set(connection) }
    try listener.start()
    let firstToken = listener.token
    listener.stop()
    try listener.start()
    defer { listener.stop() }

    expect(listener.token != firstToken, "restart: the token is regenerated")
    expectEq(listener.token.count, 64, "restart: the new token is a full token")

    let session = BridgeSession(
        tools: FakeParentTools(), guard: ParentToolGuard(),
        token: { listener.token }, language: { .en }, accessibility: { true })
    let client = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
    defer { client.close() }
    let connection = await waitForConnection { box.get() }
    expect(connection != nil, "restart: the second listen socket accepts")
    guard let connection else { return }
    Task.detached { await session.serve(connection) }

    try client.send(
        #"{"id":1,"method":"hello","params":{"token":"\#(listener.token)","client":"claude-code","protocol":1}}"#)
    let reply = client.readLine()
    expect(reply?.contains("\"session\"") == true, "restart: hello round-trips on the new socket")
}

// MARK: - test helpers

/// A lock-guarded box: `BridgeListener`'s `onConnection` is `@Sendable` and
/// runs on the accept thread, so a plain `var` capture would race.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ newValue: T) { lock.withLock { value = newValue } }
    func get() -> T? { lock.withLock { value } }
}

/// A minimal blocking Unix-socket client, POSIX like the listener under
/// test. A receive timeout keeps a stalled read from hanging the suite.
final class PosixTestClient {
    private let fd: Int32

    init(path: String) throws {
        let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw PosixTestClientError.socket }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(socketFD)
            throw PosixTestClientError.pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: pathBytes) }
        let connected = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let err = errno
            Darwin.close(socketFD)
            throw PosixTestClientError.connect(err)
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) { ptr in
            Darwin.setsockopt(
                socketFD, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }
        self.fd = socketFD
    }

    func send(_ line: String) throws {
        try sendRaw(Array((line + "\n").utf8))
    }

    /// Raw bytes, not necessarily valid UTF-8 or JSON — for exercising the
    /// framing layer directly (M3: an invalid-UTF-8 line).
    func sendRaw(_ bytes: [UInt8]) throws {
        let sent = bytes.withUnsafeBufferPointer { ptr in
            Darwin.write(fd, ptr.baseAddress, ptr.count)
        }
        guard sent == bytes.count else { throw PosixTestClientError.writeFailed }
    }

    /// Reads to the next `\n`, EOF, or the socket's receive timeout.
    func readLine() -> String? {
        var buffer = [UInt8]()
        var byte: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &byte, 1)
            guard n > 0 else { return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self) }
            if byte == 0x0A { return String(decoding: buffer, as: UTF8.self) }
            buffer.append(byte)
        }
    }

    /// True once the peer closes (`read` returns 0) within the timeout.
    func waitForEOF() -> Bool {
        var byte: UInt8 = 0
        return Darwin.read(fd, &byte, 1) == 0
    }

    func close() { Darwin.close(fd) }
}

enum PosixTestClientError: Error {
    case socket
    case pathTooLong
    case connect(Int32)
    case writeFailed
}
