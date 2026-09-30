import CompanionCore
import Darwin
import Foundation

/// Wave 18-2 (X1, X2, X7, X11). The process Chrome launches as a native host:
/// native frames (uint32 LE + JSON) on stdio, JSONL on `browser.sock`. It
/// holds the only copy of the token the extension never sees, and it is the
/// only writer to stdout, so nothing but frames may ever go there.
package enum BrowserHostRelay {
    /// Distinct from the relay's own failures (1) so a caller can tell an
    /// unrecognised launch from a working one that hit a problem.
    package static let rejectedExitCode: Int32 = 2

    package static func run(
        origin: String, directory: URL,
        input: FileHandle = .standardInput, output: FileHandle = .standardOutput,
        ignoreSIGPIPE: Bool = true
    ) -> Int32 {
        // Chrome closing the pipe mid-write must be an error here, not a
        // signal that ends the process without cleanup. The disposition is
        // process-wide and inherited by children, so a test host that runs
        // other processes passes false and keeps only the per-fd protection.
        if ignoreSIGPIPE { signal(SIGPIPE, SIG_IGN) }
        RelayIO.suppressSigpipe(on: output.fileDescriptor)
        // Checked before the token is read: an unpinned caller, an empty
        // origin included, must not get as far as the secret or the socket.
        guard BrowserPolicy.pinnedOrigins.contains(origin) else {
            RelayIO.log("origin rejected")
            return rejectedExitCode
        }
        guard let token = readToken(directory.appendingPathComponent("browser.token")) else { return 1 }
        guard let socketFD = BridgeSocket.connect(path: directory.appendingPathComponent("browser.sock").path)
        else {
            RelayIO.log("cannot connect to the app")
            return 1
        }
        defer { Darwin.close(socketFD) }
        return RelaySession(token: token, socketFD: socketFD, input: input.fileDescriptor,
                            output: output.fileDescriptor).run()
    }

    private static let maxTokenBytes = 128

    /// The token is the only secret between this process and the app, so the
    /// file is trusted only if it is ours and private: opened without
    /// following a link (a planted symlink could point at any file the user
    /// can read), owned by this uid, no group or world access, and short.
    private static func readToken(_ url: URL) -> String? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else {
            RelayIO.log("token file unreadable")
            return nil
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            RelayIO.log("token file has the wrong owner or permissions")
            return nil
        }
        // One byte past the cap tells "exactly the cap" from "more than the cap".
        var buffer = [UInt8](repeating: 0, count: maxTokenBytes + 1)
        let count = RelayIO.read(fd, into: &buffer)
        guard count > 0, count <= maxTokenBytes else {
            RelayIO.log("token file empty, unreadable or too long")
            return nil
        }
        let token = String(decoding: buffer[0 ..< count], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

/// Two pumps and a verdict. Whichever side ends first records the exit code;
/// `run` then releases the other and joins both, so the fds outlive them.
private final class RelaySession: @unchecked Sendable {
    private static let joinTimeout: DispatchTimeInterval = .seconds(2)

    private let token: String
    private let socketFD: Int32
    private let input: Int32
    private let output: Int32
    private let outputLock = NSLock()
    private let stateLock = NSLock()
    private var code: Int32?
    private let verdict = DispatchSemaphore(value: 0)
    private let exited = DispatchSemaphore(value: 0)
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1

    init(token: String, socketFD: Int32, input: Int32, output: Int32) {
        self.token = token
        self.socketFD = socketFD
        self.input = input
        self.output = output
    }

    func run() -> Int32 {
        var pipeFDs: [Int32] = [0, 0]
        guard Darwin.pipe(&pipeFDs) == 0 else {
            RelayIO.log("cannot create wake pipe")
            return 1
        }
        wakeRead = pipeFDs[0]
        wakeWrite = pipeFDs[1]
        startPump("relay-stdin") { self.pumpStdin() }
        startPump("relay-socket") { self.pumpSocket() }
        verdict.wait()
        Darwin.shutdown(socketFD, SHUT_RDWR)
        _ = RelayIO.writeAll(wakeWrite, Data([1]))
        // Bounded: a pump parked in a write to a stdout Chrome stopped
        // draining cannot be woken by the shutdown or the wake pipe, and an
        // unbounded join would leave a zombie host holding the app's only
        // browser slot. The caller exits the process right after, which
        // reaps the stuck thread.
        let deadline = DispatchTime.now() + Self.joinTimeout
        let joined = exited.wait(timeout: deadline) == .success && exited.wait(timeout: deadline) == .success
        // A stuck pump may still use these fds; closing them under it risks
        // a reused descriptor number, and the process is about to exit.
        if joined {
            Darwin.close(wakeRead)
            Darwin.close(wakeWrite)
        }
        return stateLock.withLock { code ?? 1 }
    }

    private func startPump(_ name: String, _ body: @escaping @Sendable () -> Void) {
        let thread = Thread { [exited] in
            body()
            exited.signal()
        }
        thread.name = name
        thread.start()
    }

    private func finish(_ exitCode: Int32) {
        let first: Bool = stateLock.withLock {
            guard code == nil else { return false }
            code = exitCode
            return true
        }
        if first { verdict.signal() }
    }

    // MARK: - stdin (extension) to socket

    private func pumpStdin() {
        var decoder = NativeFrameDecoder()
        var expectingHello = true
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            guard RelayIO.waitReadable(input, wake: wakeRead) == .readable else { return }
            let n = RelayIO.read(input, into: &chunk)
            if n == 0 {
                if decoder.finish() != nil {
                    RelayIO.log("stdin closed mid-frame")
                    finish(1)
                } else {
                    finish(0)
                }
                return
            }
            guard n > 0 else {
                finish(1)
                return
            }
            for result in decoder.push(Data(chunk[0 ..< n])) {
                switch result {
                case .failure:
                    reply(id: nil, code: BridgeCode.frameTooLarge,
                          message: "Native frame exceeds \(BrowserWire.maxNativeBytes) bytes")
                    finish(1)
                    return
                case .success(let body):
                    guard forward(body, isFirst: expectingHello) else {
                        finish(1)
                        return
                    }
                    expectingHello = false
                }
            }
        }
    }

    /// False means the relay must stop: the first frame was not a usable
    /// hello, or the app is gone. A refused later frame is answered and the
    /// relay carries on.
    private func forward(_ body: Data, isFirst: Bool) -> Bool {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: body)
        } catch {
            reply(id: nil, code: BridgeCode.badFrame, message: "Invalid JSON")
            return !isFirst
        }
        guard var message = parsed as? [String: Any] else {
            reply(id: nil, code: BridgeCode.badFrame, message: "Frame is not an object")
            return !isFirst
        }
        let id = message["id"] as? Int
        if isFirst {
            guard message["method"] as? String == "hello" else {
                reply(id: id, code: BridgeCode.badFrame, message: "The first frame must be hello")
                return false
            }
            // Always overwritten: whatever the extension put there is not
            // the token, and it must not be able to choose one.
            var params = message["params"] as? [String: Any] ?? [:]
            params["token"] = token
            message["params"] = params
        }
        let line: Data
        do {
            line = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
        } catch {
            reply(id: id, code: BridgeCode.badFrame, message: "Frame cannot be re-encoded")
            return !isFirst
        }
        // The app closes the connection on a longer line, so it is refused
        // here, with the id the extension is waiting on.
        guard line.count <= BrowserWire.maxLineBytes else {
            reply(id: id, code: BridgeCode.frameTooLarge, message: "Frame exceeds \(BrowserWire.maxLineBytes) bytes")
            return !isFirst
        }
        guard RelayIO.writeAll(socketFD, line + Data([0x0A])) else {
            finish(0)
            return false
        }
        return true
    }

    // MARK: - socket (app) to stdout

    private func pumpSocket() {
        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = RelayIO.read(socketFD, into: &chunk)
            guard n > 0 else {
                finish(0)
                return
            }
            pending.append(contentsOf: chunk[0 ..< n])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[pending.startIndex ..< newline])
                pending.removeSubrange(pending.startIndex ... newline)
                guard emit(line) else { return }
            }
            if pending.count > BrowserWire.maxNativeBytes {
                RelayIO.log("app line without terminator over the native cap")
                finish(1)
                return
            }
        }
    }

    /// False once stdout is dead: there is no extension left to talk to.
    private func emit(_ line: Data) -> Bool {
        guard !line.isEmpty else { return true }
        let frame: Data
        do {
            frame = try NativeFrameEncoder.encode(line)
        } catch {
            RelayIO.log("app line too large for a native frame, dropped")
            return true
        }
        return write(frame)
    }

    private func reply(id: Int?, code: String, message: String) {
        let line = BrowserCodec.encode(.error(id: id, BridgeErrorBody(code: code, message: message)))
        _ = emit(Data(line.utf8))
    }

    private func write(_ frame: Data) -> Bool {
        let ok = outputLock.withLock { RelayIO.writeAll(output, frame) }
        if !ok { finish(0) }
        return ok
    }
}
