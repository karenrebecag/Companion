import Darwin
import Foundation

/// File-descriptor plumbing for `BrowserHostRelay`, apart so the relay reads
/// as protocol and not as syscalls.
enum RelayIO {
    /// Writes everything or reports failure; a dead reader is `false`, never
    /// a signal (the relay ignores SIGPIPE, the sockets set SO_NOSIGPIPE).
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let sent = bytes[offset...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            if sent > 0 {
                offset += sent
            } else if sent < 0, errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// `F_SETNOSIGPIPE` is the per-fd form of the same protection and, unlike
    /// `SO_NOSIGPIPE`, also works on the pipe stdout usually is.
    static func suppressSigpipe(on fd: Int32) {
        if Darwin.fcntl(fd, F_SETNOSIGPIPE, 1) != 0 {
            log("could not protect the output fd from SIGPIPE errno=\(errno)")
        }
    }

    enum Wait { case readable, woken }

    /// Blocks until `fd` has data (or hangs up) or `wake` fires, so a thread
    /// parked on stdin can be released when the other direction finishes.
    static func waitReadable(_ fd: Int32, wake: Int32) -> Wait {
        var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                   pollfd(fd: wake, events: Int16(POLLIN), revents: 0)]
        while true {
            let ready = Darwin.poll(&fds, 2, -1)
            if ready < 0 {
                if errno == EINTR { continue }
                return .woken
            }
            if fds[1].revents != 0 { return .woken }
            return .readable
        }
    }

    /// EINTR is retried; anything else negative is returned as is.
    static func read(_ fd: Int32, into chunk: inout [UInt8]) -> Int {
        while true {
            let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            return n
        }
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data("companion-host: \(message)\n".utf8))
    }
}
