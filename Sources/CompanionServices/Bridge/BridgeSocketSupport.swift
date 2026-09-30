import Darwin
import Foundation

/// POSIX pieces `BridgeListener` shares with any future socket server, kept
/// apart so the listener stays readable.
enum BridgeSocket {
    static func bind(fd: Int32, path: String) throws {
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

    /// Client side, for the relay. Nil means nothing is listening (the app is
    /// not running, or the path is stale).
    static func connect(path: String) -> Int32? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw.copyBytes(from: pathBytes) }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let connected = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0, suppressSigpipe(on: fd) else {
            Darwin.close(fd)
            return nil
        }
        return fd
    }

    static func peerIsSameUser(_ fd: Int32) -> Bool {
        var euid: uid_t = 0
        var egid: gid_t = 0
        guard Darwin.getpeereid(fd, &euid, &egid) == 0 else { return false }
        return euid == getuid()
    }

    /// Per-fd because the process-wide disposition belongs to the app, not
    /// to this file. macOS answers EINVAL when the peer already hung up, so
    /// false means "nobody left to talk to": the caller drops the fd instead
    /// of writing to it, which would raise the very signal this prevents.
    static func suppressSigpipe(on fd: Int32) -> Bool {
        var on: Int32 = 1
        return Darwin.setsockopt(
            fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0
    }

    /// What `suppressSigpipe` set, read back from the kernel.
    static func sigpipeIsSuppressed(on fd: Int32) -> Bool {
        var value: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard Darwin.getsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, &length) == 0 else { return false }
        return value != 0
    }

    static func generateToken() -> String {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        for _ in 0 ..< 32 { bytes.append(UInt8.random(in: 0 ... 255, using: &generator)) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
