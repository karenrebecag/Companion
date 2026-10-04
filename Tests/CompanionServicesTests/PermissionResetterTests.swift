import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore
@testable import CompanionServices

// ON-18. Every process and the terminate are fakes: nothing here runs
// tccutil or open, and nothing quits.

private final class FakeRunner: CommandRunning, @unchecked Sendable {
    let calls = LockedBox<[[String]]>([])
    private let outcome: @Sendable (Int, [String]) throws -> Int32

    init(_ outcome: @escaping @Sendable (Int, [String]) throws -> Int32 = { _, _ in 0 }) {
        self.outcome = outcome
    }

    func run(_ argv: [String]) async throws -> Int32 {
        let index = calls.withLock { calls -> Int in
            calls.append(argv)
            return calls.count - 1
        }
        return try outcome(index, argv)
    }
}

private final class FakeTerminator: SelfTerminating, @unchecked Sendable {
    let count = LockedBox(0)
    func terminate() async { count.value += 1 }
}

private struct Boom: Error {}

private func makeResetter(
    runner: FakeRunner, terminator: FakeTerminator,
    bundleID: String = "com.karen.companion",
    bundlePath: String = "/Applications/Companion.app"
) -> ProcessPermissionResetter {
    ProcessPermissionResetter(
        bundleID: bundleID, bundlePath: bundlePath, pid: 4242,
        runner: runner, terminator: terminator)
}

private func failure(of body: () async throws -> Void) async -> PermissionResetError? {
    do {
        try await body()
        return nil
    } catch {
        return error as? PermissionResetError
    }
}

@Test func permissionResetterRunsEveryResetThenRelaunchesThenTerminates() async throws {
    let runner = FakeRunner()
    let terminator = FakeTerminator()
    try await makeResetter(runner: runner, terminator: terminator).resetAndRelaunch()

    let expected = try PermissionReset.plan(bundleID: "com.karen.companion")
        + [try PermissionReset.relaunch(bundlePath: "/Applications/Companion.app", afterPID: 4242)]
    expectEq(runner.calls.value, expected, "resetter: resets in order, then open -n")
    expectEq(terminator.count.value, 1, "resetter: terminates once")
}

@Test func permissionResetterStopsAtTheFirstFailedResetAndNeverRelaunches() async {
    let runner = FakeRunner { index, _ in index == 1 ? 1 : 0 }
    let terminator = FakeTerminator()
    let error = await failure {
        try await makeResetter(runner: runner, terminator: terminator).resetAndRelaunch()
    }
    expectEq(error, .resetFailed(PermissionResetService.allCases[1]),
             "resetter: names the service that failed")
    expectEq(runner.calls.value.count, 2, "resetter: nothing runs after the failure")
    expect(!runner.calls.value.contains { $0.first == "/usr/bin/open" },
           "resetter: no relaunch after a failed reset")
    expectEq(terminator.count.value, 0, "resetter: no terminate after a failed reset")
}

@Test func permissionResetterTreatsARunnerThrowAsAFailedReset() async {
    let runner = FakeRunner { index, _ in
        if index == 0 { throw Boom() }
        return 0
    }
    let terminator = FakeTerminator()
    let error = await failure {
        try await makeResetter(runner: runner, terminator: terminator).resetAndRelaunch()
    }
    expectEq(error, .resetFailed(PermissionResetService.allCases[0]), "resetter: throw is failure")
    expectEq(runner.calls.value.count, 1, "resetter: stops on throw")
    expectEq(terminator.count.value, 0, "resetter: no terminate on throw")
}

@Test func permissionResetterKeepsTheAppAliveWhenRelaunchFails() async {
    let runner = FakeRunner { _, argv in argv.first == "/usr/bin/open" ? 1 : 0 }
    let terminator = FakeTerminator()
    let error = await failure {
        try await makeResetter(runner: runner, terminator: terminator).resetAndRelaunch()
    }
    expectEq(error, .relaunchFailed, "resetter: relaunch failure is typed")
    expectEq(terminator.count.value, 0, "resetter: never quits without a successor")
}

@Test func permissionResetterRefusesBadInputsBeforeRunningAnything() async {
    let badID = FakeRunner()
    let badIDTerminator = FakeTerminator()
    let idError = await failure {
        try await makeResetter(runner: badID, terminator: badIDTerminator, bundleID: "-x")
            .resetAndRelaunch()
    }
    expectEq(idError, .invalidBundleID, "resetter: bad id refused")
    expectEq(badID.calls.value.count, 0, "resetter: bad id runs nothing")

    // A dev build outside an .app must not wipe grants it cannot relaunch from.
    let badPath = FakeRunner()
    let pathError = await failure {
        try await makeResetter(
            runner: badPath, terminator: FakeTerminator(), bundlePath: "/tmp/companion")
            .resetAndRelaunch()
    }
    expectEq(pathError, .invalidBundlePath, "resetter: bad path refused")
    expectEq(badPath.calls.value.count, 0, "resetter: bad path runs nothing, resets nothing")
}

@Test func permissionResetterFailingTheLastServiceHasRunTheSixBeforeIt() async throws {
    let last = PermissionResetService.allCases.count - 1
    let runner = FakeRunner { index, _ in index == last ? 1 : 0 }
    let terminator = FakeTerminator()
    let error = await failure {
        try await makeResetter(runner: runner, terminator: terminator).resetAndRelaunch()
    }
    expectEq(error, .resetFailed(PermissionResetService.allCases[last]), "resetter: last one named")
    let plan = try PermissionReset.plan(bundleID: "com.karen.companion")
    expectEq(runner.calls.value, plan, "resetter: all seven argv ran, in order, and nothing after")
    expectEq(Array(runner.calls.value.prefix(6)), Array(plan.prefix(6)), "resetter: six before it")
    expect(!runner.calls.value.contains { $0.first == "/usr/bin/open" }, "resetter: no relaunch")
    expectEq(terminator.count.value, 0, "resetter: no terminate")
}

@Test func permissionResetterRunsEverySuccessfulResetBeforeAFailingOpen() async throws {
    let runner = FakeRunner { _, argv in argv.first == "/usr/bin/open" ? 1 : 0 }
    let terminator = FakeTerminator()
    let error = await failure {
        try await makeResetter(runner: runner, terminator: terminator).resetAndRelaunch()
    }
    expectEq(error, .relaunchFailed, "resetter: relaunch failure typed")
    let expected = try PermissionReset.plan(bundleID: "com.karen.companion")
        + [try PermissionReset.relaunch(bundlePath: "/Applications/Companion.app", afterPID: 4242)]
    expectEq(runner.calls.value.count, 8, "resetter: seven resets then open")
    expectEq(runner.calls.value, expected, "resetter: in order, open last")
    expectEq(terminator.count.value, 0, "resetter: still no terminate")
}

// Real processes, but only /usr/bin/true and /usr/bin/false: neither touches
// tccutil or open.
@Test func processCommandRunnerReportsTheExitStatus() async throws {
    let runner = ProcessCommandRunner()
    expectEq(try await runner.run(["/usr/bin/true"]), 0, "runner: true exits 0")
    expectEq(try await runner.run(["/usr/bin/false"]), 1, "runner: false exits 1")
    expectEq(try await runner.run([]), -1, "runner: nothing to run")
    var threw = false
    do { _ = try await runner.run(["/usr/bin/does-not-exist-zzz"]) } catch { threw = true }
    expect(threw, "runner: a missing executable throws")
}

@Test func relaunchStartupReturnsAtOnceWhenThereIsNoFlag() {
    let slept = LockedBox(0)
    RelaunchStartup.awaitPredecessor(
        arguments: ["companion"], ownPID: 1, isAlive: { _ in true }, sleep: { _ in slept.value += 1 })
    expectEq(slept.value, 0, "startup: no flag, no wait")
}

@Test func relaunchStartupWaitsForAPredecessorThatLeaves() {
    let polls = LockedBox(0)
    RelaunchStartup.awaitPredecessor(
        arguments: ["companion", "--relaunch-after", "77"], ownPID: 1,
        isAlive: { pid in
            expectEq(pid, 77, "startup: probes the pid from the flag")
            polls.value += 1
            return polls.value < 3
        }, sleep: { _ in })
    expectEq(polls.value, 3, "startup: polled until gone")
}

@Test func relaunchStartupGivesUpAndLogsWhenThePredecessorStays() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("relaunch-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: url) }
    let slept = LockedBox(0)
    await Log.capturing(to: url) {
        RelaunchStartup.awaitPredecessor(
            arguments: ["companion", "--relaunch-after", "77"], ownPID: 1,
            isAlive: { _ in true }, sleep: { _ in slept.value += 1 })
    }
    expectEq(slept.value, RelaunchHandoff.maxPolls, "startup: bounded by the cap")
    let lines = Log.tail(lines: 5, from: url)
    expect(lines.contains { $0.contains("relaunch: previous instance still running") },
           "startup: the timeout is logged")
}

@Test func processIsAliveSeesItselfAndASpawnedProcessThatExited() throws {
    expect(RelaunchStartup.processIsAlive(ProcessInfo.processInfo.processIdentifier),
           "alive: our own pid")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try child.run()
    child.waitUntilExit()
    expect(!RelaunchStartup.processIsAlive(child.processIdentifier), "alive: reaped child is gone")
}
