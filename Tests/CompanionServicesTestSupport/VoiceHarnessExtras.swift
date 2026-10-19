import CompanionCore
import CompanionServices
import Foundation

// Session event capture, a mutable config provider and wire-message helpers.

package struct TestReachability: ReachabilityProbing {
    package let online: Bool
    package var isOnline: Bool { get async { online } }

    package init(online: Bool) {
        self.online = online
    }
}

package final class SessionEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [SessionEvent] = []
    package var events: [SessionEvent] { lock.withLock { _events } }

    package init(_ stream: AsyncStream<SessionEvent>) {
        Task { [weak self] in
            for await event in stream { self?.append(event) }
        }
    }

    private func append(_ event: SessionEvent) { lock.withLock { _events.append(event) } }
}

/// Mutable test provider that can simulate preference changes.
package final class TestConfigProvider: ConfigProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _config: Config
    package private(set) var readCount = 0

    package var current: Config {
        lock.withLock {
            readCount += 1
            return _config
        }
    }

    package init(config: Config) {
        self._config = config
    }

    package func updateConfig(_ newConfig: Config) {
        lock.withLock {
            _config = newConfig
        }
    }
}

/// Extend the voice harness factory to accept a provider.
@MainActor package func makeVoiceHarnessWithProvider(_ provider: any ConfigProviding) -> VoiceHarness {
    let transport = ScriptedVoiceTransport()
    transport.autoEvents = [.sessionCreated, .sessionUpdated]
    let mic = ScriptedMic()
    let player = ScriptedPlayer()
    let transcriber = ScriptedTranscriber()
    let synth = ScriptedSynth()
    let chat = ScriptedChat()
    var keys: [SecretKey: String] = [:]
    keys[.openAI] = "sk-test"
    let secrets = ScriptedSecrets(keys)
    let thread = ScriptedThread()
    let clock = TestClock()
    let session = VoiceSession(
        transport: transport,
        mic: mic,
        player: player,
        transcriber: transcriber,
        synthesizer: synth,
        chat: chat,
        secrets: secrets,
        thread: thread,
        configProvider: provider,
        reachability: TestReachability(online: true),
        echoFreeProbe: { false },
        micSilenceTimeout: 10,
        now: { clock.now },
        readyTimeout: harnessReadyTimeout)
    let watch = SnapWatch(session.snapshots)
    return VoiceHarness(
        session: session, transport: transport, mic: mic, player: player,
        transcriber: transcriber, thread: thread, clock: clock, watch: watch,
        synth: synth, chat: chat, secrets: secrets)
}

package func messageType(_ json: String) -> String? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj["type"] as? String
}

package func hasMessage(_ sent: [String], type: String) -> Bool {
    sent.contains { messageType($0) == type }
}

/// Enough voiced frames to pass `HoldAudioBuffer`'s silence gate.
@MainActor package func speak(_ h: VoiceHarness, frames: Int, byte: UInt8 = 0x11) {
    for _ in 0 ..< frames {
        h.mic.yield(MicFrame(pcm16le24k: Data(repeating: byte, count: 640), rms: 0.3))
    }
}

