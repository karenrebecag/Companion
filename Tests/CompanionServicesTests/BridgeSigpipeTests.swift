import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Darwin
import Foundation
import Testing

// docs/research/bridge-sigpipe.md: CI died with no summary inside the bridge
// suites because the test clients wrote to sockets the server had already
// closed, and nothing turned that SIGPIPE into an EPIPE. The app's accept loop
// was protected; its clients in the tests, and the connection type itself when
// built from a raw socket, were not.

/// The harness can fail: an unprotected write to a peer that left raises
/// exactly one signal, so a protected write that stays below two is a real
/// EPIPE and not a counter that never counts.
func expectTheControlRaisesOneSigpipe() async throws {
    let (control, controlPeer) = try socketPair()
    Darwin.close(controlPeer)
    var byte: UInt8 = 0x41
    _ = Darwin.write(control, &byte, 1)
    Darwin.close(control)
    expect(await waitForSigpipes(atLeast: 1), "control: an unprotected write to a gone peer raises SIGPIPE")
    expectEq(sigpipeCount.load(ordering: .relaxed), 1, "control: exactly one")
}

extension SigpipeSensitive {
    /// The invariant lives in the type, so a constructor that does not go
    /// through the accept loop (a test pair, a future listener) cannot forget it.
    @Test func aConnectionBuiltFromARawSocketIsProtectedFromSigpipe() throws {
        let (server, client) = try socketPair()
        defer { Darwin.close(client) }
        let connection = BridgeConnection(fd: server) { _ in }
        defer { connection.close() }
        expect(connection.suppressesSigpipe, "the connection protects the fd it was handed")
    }

    /// No reader is started, so nothing closes this end before the send
    /// reaches a peer that is already gone: the one ordering the read loop
    /// otherwise hides.
    @Test func aConnectionSendingToAPeerThatLeftRaisesNoSigpipe() async throws {
        try await withSigpipeCounter {
            try await expectTheControlRaisesOneSigpipe()
            let (server, client) = try socketPair()
            let connection = BridgeConnection(fd: server) { _ in }
            Darwin.close(client)
            connection.send(line: "{}")
            connection.close()
            expect(await stayedBelow(sigpipes: 2), "a send to a gone peer is an EPIPE, not a signal")
        }
    }

    /// A peer gone before construction can leave the option unset (macOS
    /// answers EINVAL): the connection must then not write at all.
    @Test func aConnectionWhosePeerLeftBeforeItWasBuiltRaisesNoSigpipe() async throws {
        try await withSigpipeCounter {
            try await expectTheControlRaisesOneSigpipe()
            let (server, client) = try socketPair()
            Darwin.close(client)
            let connection = BridgeConnection(fd: server) { _ in }
            connection.send(line: "{}")
            connection.close()
            expect(await stayedBelow(sigpipes: 2), "no write reaches a peer that left before the connection existed")
        }
    }

    /// The write CI most likely died on: a client that already read `busy`
    /// and saw the listener hang up still sends its hello.
    @Test func aTestClientWritingAfterTheListenerClosedRaisesNoSigpipe() async throws {
        let dir = tempBridgeDirectory()
        let listener = BridgeListener(directory: dir) { _ in }
        try listener.start()
        defer { listener.stop() }
        let path = dir.appendingPathComponent("bridge.sock").path
        let holder = try PosixTestClient(path: path)
        defer { holder.close() }
        try await withSigpipeCounter {
            try await expectTheControlRaisesOneSigpipe()
            let late = try PosixTestClient(path: path)
            defer { late.close() }
            expect(late.readLine()?.contains(BridgeCode.busy) == true, "the slot is taken: busy")
            expect(late.waitForEOF(), "and the listener hung up")
            _ = try? late.send("{}")
            expect(await stayedBelow(sigpipes: 2), "a late test client's write is an EPIPE, not a signal")
        }
    }

    /// The pair's client end is a raw socket the test writes on; the server
    /// end closing must not turn the test's next write into a signal.
    @Test func aBridgePairWritingAfterTheServerClosedRaisesNoSigpipe() async throws {
        try await withSigpipeCounter {
            try await expectTheControlRaisesOneSigpipe()
            let pair = BridgePair()
            pair.connection.close()
            pair.send("{}")
            pair.closeClient()
            expect(await stayedBelow(sigpipes: 2), "the pair's client write is an EPIPE, not a signal")
        }
    }
}
