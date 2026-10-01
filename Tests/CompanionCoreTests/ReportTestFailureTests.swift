import CompanionTestKit
import Foundation
import Testing

// scripts/report-test-failure.sh explains a failed `swift test` that its tail
// does not: swift test exits 1 even when the test process dies by a signal,
// and SwiftPM prints that signal on stderr ahead of the buffered test output;
// docs/research/gate4-reporte-sin-resumen.md.

private let reportScript = Conformance.repoRoot().map {
    $0.appendingPathComponent("scripts/report-test-failure.sh").path
} ?? ""

private func report(rc: Int32, output: String) throws -> String {
    let root = try scriptTempRoot("report")
    defer { removeScriptTemp(root) }
    let file = root.appendingPathComponent("out.txt")
    try output.write(to: file, atomically: true, encoding: .utf8)
    let result = try runProcess("/bin/bash", [reportScript, "\(rc)", file.path],
                                env: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
    try #require(result.status == 0, "the report never fails the gate itself: \(result.output)")
    return result.output
}

// The shape of CI run 36903280273: the log stops at a started test.
private let diedMidTest = """
    ◇ Test run started.
    ◇ Test alphaTests() started.
    ✔ Test alphaTests() passed after 0.001 seconds.
    ➜ Test diagramSnapshots() skipped.
    ◇ Suite BridgeSuite started.
    ◇ Test bridgeListenerTests() started.
    """

@Test func reportNamesTheTestThatNeverFinished() throws {
    let out = try report(rc: 1, output: diedMidTest)
    expect(out.contains("rc=1"), "rc is always printed: \(out)")
    expect(out.contains("murio sin resumen"), "no summary means the process died: \(out)")
    expect(out.contains("SIGKILL, SIGTERM, SIGINT o un exit()"), "no signal line names the silent causes: \(out)")
    expect(out.contains("sin cierre: bridgeListenerTests()"), "the open test is named: \(out)")
    expect(!out.contains("sin cierre: alphaTests()"), "a finished test is not: \(out)")
    expect(!out.contains("BridgeSuite"), "suites are not tests: \(out)")
    expect(!out.contains("sin cierre: run"), "the run's own start line is not a test: \(out)")
    // A real skipped test prints only its skipped line, never a start.
    expect(!out.contains("diagramSnapshots"), "a skipped test is not open: \(out)")
}

@Test func reportFindsTheSignalLineFarAboveTheTail() throws {
    let line = "error: Process '/x/swiftpm-testing-helper' exited with unexpected signal code 6"
    let out = try report(rc: 1, output: line + "\n" + diedMidTest)
    expect(out.contains("SIGABRT") && out.contains(line), "the stderr signal line is found and named: \(out)")
    expect(!out.contains("SIGKILL, SIGTERM, SIGINT o un exit()"), "with a signal line, no guessing: \(out)")
}

@Test func reportNamesTheSignalThatKilledSwiftTestItself() throws {
    let out = try report(rc: 134, output: diedMidTest)
    expect(out.contains("rc=134") && out.contains("SIGABRT") && out.contains("truncada"),
           "rc over 128 is a signal and the output may be cut: \(out)")
}

@Test func reportLeavesAnOrdinaryFailureAlone() throws {
    let out = try report(rc: 1, output: """
        ◇ Test betaTests() started.
        ✘ Test betaTests() recorded an issue at B.swift:3:5: Expectation failed
        ✘ Test betaTests() failed after 0.100 seconds with 1 issue.
        ✘ Test run with 1 test in 0 suites failed after 0.200 seconds with 1 issue.
        """)
    expect(out.contains("rc=1"), "rc is always printed: \(out)")
    expect(!out.contains("murio") && !out.contains("sin cierre") && !out.contains("SIG"),
           "a finished run with a failure is not a crash: \(out)")
}

@Test func reportClosesAParameterizedTest() throws {
    let out = try report(rc: 1, output: """
        ◇ Test p(x:) started.
        ◇ Test case passing 1 argument x → 1 to p(x:) started.
        ◇ Test case passing 1 argument x → 2 to p(x:) started.
        ✔ Test p(x:) with 3 test cases passed after 0.010 seconds.
        ◇ Test q() started.
        """)
    expect(out.contains("sin cierre: q()") && !out.contains("sin cierre: p(x:)"),
           "the test-case count between name and verb still closes the test: \(out)")
    // Seen in a real 1643-test log: a case announces its start and never its end.
    expect(!out.contains("sin cierre: case passing"), "per-case start lines are not open tests: \(out)")
}

@Test func reportRefusesAMissingOutputFile() throws {
    let result = try runProcess("/bin/bash", [reportScript, "1", "/nonexistent/out.txt"],
                                env: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
    expect(result.status != 0, "a missing output file is a usage error, not a quiet report: \(result.output)")
}
