import CompanionCore
import Foundation

/// Which realtime ear a session opens: Scribe when the ElevenLabs key is set,
/// else OpenAI's transcription (kept until the realtime removal), else none.
/// Resolved on every session start, so a key pasted into Settings applies
/// without a restart.
package enum RealtimeEarChoice: Equatable, Sendable {
    case scribe
    case openAI
    case unavailable

    static func resolve(elevenLabsKey: String?, openAIKey: String?) -> RealtimeEarChoice {
        if hasKey(elevenLabsKey) { return .scribe }
        if hasKey(openAIKey) { return .openAI }
        return .unavailable
    }

    private static func hasKey(_ raw: String?) -> Bool {
        !(raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

/// The one ear `VoiceSession` holds. Each backend's streams are single
/// consumer, so each is drained once for the app's lifetime and relayed only
/// while that backend is the current choice. The session keeps its ear for
/// its whole life, which is why the choice cannot be a constructor argument.
package final class RealtimeEarSelector: SegmentingTranscriber, @unchecked Sendable {
    private let elevenLabsKey: @Sendable () -> String?
    private let openAIKey: @Sendable () -> String?
    private let scribe: ScribeTranscriber
    private let openAI: OpenAITranscriber
    private let lock = NSLock()
    private var choice: RealtimeEarChoice = .unavailable
    private let box = AudioStreamBox<String>()
    private let turnBox = AudioStreamBox<EarTurnEvent>()

    package init(
        elevenLabsKey: @escaping @Sendable () -> String?,
        openAIKey: @escaping @Sendable () -> String?,
        turnDetection: @escaping @Sendable () -> TurnDetection
    ) {
        self.elevenLabsKey = elevenLabsKey
        self.openAIKey = openAIKey
        scribe = ScribeTranscriber(keyProvider: elevenLabsKey)
        openAI = OpenAITranscriber(keyProvider: openAIKey, turnDetection: turnDetection)
        relayForever(scribe, as: .scribe)
        relayForever(openAI, as: .openAI)
    }

    package var partials: AsyncStream<String> { box.stream }

    package var turnEvents: AsyncStream<EarTurnEvent> { turnBox.stream }

    package var currentText: String {
        switch lock.withLock({ choice }) {
        case .scribe: scribe.currentText
        case .openAI: openAI.currentText
        case .unavailable: ""
        }
    }

    package var isAuthorized: Bool {
        RealtimeEarChoice.resolve(
            elevenLabsKey: elevenLabsKey(), openAIKey: openAIKey()) != .unavailable
    }

    package func requestAuthorization() async -> Bool { isAuthorized }

    package func start(localeIdentifier: String) async throws {
        let picked = RealtimeEarChoice.resolve(
            elevenLabsKey: elevenLabsKey(), openAIKey: openAIKey())
        lock.withLock { choice = picked }
        if picked != .scribe { _ = await scribe.stop() }
        if picked != .openAI { _ = await openAI.stop() }
        switch picked {
        case .scribe: try await scribe.start(localeIdentifier: localeIdentifier)
        case .openAI: try await openAI.start(localeIdentifier: localeIdentifier)
        case .unavailable: throw VoiceTransportError.unreachable
        }
    }

    package func append(_ frame: MicFrame) async {
        switch lock.withLock({ choice }) {
        case .scribe: await scribe.append(frame)
        case .openAI: await openAI.append(frame)
        case .unavailable: return
        }
    }

    package func stop() async -> String {
        let current = lock.withLock { () -> RealtimeEarChoice in
            let old = choice
            choice = .unavailable
            return old
        }
        switch current {
        case .scribe: return await scribe.stop()
        case .openAI: return await openAI.stop()
        case .unavailable: return ""
        }
    }

    private func relayForever<B: SegmentingTranscriber>(_ backend: B, as owner: RealtimeEarChoice) {
        Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await text in backend.partials {
                        self?.relayPartial(text, from: owner)
                    }
                }
                group.addTask { [weak self] in
                    for await event in backend.turnEvents {
                        self?.relayTurn(event, from: owner)
                    }
                }
            }
        }
    }

    private func relayPartial(_ text: String, from owner: RealtimeEarChoice) {
        guard lock.withLock({ choice == owner }) else { return }
        box.yield(text)
    }

    private func relayTurn(_ event: EarTurnEvent, from owner: RealtimeEarChoice) {
        guard lock.withLock({ choice == owner }) else { return }
        turnBox.yield(event)
    }
}
