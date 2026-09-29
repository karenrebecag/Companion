import CompanionCore
import Darwin
import Foundation

/// Wave 17 (§9-1). The transport: a Unix-domain socket, POSIX not `NWListener`
/// — the 30-minute spike (§3b) found `NWListener` rejects `.unix` endpoints
/// outright (`POSIXErrorCode 22`, on creating the listener, not on `bind`).
/// The accept loop and each connection's read loop run on their own
/// `Thread`, never an actor: a blocking `read`/`accept` on an actor's
/// executor would starve every other task on it.
public final class BridgeListener: @unchecked Sendable {
    private let directory: URL
    private let onConnection: @Sendable (BridgeConnection) -> Void
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private var activeConnection: BridgeConnection?
    private var socketPath = ""
    private var tokenPath = ""
    private var _token = ""

    public init(directory: URL, onConnection: @escaping @Sendable (BridgeConnection) -> Void) {
        self.directory = directory
        self.onConnection = onConnection
    }

    public var token: String {
        lock.lock(); defer { lock.unlock() }
        return _token
    }

    /// §9-2: the directory (`Companion/bridge/`) is 0700 before the `bind`
    /// so it excludes other users on its own; the socket gets 0600 right
    /// after `listen`, and the token file is created with 0600 already set,
    /// never chmod'd after the fact.
    public func start() throws {
        try prepareDirectory()
        let socketURL = directory.appendingPathComponent("bridge.sock")
        let tokenURL = directory.appendingPathComponent("bridge.token")
        removeStaleSocket(at: socketURL)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeListenerError.systemCall("socket", errno) }

        do {
            try bind(fd: fd, path: socketURL.path)
            guard Darwin.listen(fd, 4) == 0 else {
                throw BridgeListenerError.systemCall("listen", errno)
            }
            guard Darwin.chmod(socketURL.path, 0o600) == 0 else {
                throw BridgeListenerError.systemCall("chmod", errno)
            }
        } catch {
            Darwin.close(fd)
            throw error
        }

        let tokenString = Self.generateToken()
        guard FileManager.default.createFile(
            atPath: tokenURL.path, contents: Data(tokenString.utf8),
            attributes: [.posixPermissions: 0o600])
        else {
            Darwin.close(fd)
            throw BridgeListenerError.tokenWrite
        }

        lock.lock()
        listenFD = fd
        _token = tokenString
        socketPath = socketURL.path
        tokenPath = tokenURL.path
        running = true
        lock.unlock()

        Log.bridge("listening")

        let thread = Thread { [weak self] in self?.acceptLoop(fd: fd) }
        thread.name = "bridge-accept"
        thread.start()
    }

    /// Closes the listening socket (unblocking a thread parked in `accept`),
    /// closes the active connection if any, and removes both files so a
    /// stale socket never outlives the process that owned it.
    public func stop() {
        lock.lock()
        running = false
        let fd = listenFD
        listenFD = -1
        let connection = activeConnection
        activeConnection = nil
        let sPath = socketPath
        let tPath = tokenPath
        socketPath = ""
        tokenPath = ""
        lock.unlock()

        if fd >= 0 {
            // `shutdown` before `close`: closing alone can leave the accept
            // thread parked on the old fd number until another connection
            // arrives (BSD sockets do not always wake other threads on close).
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        connection?.close()
        removeIfPresent(sPath)
        removeIfPresent(tPath)
    }

    // MARK: - accept loop (its own thread)

    private func acceptLoop(fd: Int32) {
        while isRunning() {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else {
                if isRunning() { continue }
                return
            }
            guard peerIsSameUser(clientFD) else {
                Log.bridge("rejected peer uid")
                Darwin.close(clientFD)
                continue
            }
            if hasActiveConnection() {
                sendBusy(to: clientFD)
                Darwin.close(clientFD)
                continue
            }
            let connection = BridgeConnection(fd: clientFD)
            connection.onClosed = { [weak self, weak connection] in
                if let connection { self?.clearActiveConnection(connection) }
            }
            setActiveConnection(connection)
            onConnection(connection)
        }
    }

    private func peerIsSameUser(_ fd: Int32) -> Bool {
        var euid: uid_t = 0
        var egid: gid_t = 0
        guard Darwin.getpeereid(fd, &euid, &egid) == 0 else { return false }
        return euid == getuid()
    }

    private func sendBusy(to fd: Int32) {
        let body = BridgeErrorBody(code: BridgeCode.busy, message: "another client is connected")
        let bytes = Array(BridgeCodec.encode(.error(id: nil, body)).utf8) + [0x0A]
        _ = bytes.withUnsafeBufferPointer { ptr in Darwin.write(fd, ptr.baseAddress, ptr.count) }
    }

    // MARK: - lock-guarded state

    private func isRunning() -> Bool {
        lock.lock(); defer { lock.unlock() }; return running
    }

    private func hasActiveConnection() -> Bool {
        lock.lock(); defer { lock.unlock() }; return activeConnection != nil
    }

    private func setActiveConnection(_ connection: BridgeConnection) {
        lock.lock(); activeConnection = connection; lock.unlock()
    }

    /// Only the connection that owns the slot may free it: a late close of
    /// an earlier one must not evict the connection that replaced it.
    private func clearActiveConnection(_ connection: BridgeConnection) {
        lock.lock()
        if activeConnection === connection { activeConnection = nil }
        lock.unlock()
    }

    // MARK: - filesystem

    private func prepareDirectory() throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } else {
            try fm.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
    }

    private func removeStaleSocket(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.bridge("could not remove stale socket")
        }
    }

    private func removeIfPresent(_ path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            Log.bridge("stop: could not remove a bridge file")
        }
    }

    private func bind(fd: Int32, path: String) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw BridgeListenerError.pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw.copyBytes(from: pathBytes) }
        let bound = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw BridgeListenerError.systemCall("bind", errno) }
    }

    private static func generateToken() -> String {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        for _ in 0 ..< 32 { bytes.append(UInt8.random(in: 0 ... 255, using: &generator)) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public enum BridgeListenerError: Error, Sendable, Equatable {
    case pathTooLong
    case tokenWrite
    case systemCall(String, Int32)
}

/// One accepted client connection: a lock-guarded fd exposing whole lines in
/// (`lines`, one per `\n`) and whole lines out (`send`). The read loop runs
/// on its own thread; `AsyncStream`'s continuation is how it hands data back
/// to Swift concurrency without an actor ever blocking on `read`.
public final class BridgeConnection: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false
    private let continuation: AsyncStream<String>.Continuation
    public let lines: AsyncStream<String>
    /// Set by `BridgeListener` before handing the connection to
    /// `onConnection`, so it can free the "one active connection" slot.
    var onClosed: (@Sendable () -> Void)?
    private var slotHeld = false
    private var slotFreed = false

    init(fd: Int32) {
        self.fd = fd
        var pendingContinuation: AsyncStream<String>.Continuation?
        self.lines = AsyncStream<String> { continuation in pendingContinuation = continuation }
        self.continuation = pendingContinuation!
        let thread = Thread { [weak self] in self?.readLoop() }
        thread.name = "bridge-connection"
        thread.start()
    }

    /// Appends the line terminator and writes the whole line, retrying on a
    /// partial write (a blocking socket should not see `EAGAIN`, but the
    /// retry costs nothing and protects against a future non-blocking fd).
    public func send(line: String) {
        guard !isClosed() else { return }
        _ = writeAll(Data((line + "\n").utf8))
    }

    public func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let freeSlot = takeSlotRelease()
        lock.unlock()
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        continuation.finish()
        if freeSlot { onClosed?() }
    }

    /// Wave 20c D5 (M1): the session takes the slot's release into its own
    /// hands, so the listener cannot accept a replacement while the previous
    /// connection's authorization is still standing. Opt-in: a connection
    /// nobody serves frees the slot the moment it closes, as before.
    func holdSlotUntilServed() {
        lock.lock(); defer { lock.unlock() }
        if !slotFreed { slotHeld = true }
    }

    /// Called once the session has reset its state for this connection.
    func releaseSlot() {
        lock.lock()
        slotHeld = false
        let freeSlot = takeSlotRelease()
        lock.unlock()
        if freeSlot { onClosed?() }
    }

    /// Under `lock`. True exactly once: when the connection is closed and
    /// nobody is holding the slot.
    private func takeSlotRelease() -> Bool {
        guard closed, !slotHeld, !slotFreed else { return false }
        slotFreed = true
        return true
    }

    /// M4 (security review 2026-09-28): lets `BridgeSession` check, after
    /// an `await` on a parked sheet, whether the peer it would reply to is
    /// even still there before acting on its answer.
    public var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }; return !closed
    }

    private func isClosed() -> Bool {
        lock.lock(); defer { lock.unlock() }; return closed
    }

    private func readLoop() {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !isClosed() {
            let n = chunk.withUnsafeMutableBytes { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress, ptr.count)
            }
            guard n > 0 else {
                close()
                return
            }
            buffer.append(contentsOf: chunk[0 ..< n])
            if !drainLines(from: &buffer) { return }
        }
    }

    /// Yields every complete line in `buffer`; a partial line already past
    /// the limit closes the connection even before its `\n` arrives.
    private func drainLines(from buffer: inout Data) -> Bool {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            let consumed = buffer.distance(from: buffer.startIndex, to: newline) + 1
            guard lineData.count <= BridgeCodec.maxLineBytes else {
                sendFrameTooLarge()
                close()
                return false
            }
            if let line = String(data: lineData, encoding: .utf8) {
                continuation.yield(line)
            } else {
                // Security review 2026-09-28 (MEDIUM): silently dropping
                // this line left the shim waiting on that request's id
                // forever. An id-less error, same as `frameTooLarge`, but
                // the connection stays open — one bad line is not fatal.
                sendBadFrame()
            }
            buffer.removeFirst(consumed)
        }
        guard buffer.count <= BridgeCodec.maxLineBytes else {
            sendFrameTooLarge()
            close()
            return false
        }
        return true
    }

    private func sendFrameTooLarge() {
        let body = BridgeErrorBody(
            code: BridgeCode.frameTooLarge,
            message: "line exceeds \(BridgeCodec.maxLineBytes) bytes")
        send(line: BridgeCodec.encode(.error(id: nil, body)))
    }

    private func sendBadFrame() {
        let body = BridgeErrorBody(code: BridgeCode.badFrame, message: "line is not valid UTF-8")
        send(line: BridgeCodec.encode(.error(id: nil, body)))
    }

    private func writeAll(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let sent = bytes[offset...].withUnsafeBufferPointer { ptr -> Int in
                Darwin.write(fd, ptr.baseAddress, ptr.count)
            }
            if sent > 0 {
                offset += sent
            } else if sent < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                continue
            } else {
                return false
            }
        }
        return true
    }
}
