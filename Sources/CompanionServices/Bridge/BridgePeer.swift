import Darwin
import Foundation

/// Wave 20c D5 (M2c). What the kernel says about the process on the other end
/// of a bridge socket. The `client` name in `hello` is the peer's own claim;
/// this is not, so the approval sheet shows it beside the claim.
///
/// HACK: pid and executable path only; the code signature of the peer is not
/// checked. Upgrade trigger: a shim that ships signed (Developer ID), so the
/// sheet can say "signed by Anthropic" instead of just where the binary lives.
package struct BridgePeer: Sendable, Equatable {
    package let pid: Int32
    package let path: String

    /// Nil when the kernel will not say (a peer that already exited).
    static func of(fd: Int32) -> BridgePeer? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard Darwin.getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else {
            return nil
        }
        return BridgePeer(pid: pid, path: executablePath(of: pid))
    }

    private static func executablePath(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }
}
