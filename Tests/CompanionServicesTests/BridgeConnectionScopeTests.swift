import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Darwin
import Foundation
import Testing

// Wave 20c D5 (M1, spec criterion 8). The bridge's authenticated state lives
// with ONE connection: a second socket that never sent a valid `hello` must
// not inherit the first one's open session, and a connection that went away
// must not be able to open anything for the one that replaced it.

/// A connected socket pair: `connection` is the server end the session
/// serves, `client` is what the test writes to and reads from. The peer of
/// the server end is this very process, which is what a real client is not,
/// but the wire behaviour is identical.
final class BridgePair: @unchecked Sendable {
    let connection: BridgeConnection
    private let clientFD: Int32
    private var buffer = Data()

    init(onClosed: @escaping @Sendable () -> Void = {}) {
        var fds: [Int32] = [0, 0]
        precondition(Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0, "socketpair")
        connection = BridgeConnection(fd: fds[0]) { _ in onClosed() }
        connection.start()
        clientFD = fds[1]
    }

    func send(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBufferPointer { Darwin.write(clientFD, $0.baseAddress, $0.count) }
    }

    /// One reply line, or nil after `timeout` (a silent server is an answer).
    func readLine(timeout: TimeInterval = 2) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[..<newline], encoding: .utf8)
                buffer.removeSubrange(...newline)
                return line
            }
            var pfd = pollfd(fd: clientFD, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&pfd, 1, 50) > 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = chunk.withUnsafeMutableBytes { Darwin.read(clientFD, $0.baseAddress, $0.count) }
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0 ..< n])
        }
        return nil
    }

    func closeClient() { Darwin.close(clientFD) }
}

func hello(_ id: Int, token: String = "tok") -> String {
    #"{"id":\#(id),"method":"hello","params":{"token":"\#(token)","client":"claude-code","protocol":1}}"#
}

func call(_ id: Int, _ name: String = "look") -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":{}}}"#
}

func makeSession(
    _ tools: FakeParentTools, _ approvals: ScriptedApprovals
) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { "tok" }, language: { .en }, accessibility: { true })
}

func pollUntilTrue(timeout: TimeInterval = 2, _ probe: @escaping @Sendable () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !probe(), Date() < deadline {
        await Task.yield()
        do { try await Task.sleep(nanoseconds: 5_000_000) } catch { return }
    }
}

@Test @MainActor func bridgeConnectionScopeTests() async {
    await testACallOnANewConnectionWithoutHelloGetsNoSession()
    await testASecondLiveConnectionIsBusyAndTheFirstStaysIntact()
    await testALateAnswerFromAGoneConnectionCannotOpenTheNewOne()
    testTheSlotIsHeldUntilTheSessionReleasesIt()
    await testServingReleasesTheSlotOnlyAfterTheStateIsReset()
    await testACloseBeforeTheCallbackIsWiredIsNeverLost()
    await testStartingTwiceRunsOneReader()
    await testACloseBeforeStartNeverRunsAReader()
    await testHoldingAfterTheReaderClosedReleasesOnce()
}

/// races-produccion 1: the peer is gone before the connection exists, so its
/// read loop hits EOF and closes at once. The slot release is one-shot, so the
/// callback has to be in place before the reader can run: guarded by passing
/// it at construction and starting the reader only in `start()`.
@MainActor func testACloseBeforeTheCallbackIsWiredIsNeverLost() async {
    var lost = 0
    for _ in 0 ..< 500 {
        var fds: [Int32] = [0, 0]
        precondition(Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0, "socketpair")
        Darwin.close(fds[1])
        let released = ReleaseCount()
        let connection = BridgeConnection(fd: fds[0]) { _ in released.bump() }
        connection.start()
        await pollUntilTrue { released.value > 0 }
        connection.close()
        // After the explicit close too: the reader's close and ours must add up to one.
        if released.value != 1 { lost += 1 }
    }
    expectEq(lost, 0, "races 1: el cierre avisa exactamente una vez aunque el cliente ya se hubiera ido")
}

final class ReleaseCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// The listener frees its one slot from `onClosed`. If that ran before the
/// session reset its state, a fast reconnect could be accepted while the old
/// authorization was still standing.
@MainActor func testTheSlotIsHeldUntilTheSessionReleasesIt() {
    let released = ReleaseCount()
    let pair = BridgePair(onClosed: { released.bump() })
    pair.connection.holdSlotUntilServed()
    pair.connection.close()
    expectEq(released.value, 0, "M1: cerrada pero el slot sigue tomado")
    pair.connection.releaseSlot()
    expectEq(released.value, 1, "M1: el slot se libera al terminar la sesion")
    pair.connection.releaseSlot()
    expectEq(released.value, 1, "M1: liberar dos veces no libera dos")
}

@MainActor func testServingReleasesTheSlotOnlyAfterTheStateIsReset() async {
    let tools = FakeParentTools()
    let session = makeSession(tools, ScriptedApprovals(answer: true))
    let released = ReleaseCount()
    let pair = BridgePair(onClosed: { released.bump() })
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    _ = pair.readLine()
    pair.send(call(2))
    _ = pair.readLine()
    expect(await session.state == .open(until: nil), "M1: la sesion esta abierta")
    pair.closeClient()
    await serving.value
    expectEq(released.value, 1, "M1: el slot se libero al terminar serve")
    expect(await session.state == .idle, "M1: el estado ya estaba en idle cuando se libero")
}

/// Criterion 8 proper: the first connection opens a real session and goes
/// away; a real second connection that skips `hello` must be told
/// `no_session`, not run on the hands the first one had opened. A silent or
/// timed-out server fails this test (it is not an acceptable "no").
@MainActor func testACallOnANewConnectionWithoutHelloGetsNoSession() async {
    let tools = FakeParentTools()
    let session = makeSession(tools, ScriptedApprovals(answer: true))
    let first = BridgePair()
    let firstServe = Task.detached { await session.serve(first.connection) }
    first.send(hello(1))
    _ = first.readLine()
    first.send(call(2))
    let opened = first.readLine() ?? "<silence>"
    expect(opened.contains(#""ok":true"#), "criterion 8: the first connection opens a real session: \(opened)")
    first.closeClient()
    await firstServe.value

    let second = BridgePair()
    let secondServe = Task.detached { await session.serve(second.connection) }
    second.send(call(3))
    let reply = second.readLine() ?? "<silence>"
    expect(reply.contains(BridgeCode.noSession), "criterion 8: a call without hello is no_session: \(reply)")
    expectEq(tools.executeCalls.count, 1, "criterion 8: the second connection never drove the hands")
    second.closeClient()
    await secondServe.value
}

/// Defense in depth, NOT criterion 8: the listener never serves a second
/// connection while one is live, but if one arrives anyway it gets `busy`
/// and must leave the first one's session untouched.
@MainActor func testASecondLiveConnectionIsBusyAndTheFirstStaysIntact() async {
    let tools = FakeParentTools()
    let session = makeSession(tools, ScriptedApprovals(answer: true))
    let first = BridgePair()
    let firstServe = Task.detached { await session.serve(first.connection) }
    first.send(hello(1))
    _ = first.readLine()
    first.send(call(2))
    _ = first.readLine()

    let second = BridgePair()
    let secondServe = Task.detached { await session.serve(second.connection) }
    second.send(call(3))
    let reply = second.readLine() ?? "<silence>"
    expect(reply.contains(BridgeCode.busy), "M1: a second live connection is busy: \(reply)")
    expectEq(tools.executeCalls.count, 1, "M1: the second connection did not drive the hands")

    first.send(call(4))
    expect((first.readLine() ?? "").contains(#""ok":true"#), "M1: the first is still alive and intact")
    first.closeClient()
    second.closeClient()
    await firstServe.value
    await secondServe.value
}

@MainActor func testALateAnswerFromAGoneConnectionCannotOpenTheNewOne() async {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(park: true)
    let session = makeSession(tools, approvals)
    let first = BridgePair()
    let firstServe = Task.detached { await session.serve(first.connection) }
    first.send(hello(1))
    _ = first.readLine()
    first.send(call(2))
    await pollUntilTrue { !approvals.requests.isEmpty }
    first.closeClient()
    await pollUntilTrue { !first.connection.isOpen }

    let second = BridgePair()
    let secondServe = Task.detached { await session.serve(second.connection) }
    second.send(hello(3))
    let helloReply = second.readLine() ?? ""
    expect(!helloReply.contains("error"), "M1: la conexion nueva parte de idle y su hello pasa")

    // The gone connection's sheet is answered late, with a yes.
    if let request = approvals.requests.first {
        _ = await approvals.resolve(requestId: request.requestId, approved: true)
    }
    await firstServe.value
    expectEq(tools.executeCalls.count, 0, "M1: el si tardio de otra conexion no ejecuta nada")
    expect(await session.state == .listed, "M1: la conexion nueva sigue en listed, sin sesion abierta")
    second.closeClient()
    await secondServe.value
}

/// A second `start()` must not spawn a second reader on the same fd: two
/// readers would split the bytes between them and garble the lines.
@MainActor func testStartingTwiceRunsOneReader() async {
    let pair = BridgePair()
    pair.connection.start()
    pair.send("uno")
    pair.send("dos")
    pair.closeClient()
    var got: [String] = []
    for await line in pair.connection.lines { got.append(line) }
    expectEq(got, ["uno", "dos"], "races 1: start dos veces, un solo lector y las lineas enteras")
}

/// `stop()` can close a connection the listener built but had not started:
/// the slot is released once and no reader ever touches the closed fd.
@MainActor func testACloseBeforeStartNeverRunsAReader() async {
    var fds: [Int32] = [0, 0]
    precondition(Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0, "socketpair")
    defer { Darwin.close(fds[1]) }
    let released = ReleaseCount()
    let connection = BridgeConnection(fd: fds[0]) { _ in released.bump() }
    connection.close()
    connection.start()
    var lines = 0
    for await _ in connection.lines { lines += 1 }
    expectEq(released.value, 1, "races 1: cerrar antes de arrancar libera el slot una vez")
    expectEq(lines, 0, "races 1: y ningun lector corre sobre el fd cerrado")
    var byte: UInt8 = 0
    expectEq(Darwin.read(fds[1], &byte, 1), 0, "races 1: el otro extremo ve el cierre")
}

/// The peer vanished and the reader already freed the slot before the
/// session got to hold it: holding and releasing afterwards adds nothing.
@MainActor func testHoldingAfterTheReaderClosedReleasesOnce() async {
    var fds: [Int32] = [0, 0]
    precondition(Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0, "socketpair")
    Darwin.close(fds[1])
    let released = ReleaseCount()
    let connection = BridgeConnection(fd: fds[0]) { _ in released.bump() }
    connection.start()
    await pollUntilTrue { released.value > 0 }
    connection.holdSlotUntilServed()
    connection.releaseSlot()
    expectEq(released.value, 1, "races 1: retener tras el cierre del lector no libera dos veces")
}
