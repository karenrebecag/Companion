import CompanionTestKit
import Foundation
import Testing

// scripts/run-tests-watched.sh runs `swift test` for Gate 4. A test that
// waits forever used to hold the CI runner for six hours with an empty log,
// because the output was captured and only printed at the end. The script
// streams the output as it comes and kills the run after a stretch of silence,
// naming what was running.

private let repoRoot = Conformance.repoRoot()
private let watchedScript = repoRoot.map { $0.appendingPathComponent("scripts/run-tests-watched.sh").path } ?? ""
private let systemPath = "/usr/bin:/bin:/usr/sbin:/sbin"

private struct Watched {
    let status: Int32
    let output: String
    let file: String
    let seconds: Double
}

private func watched(idle: String, path: String = systemPath, _ command: String) throws -> Watched {
    let root = try scriptTempRoot("watched")
    defer { removeScriptTemp(root) }
    let file = root.appendingPathComponent("out.txt")
    let start = Date()
    let result = try runProcess("/bin/bash", [watchedScript, idle, file.path, "/bin/bash", "-c", command],
                                env: ["PATH": path])
    let seconds = Date().timeIntervalSince(start)
    let saved = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    return Watched(status: result.status, output: result.output, file: saved, seconds: seconds)
}

private func readPid(_ pidFile: String) throws -> Int32 {
    let text = try String(contentsOfFile: pidFile, encoding: .utf8)
    return try #require(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), "pid file holds a pid: \(text)")
}

/// A killed process can linger a moment as a zombie before launchd reaps it,
/// so death is polled instead of read once.
private func diesSoon(_ pid: Int32) -> Bool {
    for _ in 0..<30 {
        if kill(pid, 0) != 0 { return true }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return false
}

@Test func watchedRunStreamsTheOutputAndKeepsTheExitCode() throws {
    let run = try watched(idle: "5", "echo first; echo second >&2; exit 3")
    expect(run.status == 3, "the command's own exit code comes back: \(run.status) \(run.output)")
    expect(run.output.contains("first") && run.output.contains("second"), "stdout and stderr reach the log: \(run.output)")
    expect(run.file.contains("first") && run.file.contains("second"), "and the file keeps them for the summary: \(run.file)")
    expect(!run.output.contains("colgado"), "a run that ends is not a hang: \(run.output)")
}

@Test func watchedRunKeepsASignalExitAndAMissingCommand() throws {
    let aborted = try watched(idle: "5", "echo last words; kill -ABRT $$")
    expect(aborted.status == 134, "a signal death stays rc 128+n for report-test-failure: \(aborted.status)")
    expect(aborted.output.contains("last words") && aborted.file.contains("last words"),
           "the line printed right before dying is flushed: \(aborted.output)")
    let missing = try watched(idle: "5", "/nonexistent/swift-test")
    expect(missing.status == 127, "a missing command keeps its rc: \(missing.status) \(missing.output)")
    expect(missing.file.contains("No such file"), "and its error lands in the file: \(missing.file)")
}

@Test func watchedRunLetsSteadyOutputRunPastTheIdleLimit() throws {
    // Ticks well under the limit: a healthy run is never killed, whatever the
    // phase between the ticks and the watchdog's one-second poll.
    let run = try watched(idle: "2", "for i in $(seq 1 12); do echo tick $i; sleep 0.5; done")
    expect(run.status == 0, "a run that keeps talking is never killed: \(run.status) \(run.output)")
    expect(run.output.contains("tick 12"), "every line reaches the log: \(run.output)")
}

@Test func watchedRunKillsASilentRunAndNamesTheOpenTest() throws {
    let root = try scriptTempRoot("watched-pid")
    defer { removeScriptTemp(root) }
    let sleeperFile = root.appendingPathComponent("sleeper.pid").path
    let stubbornFile = root.appendingPathComponent("stubborn.pid").path
    // A grandchild like the test helper under swift test, and a great-grandchild
    // that ignores SIGTERM so only the SIGKILL escalation ends it.
    let run = try watched(idle: "2", """
        echo '◇ Test run started.'
        echo '◇ Test alphaTests() started.'
        echo '✔ Test alphaTests() passed after 0.001 seconds.'
        echo '◇ Test stuckTests() started.'
        sleep 20 &
        echo $! > '\(sleeperFile)'
        /bin/bash -c 'trap "" TERM; sleep 21 & echo $! > "\(stubbornFile)"; wait' &
        wait
        """)
    expect(run.status == 124, "a hang has its own exit code: \(run.status) \(run.output)")
    expect(run.seconds < 25, "killed at the idle limit, not when the sleepers end: \(run.seconds)s")
    expect(run.output.contains("colgado"), "the log says it hung: \(run.output)")
    expect(run.output.contains("ultimo test empezado: ◇ Test stuckTests() started."),
           "the diagnosis names the last started test: \(run.output)")
    expect(!run.output.contains("ultimo test empezado: ◇ Test alphaTests()"), "not a finished one: \(run.output)")
    let sleeper = try readPid(sleeperFile)
    let stubborn = try readPid(stubbornFile)
    let rows = run.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    expect(rows.contains { $0.hasPrefix("\(sleeper) ") }, "the tree lists the grandchild: \(run.output)")
    expect(rows.contains { $0.hasPrefix("\(stubborn) ") }, "and the process under it: \(run.output)")
    expect(run.output.contains("Call graph"), "/usr/bin/sample printed a stack of the stuck processes: \(run.output)")
    expect(run.file.contains("stuckTests()"), "the file keeps the output for report-test-failure: \(run.file)")
    expect(diesSoon(sleeper), "the grandchild does not outlive the run")
    expect(diesSoon(stubborn), "a process that ignores SIGTERM does not either")
}

@Test func watchedRunFinishesEvenWhenSampleHangs() throws {
    let root = try scriptTempRoot("watched-stub")
    defer { removeScriptTemp(root) }
    let stub = root.appendingPathComponent("sample")
    try "#!/bin/bash\nsleep 60\n".write(to: stub, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    let run = try watched(idle: "2", path: root.path + ":" + systemPath, "echo '◇ Test stuckTests() started.'; sleep 30")
    expect(run.status == 124, "the hang is still reported: \(run.status) \(run.output)")
    expect(run.seconds < 28, "a stuck sample is cut off instead of stalling the watchdog: \(run.seconds)s")
}

@Test func watchedRunTakesItsProcessesDownWhenInterrupted() throws {
    let root = try scriptTempRoot("watched-int")
    defer { removeScriptTemp(root) }
    let pidFile = root.appendingPathComponent("child.pid").path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [watchedScript, "60", root.appendingPathComponent("out.txt").path,
                         "/bin/bash", "-c", "sleep 20 & echo $! > '\(pidFile)'; wait"]
    process.environment = ["PATH": systemPath]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    for _ in 0..<50 where !FileManager.default.fileExists(atPath: pidFile) {
        Thread.sleep(forTimeInterval: 0.1)
    }
    let child = try readPid(pidFile)
    process.interrupt()
    process.waitUntilExit()
    expect(process.terminationStatus == 130, "Ctrl-C ends the watchdog as an interrupt: \(process.terminationStatus)")
    expect(diesSoon(child), "and swift test under it does not keep running as an orphan")
}

@Test func watchedRunRefusesABadIdleLimit() throws {
    for idle in ["", "0", "5m", "-1"] {
        let run = try watched(idle: idle, "echo never")
        expect(run.status == 2, "idle '\(idle)' is a usage error: \(run.status) \(run.output)")
        expect(!run.output.contains("never"), "the command does not run on a usage error: \(run.output)")
    }
}

@Test func gateFourRunsTheTestsUnderTheWatchdog() throws {
    let gates = try String(contentsOf: try #require(repoRoot).appendingPathComponent("scripts/gates.sh"), encoding: .utf8)
    expect(gates.contains("scripts/run-tests-watched.sh\" \"${GATES_TEST_IDLE_SECONDS:-300}\" \"$test_out_tmp\""),
           "Gate 4 streams swift test through the watchdog with the output file the report reads")
    expect(!gates.contains("$(cd \"$ROOT\" && swift test"),
           "swift test is never captured into a variable again: a hang would show an empty log")
}
