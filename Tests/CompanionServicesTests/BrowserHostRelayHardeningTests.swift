import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Darwin
import Foundation
import Testing

// Wave 18-2 review fixes: the relay under the conditions a hostile or broken
// neighbourhood creates (dead stdout, no app, tampered token, boundary sizes).

private func parsedObject(_ line: String) -> [String: Any] {
    let value = try? JSONSerialization.jsonObject(with: Data(line.utf8))
    return value as? [String: Any] ?? [:]
}

private func tokenURL(_ app: App) -> URL { app.dir.appendingPathComponent("browser.token") }

private func realToken(_ app: App) -> String { app.listener.token }

private func chmod(_ url: URL, _ mode: mode_t) throws {
    guard Darwin.chmod(url.path, mode) == 0 else { throw PosixTestClientError.socket }
}

private func exitedWithoutConnecting(
    _ run: RelayRun, _ log: ConnectionLog, _ app: App, _ label: String
) async throws {
    let code = await run.exitCode()
    expect(code != nil && code != 0, "\(label): non-zero exit")
    expectEq(try app.connectionsBeforeAProbe(log), 0, "\(label): the app never saw a connection")
    // A relay that is still running holds the pipe open: reading to EOF would hang the suite instead of failing it.
    guard code != nil else { run.closeStdin(); return }
    expectEq(run.stdoutFrames().frames, [], "\(label): nothing on stdout")
}

extension SigpipeSensitive {
    @Test func theRelayProtectsItsOutputFdSoADeadPipeIsAnErrorNotASignal() async throws {
        try await withSigpipeCounter {
            let control = Pipe()
            do { try control.fileHandleForReading.close() } catch { expect(false, "control: close failed \(error)") }
            _ = RelayIO.writeAll(control.fileHandleForWriting.fileDescriptor, Data([0x41]))
            expect(await waitForSigpipes(atLeast: 1), "control: an unprotected pipe raises SIGPIPE (the harness can fail)")

            let guarded = Pipe()
            RelayIO.suppressSigpipe(on: guarded.fileHandleForWriting.fileDescriptor)
            do { try guarded.fileHandleForReading.close() } catch { expect(false, "guarded: close failed \(error)") }
            let wrote = RelayIO.writeAll(guarded.fileHandleForWriting.fileDescriptor, Data([0x41]))
            expect(!wrote, "guarded: the write reports failure")
            expect(await stayedBelow(sigpipes: 2), "guarded: and raises no signal beyond the control's")
        }
    }

    @Test func aDeadStdoutEndsTheRelayWithExitZeroInsteadOfKillingTheProcess() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        try await withSigpipeCounter {
            let run = RelayRun(directory: app.dir)
            run.send(helloJSON())
            guard let connection = await app.connection() else { expect(false, "dead stdout: connected"); return }
            _ = await app.lines(connection, count: 1)
            // Chrome kills the port: nobody reads stdout any more.
            do { try run.stdout.fileHandleForReading.close() } catch { expect(false, "dead stdout: close failed \(error)") }
            // stdin stays open, so only the failed write after the close can end the relay.
            connection.send(line: #"{"id":1,"result":{"ok":true}}"#)
            expectEq(await run.exitCode(), 0, "dead stdout: exit 0, caused by the write to the dead pipe")
            expect(await stayedBelow(sigpipes: 1), "dead stdout: no SIGPIPE from the relay's own write")
            run.closeStdin()
        }
    }

    /// The flag is process-wide, so the test restores what it found.
    @Test func ignoreSigpipeSetsTheProcessWideDispositionTheProductionPathNeeds() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let before = signal(SIGPIPE, SIG_DFL)
        defer { signal(SIGPIPE, before) }
        let run = RelayRun(origin: "chrome-extension://someoneelse/", directory: app.dir, ignoreSIGPIPE: true)
        _ = await run.exitCode()
        let during = signal(SIGPIPE, SIG_DFL)
        expectEq(unsafeBitCast(during, to: Int.self), unsafeBitCast(SIG_IGN, to: Int.self), "sigign: the relay ignores SIGPIPE")
    }
}

@Test func aTokenFileWithNoListenerBehindItExitsNonZeroWithoutOutput() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rly-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let token = dir.appendingPathComponent("browser.token")
    FileManager.default.createFile(atPath: token.path, contents: Data("t0ken".utf8), attributes: [.posixPermissions: 0o600])

    let absent = RelayRun(directory: dir)
    expectEq(await absent.exitCode(), 1, "no app: exit 1 when the socket file does not exist")
    expectEq(absent.stdoutFrames().frames, [], "no app: nothing on stdout")

    // A socket file left by a dead process: bound, never listened, so connect is refused.
    let stale = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    try BridgeSocket.bind(fd: stale, path: dir.appendingPathComponent("browser.sock").path)
    Darwin.close(stale)
    let refused = RelayRun(directory: dir)
    expectEq(await refused.exitCode(), 1, "stale socket: exit 1 when nothing accepts")
    expectEq(refused.stdoutFrames().frames, [], "stale socket: nothing on stdout")
}

@Test func aSymlinkedTokenFileIsNotFollowedAndTheSocketIsNeverTouched() async throws {
    let log = ConnectionLog()
    let app = try makeGreetingApp(log: log)
    defer { app.listener.stop() }
    let elsewhere = app.dir.appendingPathComponent("elsewhere.token")
    FileManager.default.createFile(atPath: elsewhere.path, contents: Data(realToken(app).utf8), attributes: [.posixPermissions: 0o600])
    try FileManager.default.removeItem(at: tokenURL(app))
    try FileManager.default.createSymbolicLink(at: tokenURL(app), withDestinationURL: elsewhere)
    try await exitedWithoutConnecting(RelayRun(directory: app.dir), log, app, "symlink")
}

@Test func aGroupReadableTokenFileIsRefusedAndTheSocketIsNeverTouched() async throws {
    let log = ConnectionLog()
    let app = try makeGreetingApp(log: log)
    defer { app.listener.stop() }
    try chmod(tokenURL(app), 0o640)
    try await exitedWithoutConnecting(RelayRun(directory: app.dir), log, app, "group-readable")
}

@Test func aWorldReadableTokenFileIsRefusedToo() async throws {
    let log = ConnectionLog()
    let app = try makeGreetingApp(log: log)
    defer { app.listener.stop() }
    try chmod(tokenURL(app), 0o604)
    try await exitedWithoutConnecting(RelayRun(directory: app.dir), log, app, "world-readable")
}

@Test func aTokenFileOverTheCapIsRefusedAndTheSocketIsNeverTouched() async throws {
    let log = ConnectionLog()
    let app = try makeGreetingApp(log: log)
    defer { app.listener.stop() }
    try Data(String(repeating: "a", count: 4096).utf8).write(to: tokenURL(app))
    try await exitedWithoutConnecting(RelayRun(directory: app.dir), log, app, "oversized")
}

@Test func aTokenFileTheUserOwnsWithMode0600StillWorks() async throws {
    let app = try makeApp()
    defer { app.listener.stop() }
    let run = RelayRun(directory: app.dir)
    run.send(helloJSON())
    guard let connection = await app.connection() else { expect(false, "0600: connected"); return }
    let lines = await app.lines(connection, count: 1)
    let params = parsedObject(lines.first ?? "")["params"] as? [String: Any]
    expectEq(params?["token"] as? String, app.listener.token, "0600: the token is read and injected")
    run.closeStdin()
    _ = await run.exitCode()
}

// MARK: - boundary of the re-encoded line (X7)

/// A frame whose compact re-encoding is exactly `total` bytes, sent with
/// whitespace so the input is longer than what the relay measures.
private func frame(id: Int, encodedBytes total: Int) -> (input: String, encoded: String) {
    let shell = #"{"id":\#(id),"result":{"done":""}}"#
    let filler = String(repeating: "x", count: total - shell.utf8.count)
    let encoded = #"{"id":\#(id),"result":{"done":"\#(filler)"}}"#
    let input = #"{ "id": \#(id), "result": { "done": "\#(filler)" } }"#
    return (input, encoded)
}

@Test func aReEncodedLineOfExactlyTheCapPassesAndOneByteMoreIsRefusedWithItsId() async throws {
    let app = try makeApp()
    defer { app.listener.stop() }
    let run = RelayRun(directory: app.dir)
    run.send(helloJSON())
    let exact = frame(id: 41, encodedBytes: BrowserWire.maxLineBytes)
    let over = frame(id: 42, encodedBytes: BrowserWire.maxLineBytes + 1)
    expect(exact.input.utf8.count > exact.encoded.utf8.count, "boundary: the input is padded, only the re-encoding counts")
    run.send(exact.input)
    run.send(over.input)
    run.send(#"{"id":43,"result":{"done":"ok"}}"#)
    guard let connection = await app.connection() else { expect(false, "boundary: connected"); return }
    let lines = await app.lines(connection, count: 3)
    expectEq(lines.count, 3, "boundary: hello, the exact-cap frame and the small one")
    expectEq(lines.dropFirst().first, exact.encoded, "boundary: the cap-sized frame arrives whole")
    expect(!lines.contains { $0.contains("\"id\":42") }, "boundary: the frame one byte over never reaches the app")
    run.closeStdin()
    expectEq(await run.exitCode(), 0, "boundary: the relay keeps going after the refusal")
    let reply = parsedObject(run.stdoutFrames().frames.first ?? "")
    expectEq(reply["id"] as? Int, 42, "boundary: the refusal names the frame")
    expectEq((reply["error"] as? [String: Any])?["code"] as? String, BridgeCode.frameTooLarge, "boundary: frame_too_large")
}

// MARK: - bounded shutdown

final class SendCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }

    /// True once the count stopped moving for `quiet` after it had started,
    /// polled with an overall cap; false if it never stalled before the cap
    /// (all sends completed, so nothing was parked).
    func stalls(quiet: TimeInterval = 0.25, cap: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(cap)
        var last = -1
        var since = Date()
        while Date() < deadline {
            let now = count
            if now >= 60 { return false }
            if now != last {
                last = now
                since = Date()
            } else if last > 0, Date().timeIntervalSince(since) >= quiet {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }
}


/// A stdout nobody drains parks the socket pump in a blocking write. Closing
/// stdin must still end the relay in bounded time: Chrome would otherwise be
/// left with a zombie host that holds the app's single browser slot.
@Test func aStdoutThatNeverDrainsCannotHoldTheRelayOpenAfterStdinCloses() async throws {
    let app = try makeApp()
    defer { app.listener.stop() }
    let run = RelayRun(directory: app.dir)
    run.send(helloJSON())
    guard let connection = await app.connection() else { expect(false, "join: connected"); return }
    _ = await app.lines(connection, count: 1)
    let filler = #"{"id":1,"result":{"done":"\#(String(repeating: "y", count: 8000))"}}"#
    // Off-thread: once every buffer between here and the pipe is full, send itself blocks.
    let sent = SendCounter()
    DispatchQueue.global().async {
        for _ in 0 ..< 60 {
            connection.send(line: filler)
            sent.increment()
        }
    }
    // The pump being parked in a write is not observable from outside; the sender stalling is its consequence.
    expect(await sent.stalls(), "join: the sender stalled, so the relay is parked writing to the undrained stdout")
    run.closeStdin()
    let code = await run.exitCode(timeout: 6)
    expectEq(code, 0, "join: the relay returns within the bounded wait")
    // Releases the parked writer so the test leaves no thread behind.
    do { try run.stdout.fileHandleForReading.close() } catch { expect(false, "join: close failed \(error)") }
}
