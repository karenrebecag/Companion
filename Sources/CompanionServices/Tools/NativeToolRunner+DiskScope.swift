import CompanionCore
import Foundation

// The file tools reach the whole disk (docs/DECISIONS.md, 2026-10-16). Two
// things can still say no: the protected list in `PathValidator`, and macOS
// itself (TCC) on folders like Mail or Messages.

extension NativeToolRunner {
    /// A refusal the model can act on: it names the cause instead of a work
    /// folder that no longer bounds these tools.
    func outsideZone(_ path: String, resolved: Bool = false) -> ToolResult {
        if pathValidator.wholeDisk {
            let place = resolved ? "\(path) resolves to" : "\(path) is"
            return ToolResult(
                ok: false,
                output: ContractError.deniedPath(
                    "\(place) a protected location: system folders, Keychain, SSH and cloud "
                        + "credentials, and Companion's own data are never opened").wire)
        }
        return ToolResult(
            ok: false,
            output: resolved ? "Resolved path outside working directory" : "Path outside working directory")
    }

    /// TCC answers EPERM where a plain permission bit answers EACCES, so only
    /// EPERM means "the user has to grant Full Disk Access"; telling them to
    /// when a chmod is the cause would send them to the wrong switch.
    static func fullDiskAccessFailure(_ error: Error) -> ToolResult? {
        var current: NSError? = error as NSError
        while let next = current {
            if next.domain == NSPOSIXErrorDomain, next.code == Int(EPERM) {
                return ToolResult(
                    ok: false,
                    output: BridgeCode.fullDiskAccessRequired + ": " + BridgeMessages.fullDiskAccessRequired)
            }
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }
}
