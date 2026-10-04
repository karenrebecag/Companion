import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore

// ON-18. The planner is pure: it only builds argv arrays, so nothing here can
// touch the real privacy database.

@Test func permissionResetPlansExactlyTheServicesCompanionRequests() {
    // Names verified against /usr/bin/tccutil ("kTCCService%s" prefix) and the
    // kTCCService* constants inside tccd. Location is absent on purpose: it is
    // not a TCC service, so tccutil cannot reset it.
    let expected: Set<String> = [
        "Microphone", "SpeechRecognition", "ScreenCapture", "Accessibility",
        "ListenEvent", "AddressBook", "AppleEvents",
    ]
    expectEq(Set(PermissionResetService.allCases.map(\.rawValue)), expected,
             "reset: the exact TCC service set")
    expectEq(PermissionResetService.allCases.count, expected.count,
             "reset: no service twice")
}

@Test func permissionResetPlanIsOnePerServiceNeverAll() throws {
    let plan = try PermissionReset.plan(bundleID: "com.karen.companion")
    expectEq(plan.count, PermissionResetService.allCases.count, "reset: one argv per service")
    for argv in plan {
        expectEq(argv.count, 4, "reset: argv has four elements")
        expectEq(argv[0], "/usr/bin/tccutil", "reset: absolute tccutil")
        expectEq(argv[1], "reset", "reset: reset verb")
        expectEq(argv[3], "com.karen.companion", "reset: bundle id last")
        expect(argv[2] != "All", "reset: never the all-services form")
    }
    expectEq(plan.map { $0[2] }, PermissionResetService.allCases.map(\.rawValue),
             "reset: argv follow the service order")
    expectEq(plan[0], ["/usr/bin/tccutil", "reset", "Microphone", "com.karen.companion"],
             "reset: exact first argv")
}

@Test func permissionResetAcceptsReverseDNSBundleIDs() throws {
    for id in ["com.karen.companion", "com.karen.companion.next", "a.b", "com.my-co.App2"] {
        expectEq(try PermissionReset.plan(bundleID: id).count,
                 PermissionResetService.allCases.count, "reset: accepts \(id)")
    }
}

@Test func permissionResetRejectsMalformedBundleIDs() {
    let bad = [
        "", " ", "com.karen.companion ", " com.karen.companion", "com. karen.x",
        "com.karen\n.x", "-com.karen.companion", "--help", "nodots", ".com.karen",
        "com.karen.", "com..karen", "com.karen.companion; rm -rf /", "com.k$(id).x",
        "com.k`id`.x", "com.k|x.y", "com.k&x.y", "com.k\"x.y", "com.k'x.y",
        "com.k/x.y", "com.k\\x.y", "com.kärén.x", "com.k\u{0}x.y", "com.k*.y",
        String(repeating: "a", count: 300) + ".b",
    ]
    for id in bad {
        do {
            _ = try PermissionReset.plan(bundleID: id)
            expect(false, "reset: should reject \(id.debugDescription)")
        } catch {
            expectEq(error as? PermissionResetError, .invalidBundleID,
                     "reset: typed error for \(id.debugDescription)")
        }
    }
}

@Test func permissionResetRelaunchIsOpenNewInstance() throws {
    expectEq(try PermissionReset.relaunch(bundlePath: "/Applications/Companion.app", afterPID: 4242),
             ["/usr/bin/open", "-n", "/Applications/Companion.app",
              "--args", "--relaunch-after", "4242"],
             "relaunch: exact argv, carrying the pid to wait for")
}

@Test func permissionResetRelaunchRejectsPathsThatAreNotAnAppBundle() {
    for path in ["", "Companion.app", "/Applications/Companion", "-n", "/tmp/x.app\u{0}",
                 "/Users/k/.build/debug/companion", "../Companion.app"] {
        do {
            _ = try PermissionReset.relaunch(bundlePath: path, afterPID: 1)
            expect(false, "relaunch: should reject \(path.debugDescription)")
        } catch {
            expectEq(error as? PermissionResetError, .invalidBundlePath,
                     "relaunch: typed error for \(path.debugDescription)")
        }
    }
}

@Test func permissionResetConfirmationWordFollowsTheLanguage() {
    expectEq(PermissionReset.confirmationWord(for: .es), "RESTABLECER", "word: es")
    expectEq(PermissionReset.confirmationWord(for: .en), "RESET", "word: en")
}

// Decision: the check ignores case and surrounding whitespace. The friction is
// reading and typing the word, not hitting shift; a caps-lock mismatch would
// only punish the person. Anything else (partial, other language) stays locked.
@Test func permissionResetConfirmationIgnoresCaseAndOuterWhitespace() {
    expect(PermissionReset.isConfirmed("RESET", language: .en), "confirm: exact en")
    expect(PermissionReset.isConfirmed("reset", language: .en), "confirm: lowercase en")
    expect(PermissionReset.isConfirmed("  Reset \n", language: .en), "confirm: padded en")
    expect(PermissionReset.isConfirmed("RESTABLECER", language: .es), "confirm: exact es")
    expect(PermissionReset.isConfirmed("restablecer", language: .es), "confirm: lowercase es")
    expect(PermissionReset.isConfirmed("\tRestablecer ", language: .es), "confirm: padded es")
}

@Test func permissionResetConfirmationRejectsEverythingElse() {
    expect(!PermissionReset.isConfirmed("", language: .en), "confirm: empty")
    expect(!PermissionReset.isConfirmed("   ", language: .en), "confirm: blank")
    expect(!PermissionReset.isConfirmed("RES", language: .en), "confirm: prefix")
    expect(!PermissionReset.isConfirmed("RESET!", language: .en), "confirm: suffix")
    expect(!PermissionReset.isConfirmed("RE SET", language: .en), "confirm: inner space")
    expect(!PermissionReset.isConfirmed("RESTABLECER", language: .en), "confirm: es word in en")
    expect(!PermissionReset.isConfirmed("RESET", language: .es), "confirm: en word in es")
    expect(!PermissionReset.isConfirmed("RESETZ", language: .en), "confirm: lookalike")
}

@Test func permissionResetRelaunchRejectsANonPositivePID() {
    for pid: Int32 in [0, -1, Int32.min] {
        do {
            _ = try PermissionReset.relaunch(bundlePath: "/Applications/Companion.app", afterPID: pid)
            expect(false, "relaunch: should reject pid \(pid)")
        } catch {
            expectEq(error as? PermissionResetError, .invalidPID, "relaunch: typed error for pid \(pid)")
        }
    }
}

// The flag can be passed by any process that launches the app, so the parser
// takes only a plain positive pid that is not ours.
@Test func relaunchHandoffParsesOnlyAPlainForeignPID() {
    func parse(_ args: [String]) -> Int32? { RelaunchHandoff.predecessor(in: args, ownPID: 100) }
    expectEq(parse(["companion", "--relaunch-after", "4242"]), 4242, "handoff: valid")
    expectEq(parse(["companion"]), nil, "handoff: flag missing")
    expectEq(parse([]), nil, "handoff: no arguments")
    expectEq(parse(["companion", "--relaunch-after"]), nil, "handoff: flag without value")
    expectEq(parse(["companion", "--relaunch-after", "abc"]), nil, "handoff: non-numeric")
    expectEq(parse(["companion", "--relaunch-after", "12abc"]), nil, "handoff: trailing junk")
    expectEq(parse(["companion", "--relaunch-after", "+5"]), nil, "handoff: signed plus")
    expectEq(parse(["companion", "--relaunch-after", "0"]), nil, "handoff: zero")
    expectEq(parse(["companion", "--relaunch-after", "-7"]), nil, "handoff: negative")
    expectEq(parse(["companion", "--relaunch-after", "100"]), nil, "handoff: own pid")
    expectEq(parse(["companion", "--relaunch-after", "99999999999999999999"]), nil, "handoff: huge")
    expectEq(parse(["companion", "--relaunch-after", ""]), nil, "handoff: empty value")
    expectEq(parse(["companion", "--relaunch-after", "1", "--relaunch-after", "2"]), 1,
             "handoff: the first flag wins")
}

@Test func relaunchHandoffReturnsAtOnceWhenThePredecessorIsGone() {
    let slept = LockedBox(0)
    let outcome = RelaunchHandoff.wait(
        forExitOf: 7, isAlive: { _ in false }, sleep: { _ in slept.value += 1 })
    expectEq(outcome, .exited, "wait: gone is gone")
    expectEq(slept.value, 0, "wait: no sleep when already gone")
}

@Test func relaunchHandoffWaitsWhileThePredecessorLives() {
    let polls = LockedBox(0)
    let slept = LockedBox(0)
    let outcome = RelaunchHandoff.wait(
        forExitOf: 7,
        isAlive: { _ in
            polls.value += 1
            return polls.value <= 3
        },
        sleep: { _ in slept.value += 1 })
    expectEq(outcome, .exited, "wait: ends when the pid goes away")
    expectEq(slept.value, 3, "wait: one sleep per live probe")
}

@Test func relaunchHandoffStopsAtTheCapWhenThePredecessorNeverExits() {
    let slept = LockedBox<[TimeInterval]>([])
    let outcome = RelaunchHandoff.wait(
        forExitOf: 7, isAlive: { _ in true }, sleep: { slept.value.append($0) })
    expectEq(outcome, .timedOut, "wait: gives up instead of hanging")
    expectEq(slept.value.count, RelaunchHandoff.maxPolls, "wait: bounded by maxPolls")
    expect(slept.value.allSatisfy { $0 == RelaunchHandoff.pollInterval }, "wait: fixed interval")
    expect(Double(RelaunchHandoff.maxPolls) * RelaunchHandoff.pollInterval <= 5,
           "wait: the worst case stays a short delay")
}

// What a failed reset leaves behind: everything before it in plan order.
@Test func permissionResetClearedBeforeFollowsPlanOrder() {
    let all = PermissionResetService.allCases
    for (index, service) in all.enumerated() {
        expectEq(PermissionReset.cleared(before: service), Array(all.prefix(index)),
                 "cleared: what ran before \(service)")
    }
    expectEq(PermissionReset.cleared(before: all[0]), [], "cleared: nothing before the first")
    expectEq(PermissionReset.cleared(before: all[all.count - 1]).count, 6,
             "cleared: six before the last")
}
