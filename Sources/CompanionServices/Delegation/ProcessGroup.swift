import CompanionCore
import Foundation

public struct ShellOutcome: Sendable {
    /// nil when the group was killed rather than allowed to exit.
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    public var pid: pid_t
    /// True when nothing ran: the concurrency ceiling was full. Distinct from
    /// a failure, because the command never got its chance.
    public var refusedByCap: Bool

    public init(
        exitCode: Int32?, stdout: String, stderr: String,
        timedOut: Bool, pid: pid_t, refusedByCap: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.pid = pid
        self.refusedByCap = refusedByCap
    }
}

/// Runs a command in a process group of its own so that terminating it
/// terminates its DESCENDANTS too.
///
/// Why not `Foundation.Process`: a process it spawns inherits our process
/// group, so signalling that group would signal Companion itself. Killing only
/// the direct child leaves grandchildren behind for launchd to adopt, which is
/// how a machine ends up with a week of stray daemons. macOS has no
/// `PR_SET_PDEATHSIG`, so the group is the mechanism, and reaching it needs
/// `posix_spawn` with `POSIX_SPAWN_SETPGROUP`.
public enum ProcessGroupRunner: Sendable {
    /// How long SIGTERM gets to work before SIGKILL. Short on purpose: this
    /// only runs after the command already overstayed its timeout.
    static let graceSeconds: TimeInterval = 0.25

    public static func run(
        executable: String,
        arguments: [String],
        cwd: String?,
        timeout: TimeInterval,
        registry: ProcessRegistry = .shared
    ) async -> ShellOutcome {
        guard registry.reserve() else {
            return ShellOutcome(
                exitCode: nil, stdout: "",
                stderr: "Too many commands running at once; try again in a moment.",
                timedOut: false, pid: 0, refusedByCap: true)
        }
        let out = Pipe()
        let err = Pipe()

        let pid: pid_t
        do {
            pid = try spawn(
                executable: executable, arguments: arguments, cwd: cwd,
                stdout: out.fileHandleForWriting.fileDescriptor,
                stderr: err.fileHandleForWriting.fileDescriptor)
        } catch {
            registry.release()
            return ShellOutcome(
                exitCode: nil, stdout: "",
                stderr: "Failed to execute command: \(error)",
                timedOut: false, pid: 0)
        }
        registry.commit(pid)
        // The child owns the write ends now. Holding them open here would mean
        // never seeing EOF, which reads exactly like a hung command.
        closeWriteEnd(out, label: "stdout")
        closeWriteEnd(err, label: "stderr")

        // Drained WHILE the command runs, never after: a pipe holds ~64 KB and
        // a child that fills it blocks on write forever. Reading only after
        // waiting turned every large output into a false timeout.
        async let stdoutText = drain(out.fileHandleForReading)
        async let stderrText = drain(err.fileHandleForReading)

        let status = await wait(for: pid, timeout: timeout)
        if status == nil { terminateGroup(pid) }
        registry.forget(pid)

        let stdout = await stdoutText
        let stderr = await stderrText
        return ShellOutcome(
            exitCode: status, stdout: stdout, stderr: stderr,
            timedOut: status == nil, pid: pid)
    }

    // MARK: - spawn

    enum SpawnError: Error { case failed(Int32) }

    static func spawn(
        executable: String,
        arguments: [String],
        cwd: String?,
        stdout: Int32,
        stderr: Int32,
        stdin: Int32? = nil
    ) throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // pgroup 0 = the child becomes the leader of a brand new group, so its
        // pid IS the group id and killpg(pid) reaches everything it starts.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdout, 1)
        posix_spawn_file_actions_adddup2(&actions, stderr, 2)
        if let stdin { posix_spawn_file_actions_adddup2(&actions, stdin, 0) }
        if let cwd {
            posix_spawn_file_actions_addchdir_np(&actions, cwd)
        }

        let argv: [UnsafeMutablePointer<CChar>?] =
            ([executable] + arguments).map { strdup($0) } + [nil]
        defer { for arg in argv where arg != nil { free(arg) } }

        var pid: pid_t = 0
        let code = posix_spawn(&pid, executable, &actions, &attr, argv, environ)
        guard code == 0 else { throw SpawnError.failed(code) }
        return pid
    }

    // MARK: - wait and kill

    /// Returns the exit code, or nil if the timeout ran out first. Polls in a
    /// detached task: `waitpid` blocks a thread, and the cooperative pool is
    /// not the place to park one for a whole timeout.
    static func wait(for pid: pid_t, timeout: TimeInterval) async -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                // WIFEXITED / WEXITSTATUS, spelled out: the macros are C.
                if status & 0x7F == 0 { return (status >> 8) & 0xFF }
                return nil
            }
            if result < 0 { return nil }
            do {
                try await Task.sleep(nanoseconds: 5_000_000)
            } catch {
                return nil
            }
        }
        return nil
    }

    /// SIGTERM to the whole group, a short grace, then SIGKILL — and only then
    /// reap. A lone SIGTERM is a request: a child that traps it keeps running
    /// and nobody notices.
    static func terminateGroup(_ pid: pid_t) {
        killpg(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(graceSeconds)
        while Date() < deadline {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid {
                killpg(pid, SIGKILL)  // sweep any descendant it left behind
                return
            }
            usleep(10_000)
        }
        killpg(pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }

    /// Swallowing errors is banned in Services for good reason, and there is
    /// nothing to propagate here: the child already owns the descriptor, so a
    /// failure is worth a log line and nothing else.
    static func closeWriteEnd(_ pipe: Pipe, label: String) {
        do {
            try pipe.fileHandleForWriting.close()
        } catch {
            Log.app("process: could not close \(label) write end")
        }
    }

    private static func drain(_ handle: FileHandle) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                continuation.resume(
                    returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}

/// A long-lived child in its own process group, with stdin wired.
///
/// Foundation's `Process` is enough plumbing for one command; it is not enough
/// for a specialist session, which can outlive several turns and can start
/// helpers of its own. Those helpers are the ones that end up adopted by
/// launchd when only the direct child gets signalled.
public final class GroupProcess: @unchecked Sendable {
    public let pid: pid_t
    public let stdin: Pipe
    public let stdout: Pipe

    private let registry: ProcessRegistry
    private let lock = NSLock()
    private var dead = false

    init(pid: pid_t, stdin: Pipe, stdout: Pipe, registry: ProcessRegistry) {
        self.pid = pid
        self.stdin = stdin
        self.stdout = stdout
        self.registry = registry
    }

    /// Reaps as it asks: an exited child stays a zombie until someone collects
    /// it, and a zombie still answers `kill(pid, 0)`, so asking that alone
    /// would report a dead process as running forever.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        if dead { return false }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == 0 { return true }
        dead = true
        registry.forget(pid)
        return false
    }

    public func terminate() {
        lock.lock()
        let alreadyDead = dead
        dead = true
        lock.unlock()
        if !alreadyDead {
            ProcessGroupRunner.terminateGroup(pid)
        }
        registry.forget(pid)
    }
}

extension ProcessGroupRunner {
    /// Spawns a group with stdin attached, for sessions that stay open.
    /// Returns nil when the concurrency ceiling is full — the caller must say
    /// so rather than pretend the launch merely failed.
    public static func spawnSession(
        executable: String,
        arguments: [String],
        cwd: String?,
        registry: ProcessRegistry = .shared
    ) -> GroupProcess? {
        guard registry.reserve() else {
            Log.app("process: refused \(executable), concurrency cap reached")
            return nil
        }
        let stdin = Pipe()
        let stdout = Pipe()
        let pid: pid_t
        do {
            pid = try spawn(
                executable: executable, arguments: arguments, cwd: cwd,
                stdout: stdout.fileHandleForWriting.fileDescriptor,
                stderr: FileHandle.nullDevice.fileDescriptor,
                stdin: stdin.fileHandleForReading.fileDescriptor)
        } catch {
            registry.release()
            Log.app("process: launching \(executable) failed")
            return nil
        }
        registry.commit(pid)
        // The child owns these ends now; keeping them open here would hide EOF.
        closeWriteEnd(stdout, label: "stdout")
        closeReadEnd(stdin, label: "stdin")
        return GroupProcess(
            pid: pid, stdin: stdin, stdout: stdout, registry: registry)
    }

    static func closeReadEnd(_ pipe: Pipe, label: String) {
        do {
            try pipe.fileHandleForReading.close()
        } catch {
            Log.app("process: could not close \(label) read end")
        }
    }
}
