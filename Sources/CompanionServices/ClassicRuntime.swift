import CompanionCore
import Foundation

/// Port protocols (Transcriber, SpeechSynthesizer, ChatProvider, ConversationPresenting)
/// may not conform to Sendable but are safely isolated by exclusive access in VoiceSession.
final class ClassicRuntime: @unchecked Sendable {
    let transcriber: any Transcriber
    let synthesizer: any SpeechSynthesizer
    let chat: any ChatProvider
    let thread: any ConversationPresenting

    init(
        transcriber: any Transcriber,
        synthesizer: any SpeechSynthesizer,
        chat: any ChatProvider,
        thread: any ConversationPresenting
    ) {
        self.transcriber = transcriber
        self.synthesizer = synthesizer
        self.chat = chat
        self.thread = thread
    }

    func requestListen(
        mic: any MicCapturing,
        apply: @escaping @Sendable (TurnEvent) async -> Void
    ) async {
        let granted = await mic.requestAccess()
        if !granted {
            await apply(.voiceStartFailed(.micDenied))
            return
        }
        let speech = await transcriber.requestAuthorization()
        if !speech {
            await apply(.voiceStartFailed(.speechEngine))
            return
        }
        do {
            try await mic.start()
        } catch {
            await apply(.voiceStartFailed(.micUnavailable))
            return
        }
        do {
            try await transcriber.start(localeIdentifier: "es-MX")
        } catch {
            await apply(.voiceStartFailed(.speechEngine))
            return
        }
        await apply(.classicListenArmed)
    }

    func stopIO(mic: any MicCapturing) async {
        _ = await transcriber.stop()
        await synthesizer.stop()
        await mic.stop()
    }

    func submit(apply: @escaping @Sendable (TurnEvent) async -> Void) async {
        let heard = await transcriber.stop()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if heard.isEmpty {
            await apply(.utteranceEmpty)
            return
        }
        await thread.appendUser(heard)
        let history = await thread.historyTurns()
        var buf = ""
        var started = false
        do {
            for try await delta in chat.stream(history, tools: []) {
                if Task.isCancelled { return }
                guard case .text(let piece) = delta else { continue }
                if !started && !piece.isEmpty {
                    started = true
                    await apply(.firstSentence)
                }
                buf += piece
                while let cut = SentenceSplitter.takeSentence(buf) {
                    buf = cut.rest
                    await synthesizer.enqueue(cut.sentence)
                }
            }
        } catch {
            Log.app("voice: classic chat failed")
            if !started {
                await apply(.turnFailed(VoiceFailureMapping.failure(for: error)))
                return
            }
        }
        let rest = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty {
            if !started {
                started = true
                await apply(.firstSentence)
            }
            await synthesizer.enqueue(rest)
        }
        await apply(.replyCompleted)
    }

    static func status(_ reason: TurnFailure) -> String {
        switch reason {
        case .micDenied:
            return "No pude usar el micrófono."
        case .micUnavailable:
            return "El micrófono no está disponible."
        case .micSilent:
            return "El micrófono no entregó audio."
        case .notHeard:
            return "No te escuché."
        case .speechEngine:
            return "Me quedé sin voz."
        case .noProviders:
            return "No hay un proveedor de voz disponible."
        case .sessionDropped:
            return "La sesión de voz se cayó."
        case .networkUnavailable:
            return "Sin conexión a internet. Verifica tu red."
        }
    }
}
