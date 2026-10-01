import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// docs/research/bridge-sigpipe.md, option F: the delegated CLI's stdin is a
// plain pipe and the app never ignores SIGPIPE (AppKit leaves it at SIG_DFL).
// A CLI that died between jobs made the next turn's write kill the whole app,
// while ClaudeCodeExecutor.attempt expects that write to throw and retries.

extension SigpipeSensitive {
    @Test func aTurnWrittenToADelegateThatAlreadyExitedThrowsInsteadOfSignalling() async throws {
        try await withSigpipeCounter {
            try await expectTheControlRaisesOneSigpipe()
            let launcher = RealProcessLauncher()
            guard let handle = await launcher.launch(executable: "/usr/bin/true", arguments: [], cwd: nil) else {
                expect(false, "the delegate launched")
                return
            }
            // isRunning reaps with waitpid, so false means the kernel already
            // closed the child's end of stdin; stdout's EOF alone does not
            // order that close, and an unbounded read would hang the suite.
            let deadline = Date().addingTimeInterval(5)
            while handle.isRunning, Date() < deadline {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            expect(!handle.isRunning, "the delegate exited")
            var threw = false
            do {
                try await handle.sendLine("the next turn")
            } catch ProcessError.writeFailed {
                threw = true
            }
            await handle.terminate()
            expect(threw, "the write fails with the error the executor retries on")
            expect(await stayedBelow(sigpipes: 2), "and raises no SIGPIPE, which would kill the app")
        }
    }
}
