import CompanionCore
import CompanionServices
import Darwin
import Foundation
import Testing

// Wave 18-2 (§5, X1, X2, X7, X11). The relay is the process Chrome launches:
// native frames on stdio, JSONL on the app's socket. Real sockets and pipes.

let extensionID = "gaipfdnbliibnfchgcnamnjpfgkilnll"
let pinnedOrigin = "chrome-extension://\(extensionID)/"

func nativeFrame(_ json: String) -> Data {
    do {
        return try NativeFrameEncoder.encode(Data(json.utf8))
    } catch {
        return Data()
    }
}

func helloJSON(id: Int = 1, token: String? = nil) -> String {
    let tokenPart = token.map { #","token":"\#($0)""# } ?? ""
    return #"{"id":\#(id),"method":"hello","params":{"extension":"\#(extensionID)","browser":"comet","version":"0.1.0","protocol":1\#(tokenPart)}}"#
}

struct App {
    let dir: URL
    let listener: BridgeListener
    let accepted: Box<BridgeConnection>

    /// Everything the relay wrote on the socket, in order.
    func lines(_ connection: BridgeConnection, count: Int, timeout: TimeInterval = 3) async -> [String] {
        await withTaskGroup(of: [String].self) { group in
            group.addTask {
                var out: [String] = []
                for await line in connection.lines {
                    out.append(line)
                    if out.count == count { break }
                }
                return out
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }
    }

    func connection(timeout: TimeInterval = 3) async -> BridgeConnection? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = accepted.get() { return found }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return accepted.get()
    }
}

/// Answers "did the relay ever connect?" without a sleep. Accepts are
/// sequential, so once a probe client is greeted every earlier connection is
/// already in `connections`: the count is final at that moment.
final class ConnectionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [BridgeConnection] = []
    func add(_ connection: BridgeConnection) { lock.withLock { all.append(connection) } }
    var count: Int { lock.withLock { all.count } }
}

extension App {
    /// Connects a probe client and waits for the greeting the app sends to
    /// every connection; returns how many connections the app saw before the probe.
    func connectionsBeforeAProbe(_ log: ConnectionLog) throws -> Int {
        let probe = try PosixTestClient(path: dir.appendingPathComponent("browser.sock").path)
        defer { probe.close() }
        // A busy answer means a live connection already held the slot, and the probe never reached the log.
        let served = probe.readLine() == "hi"
        return log.count - (served ? 1 : 0)
    }
}

func makeGreetingApp(log: ConnectionLog) throws -> App {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rly-\(UUID().uuidString.prefix(8))")
    let accepted = Box<BridgeConnection>()
    let listener = BridgeListener(
        directory: dir, socketName: "browser.sock", tokenName: "browser.token"
    ) { connection in
        accepted.set(connection)
        log.add(connection)
        connection.send(line: "hi")
    }
    try listener.start()
    return App(dir: dir, listener: listener, accepted: accepted)
}

func makeApp() throws -> App {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rly-\(UUID().uuidString.prefix(8))")
    let accepted = Box<BridgeConnection>()
    let listener = BridgeListener(
        directory: dir, socketName: "browser.sock", tokenName: "browser.token"
    ) { accepted.set($0) }
    try listener.start()
    return App(dir: dir, listener: listener, accepted: accepted)
}

/// One relay run on its own thread, with pipes standing in for Chrome's stdio.
final class RelayRun: @unchecked Sendable {
    let stdin = Pipe()
    let stdout = Pipe()
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var code: Int32?

    init(origin: String = pinnedOrigin, directory: URL, ignoreSIGPIPE: Bool = false) {
        let input = stdin.fileHandleForReading
        let output = stdout.fileHandleForWriting
        let thread = Thread { [self] in
            let result = BrowserHostRelay.run(
                origin: origin, directory: directory, input: input, output: output,
                // SIG_IGN is process-wide and inherited by children: leaking it
                // would change what every other test's subprocesses see, so
                // only the one test that covers the flag turns it on (and restores it).
                ignoreSIGPIPE: ignoreSIGPIPE)
            lock.withLock { code = result }
            done.signal()
        }
        thread.start()
    }

    func send(_ json: String) { write(nativeFrame(json)) }

    func write(_ data: Data) {
        do { try stdin.fileHandleForWriting.write(contentsOf: data) } catch {}
    }

    func closeStdin() {
        do { try stdin.fileHandleForWriting.close() } catch {}
    }

    /// nil when the relay is still running at the deadline.
    func exitCode(timeout: TimeInterval = 3) async -> Int32? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if self.done.wait(timeout: .now() + timeout) == .timedOut {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: self.lock.withLock { self.code })
                }
            }
        }
    }

    /// Reads stdout while the relay is still running, until `count` whole
    /// frames arrived or the deadline passes (poll, so a silent relay cannot hang the test).
    func liveFrames(count: Int, timeout: TimeInterval = 3) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let fd = self.stdout.fileHandleForReading.fileDescriptor
                var decoder = NativeFrameDecoder()
                var frames: [String] = []
                var chunk = [UInt8](repeating: 0, count: 4096)
                let deadline = Date().addingTimeInterval(timeout)
                while frames.count < count, Date() < deadline {
                    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    guard Darwin.poll(&pfd, 1, 100) > 0 else { continue }
                    let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                    guard n > 0 else { break }
                    for result in decoder.push(Data(chunk[0 ..< n])) {
                        if case .success(let body) = result { frames.append(String(decoding: body, as: UTF8.self)) }
                    }
                }
                continuation.resume(returning: frames)
            }
        }
    }

    /// Only after the relay returned: closes our copy of the write end so the
    /// read sees EOF, then decodes everything the relay put on stdout.
    func stdoutFrames() -> (frames: [String], clean: Bool) {
        do { try stdout.fileHandleForWriting.close() } catch {}
        let bytes: Data
        do { bytes = try stdout.fileHandleForReading.readToEnd() ?? Data() } catch { return ([], false) }
        var decoder = NativeFrameDecoder()
        var frames: [String] = []
        for result in decoder.push(bytes) {
            if case .success(let body) = result { frames.append(String(decoding: body, as: UTF8.self)) }
        }
        return (frames, decoder.finish() == nil)
    }
}

private func object(_ line: String) -> [String: Any] {
    guard let parsed = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return [:] }
    return parsed
}

extension SigpipeSensitive {
    @Test func theRelayInjectsTheTokenIntoTheHelloAndTheExtensionNeverSuppliesIt() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(helloJSON(token: "evil-token-from-the-extension"))
        guard let connection = await app.connection() else { expect(false, "inject: relay connected"); return }
        let lines = await app.lines(connection, count: 1)
        expectEq(lines.count, 1, "inject: one line reached the app")
        let params = object(lines.first ?? "")["params"] as? [String: Any]
        expectEq(params?["token"] as? String, app.listener.token, "inject: the file's token, not the extension's")
        expectEq(object(lines.first ?? "")["method"] as? String, "hello", "inject: still a hello")
        expect(!(lines.first ?? "").contains("evil-token"), "inject: the extension's value is gone")
        run.closeStdin()
        expectEq(await run.exitCode(), 0, "inject: stdin EOF exits cleanly")
    }

    @Test func laterFramesAreForwardedWithoutATokenAsOneLineEach() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(helloJSON())
        // Valid JSON with raw newlines must not split into two socket lines.
        run.send("{\"id\":2,\n \"result\":{\"tabs\":[]}}")
        guard let connection = await app.connection() else { expect(false, "forward: relay connected"); return }
        let lines = await app.lines(connection, count: 2)
        expectEq(lines.count, 2, "forward: hello plus one frame")
        expectEq(lines.last, #"{"id":2,"result":{"tabs":[]}}"#, "forward: one line, no token")
        run.closeStdin()
        _ = await run.exitCode()
    }

    @Test func aFirstFrameThatIsNotHelloIsRejectedAndNeverForwarded() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(#"{"id":9,"result":{"done":"clicked"}}"#)
        let code = await run.exitCode()
        expect(code != nil && code != 0, "not hello: relay exits non-zero")
        let out = run.stdoutFrames()
        expectEq(out.frames.count, 1, "not hello: one error frame back to the extension")
        expect(out.frames.first?.contains("bad_frame") == true, "not hello: bad_frame")
        expectEq(object(out.frames.first ?? "")["id"] as? Int, 9, "not hello: keeps the frame's id")
        // The relay is gone, so its connection ends and the stream finishes: no waiting for silence.
        if let connection = await app.connection() {
            expectEq(await app.lines(connection, count: 10), [], "not hello: nothing reached the app")
        }
    }

    @Test func aLineOverTheSocketCapIsRefusedWithItsIdAndNotForwarded() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(helloJSON())
        let big = String(repeating: "x", count: BrowserWire.maxLineBytes + 1)
        run.send(#"{"id":42,"result":{"done":"\#(big)"}}"#)
        run.send(#"{"id":43,"result":{"done":"ok"}}"#)
        guard let connection = await app.connection() else { expect(false, "cap: relay connected"); return }
        let lines = await app.lines(connection, count: 2)
        expectEq(lines.count, 2, "cap: hello and the small frame arrive")
        expect(!lines.contains { $0.contains("\"id\":42") }, "cap: the oversized frame never reaches the app")
        run.closeStdin()
        expectEq(await run.exitCode(), 0, "cap: the relay keeps running after refusing one frame")
        let out = run.stdoutFrames()
        expectEq(out.frames.count, 1, "cap: exactly one reply on stdout")
        let reply = object(out.frames.first ?? "")
        expectEq(reply["id"] as? Int, 42, "cap: the reply carries the frame's id")
        expectEq((reply["error"] as? [String: Any])?["code"] as? String, BridgeCode.frameTooLarge, "cap: frame_too_large")
    }

    @Test func aMissingTokenFileExitsNonZeroWithoutTouchingTheSocket() async throws {
        let log = ConnectionLog()
        let app = try makeGreetingApp(log: log)
        defer { app.listener.stop() }
        try FileManager.default.removeItem(at: app.dir.appendingPathComponent("browser.token"))
        let run = RelayRun(directory: app.dir)
        let code = await run.exitCode()
        expect(code != nil && code != 0, "no token: non-zero exit")
        expectEq(try app.connectionsBeforeAProbe(log), 0, "no token: the socket was never connected")
        expectEq(run.stdoutFrames().frames, [], "no token: nothing on stdout")
    }

    @Test func anOriginThatIsNotPinnedExitsNonZeroWithoutTouchingTheSocket() async throws {
        let log = ConnectionLog()
        let app = try makeGreetingApp(log: log)
        defer { app.listener.stop() }
        let run = RelayRun(origin: "chrome-extension://someoneelse/", directory: app.dir)
        let code = await run.exitCode()
        expect(code != nil && code != 0, "origin: non-zero exit")
        expectEq(try app.connectionsBeforeAProbe(log), 0, "origin: the socket was never connected")
        expect(BrowserPolicy.launch(arguments: ["companion", "chrome-extension://someoneelse/"]) == .rejected,
               "origin: the launch decision for a stranger is .rejected")
        expect(BrowserHostRelay.rejectedExitCode != 0, "origin: main exits non-zero on .rejected")
    }

    @Test func anEmptyOriginExitsRejectedWithoutTouchingTheSocket() async throws {
        let log = ConnectionLog()
        let app = try makeGreetingApp(log: log)
        defer { app.listener.stop() }
        let run = RelayRun(origin: "", directory: app.dir)
        let code = await run.exitCode()
        expectEq(code, BrowserHostRelay.rejectedExitCode, "empty origin: rejected exit code")
        expectEq(try app.connectionsBeforeAProbe(log), 0, "empty origin: the socket was never connected")
    }

    @Test func aTruncatedNativeFrameAtEOFExitsNonZeroWithoutHanging() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(helloJSON())
        run.write(Data([0x20, 0x00, 0x00, 0x00]) + Data("{\"id\":".utf8))
        run.closeStdin()
        let code = await run.exitCode()
        expect(code != nil && code != 0, "truncated: non-zero exit, not a hang")
        expect(run.stdoutFrames().clean, "truncated: stdout holds only whole frames")
    }

    @Test func anOversizeNativePrefixIsRefusedAndTheRelayStops() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(helloJSON())
        var length = UInt32(BrowserWire.maxNativeBytes + 1).littleEndian
        run.write(Data(bytes: &length, count: 4))
        let code = await run.exitCode()
        expect(code != nil && code != 0, "1 MB cap: non-zero exit")
        let out = run.stdoutFrames()
        expect(out.frames.first?.contains(BridgeCode.frameTooLarge) == true, "1 MB cap: frame_too_large to the extension")
    }

    @Test func socketLinesBecomeNativeFramesAndNothingElseReachesStdout() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(helloJSON())
        guard let connection = await app.connection() else { expect(false, "out: relay connected"); return }
        _ = await app.lines(connection, count: 1)
        let call = #"{"id":7,"method":"call","params":{"arguments":{"tab":12},"name":"browser_read"}}"#
        connection.send(line: #"{"id":1,"result":{"ok":true}}"#)
        connection.send(line: call)
        let frames = await run.liveFrames(count: 2)
        expectEq(frames.count, 2, "out: two frames")
        expectEq(frames.last, call, "out: the call arrives intact")
        run.closeStdin()
        _ = await run.exitCode()
        expect(run.stdoutFrames().clean, "out: every byte on stdout belongs to a whole native frame")
    }

    @Test func theAppClosingTheSocketEndsTheRelayCleanly() async throws {
        let app = try makeApp()
        defer { app.listener.stop() }
        let run = RelayRun(directory: app.dir)
        run.send(helloJSON())
        guard let connection = await app.connection() else { expect(false, "app close: relay connected"); return }
        _ = await app.lines(connection, count: 1)
        connection.close()
        expectEq(await run.exitCode(), 0, "app close: exit 0")
        run.closeStdin()
    }
}
