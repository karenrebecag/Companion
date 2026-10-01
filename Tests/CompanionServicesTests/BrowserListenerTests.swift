import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Darwin
import Foundation
import Testing

// Wave 18-2 (X11). The listener serves a second socket for the browser relay
// and must survive a peer that Chrome killed mid-write.

/// Tests that install a SIGPIPE handler, or make the relay ignore the signal,
/// share one serial suite: the disposition is process-wide (a signal(2) call
/// in one test replaces the handler another test is counting with), so
/// running two of them in parallel would make both results meaningless.
@Suite(.serialized) struct SigpipeSensitive {}

nonisolated(unsafe) var sigpipeCount = 0

private func countSigpipe(_ signal: Int32) { sigpipeCount += 1 }

private func shortTempDirectory() -> URL {
    // sun_path caps at 104 bytes and the sandbox $TMPDIR is already long.
    FileManager.default.temporaryDirectory
        .appendingPathComponent("brl-\(UUID().uuidString.prefix(8))")
}

private func mode(_ url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777
}

private func connection(from box: Box<BridgeConnection>) async -> BridgeConnection? {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if let found = box.get() { return found }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return box.get()
}

/// Anything that reads `sigpipeCount` shares the process-wide handler, so
/// each test resets it under the serial suite.
func withSigpipeCounter<T>(_ body: () async throws -> T) async rethrows -> T {
    let previous = signal(SIGPIPE, countSigpipe)
    defer { signal(SIGPIPE, previous) }
    sigpipeCount = 0
    return try await body()
}

/// Polls, because the handler can run on any thread after the write returns.
func waitForSigpipes(atLeast n: Int, timeout: TimeInterval = 2) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while sigpipeCount < n, Date() < deadline { try? await Task.sleep(nanoseconds: 2_000_000) }
    return sigpipeCount >= n
}

/// A negative observation: the count must not reach `n` during the window,
/// which is many times the latency the control just measured.
func stayedBelow(sigpipes n: Int, window: TimeInterval = 0.15) async -> Bool {
    let deadline = Date().addingTimeInterval(window)
    while Date() < deadline {
        if sigpipeCount >= n { return false }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return sigpipeCount < n
}

func socketPair() throws -> (Int32, Int32) {
    var fds: [Int32] = [0, 0]
    guard Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw PosixTestClientError.socket }
    return (fds[0], fds[1])
}

private func writeByte(_ fd: Int32) -> (result: Int, error: Int32) {
    var byte: UInt8 = 0x41
    let result = Darwin.write(fd, &byte, 1)
    return (result, errno)
}

extension SigpipeSensitive {
    /// The control and the protected write share one harness: if the control
    /// did not raise the signal, the protected half would pass for nothing.
    @Test func suppressSigpipeTurnsAWriteToAClosedPeerIntoEPIPE() async throws {
        try await withSigpipeCounter {
            let (control, controlPeer) = try socketPair()
            Darwin.close(controlPeer)
            _ = writeByte(control)
            Darwin.close(control)
            // The kernel posts the signal to the process, so a handler may run on another thread a moment later.
            expect(await waitForSigpipes(atLeast: 1), "control: a fd without the option raises SIGPIPE (the harness can fail)")
            expectEq(sigpipeCount, 1, "control: exactly one")

            let (protected, peer) = try socketPair()
            expect(BridgeSocket.suppressSigpipe(on: protected), "protected: the option applies to a live socket")
            Darwin.close(peer)
            let outcome = writeByte(protected)
            Darwin.close(protected)
            expectEq(outcome.result, -1, "protected: the write fails")
            expectEq(outcome.error, EPIPE, "protected: with EPIPE")
            expect(await stayedBelow(sigpipes: 2), "protected: and no further signal after the control's one")
        }
    }

    /// Wave 17 regression (X11): every fd the listener hands out carries the
    /// option, so a relay that Chrome killed cannot take the app down on the
    /// next send. The kernel-side option is what is read back, because a peer
    /// that hangs up is seen by the read loop, which closes the fd before a
    /// send can be raced against it.
    @Test func everyAcceptedConnectionIsProtectedFromSigpipe() async throws {
        let dir = shortTempDirectory()
        let box = Box<BridgeConnection>()
        let listener = BridgeListener(directory: dir) { box.set($0) }
        try listener.start()
        defer { listener.stop() }

        let client = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
        defer { client.close() }
        guard let connection = await connection(from: box) else { expect(false, "x11: accepted"); return }
        expect(connection.suppressesSigpipe, "x11: SO_NOSIGPIPE is set on the accepted fd")

        // The control: a fd that never went through the listener has it off.
        let (raw, peer) = try socketPair()
        defer { Darwin.close(raw); Darwin.close(peer) }
        expect(!BridgeSocket.sigpipeIsSuppressed(on: raw), "x11 control: the read-back can report false")
    }

    /// Sends racing a hangup, end to end: whatever the read loop has or has
    /// not noticed yet, the app survives and reports no open connection after.
    @Test func sendingWhileThePeerHangsUpNeverRaisesSigpipe() async throws {
        let dir = shortTempDirectory()
        let box = Box<BridgeConnection>()
        let listener = BridgeListener(directory: dir) { box.set($0) }
        try listener.start()
        defer { listener.stop() }

        try await withSigpipeCounter {
            let client = try PosixTestClient(path: dir.appendingPathComponent("bridge.sock").path)
            guard let connection = await connection(from: box) else { expect(false, "hangup: accepted"); return }
            client.close()
            for _ in 0 ..< 500 { connection.send(line: "{\"id\":1}") }
            expect(await stayedBelow(sigpipes: 1), "hangup: no SIGPIPE while sending to a peer that just left")
        }
    }

    /// A peer that hangs up before accept: `suppressSigpipe` refuses (EINVAL),
    /// which is what tells the accept loop to drop the fd instead of writing to it.
    @Test func aPeerThatLeftBeforeAcceptIsRefusedByTheSigpipeSetup() async throws {
        let dir = shortTempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("raw.sock").path
        let server = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try BridgeSocket.bind(fd: server, path: path)
        expectEq(Darwin.listen(server, 4), 0, "pre-accept: listening")
        defer { Darwin.close(server); try? FileManager.default.removeItem(at: dir) }

        let client = try PosixTestClient(path: path)
        client.close()
        let accepted = Darwin.accept(server, nil, nil)
        expect(accepted >= 0, "pre-accept: the kernel still hands over the dead connection")
        defer { Darwin.close(accepted) }
        expect(!BridgeSocket.suppressSigpipe(on: accepted), "pre-accept: setup fails, so the caller drops the fd")
    }

    /// The listener end of the same path: clients that vanish around accept,
    /// the busy reply included, never take the process down or wedge the slot.
    @Test func clientsThatVanishAroundAcceptNeitherRaiseSigpipeNorWedgeTheListener() async throws {
        let dir = shortTempDirectory()
        let box = Box<BridgeConnection>()
        let listener = BridgeListener(directory: dir) { box.set($0) }
        try listener.start()
        defer { listener.stop() }
        let socketPath = dir.appendingPathComponent("bridge.sock").path

        try await withSigpipeCounter {
            let holder = try PosixTestClient(path: socketPath)
            let first = await connection(from: box)
            expect(first != nil, "vanish: the first client holds the slot")
            // Paced: the listen backlog is 4 and an overflow is ECONNREFUSED, not the case under test.
            for _ in 0 ..< 10 {
                try PosixTestClient(path: socketPath).close()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            holder.close()
            expect(await stayedBelow(sigpipes: 1), "vanish: SO_NOSIGPIPE turns the signal into EPIPE")

            let deadline = Date().addingTimeInterval(3)
            var served = false
            while Date() < deadline, !served {
                let next = try PosixTestClient(path: socketPath)
                defer { next.close() }
                try await Task.sleep(nanoseconds: 50_000_000)
                if let current = box.get(), current !== first { served = current.isOpen }
            }
            expect(served, "vanish: the listener still serves a live client afterwards")
        }
    }
}

@Test func customNamesCreateBrowserFilesWith0600InA0700Directory() throws {
    let dir = shortTempDirectory()
    let listener = BridgeListener(
        directory: dir, socketName: "browser.sock", tokenName: "browser.token") { _ in }
    try listener.start()
    defer { listener.stop() }

    expectEq(try mode(dir), 0o700, "names: directory 0700")
    expectEq(try mode(dir.appendingPathComponent("browser.sock")), 0o600, "names: socket 0600")
    let tokenURL = dir.appendingPathComponent("browser.token")
    expectEq(try mode(tokenURL), 0o600, "names: token file 0600")
    expectEq(try String(contentsOf: tokenURL, encoding: .utf8), listener.token, "names: token matches")
    expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("bridge.sock").path),
           "names: the wave 17 socket is not created")

    listener.stop()
    expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("browser.sock").path),
           "names: stop removes the browser socket")
    expect(!FileManager.default.fileExists(atPath: tokenURL.path), "names: stop removes the browser token")
}

@Test func twoListenersShareADirectoryWithoutClashing() throws {
    let dir = shortTempDirectory()
    let bridge = BridgeListener(directory: dir) { _ in }
    let browser = BridgeListener(directory: dir, socketName: "browser.sock", tokenName: "browser.token") { _ in }
    try bridge.start()
    try browser.start()
    defer { bridge.stop(); browser.stop() }
    expect(bridge.token != browser.token, "two listeners: independent tokens")
    expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bridge.sock").path)
        && FileManager.default.fileExists(atPath: dir.appendingPathComponent("browser.sock").path),
        "two listeners: both sockets exist")
}
