import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import CoreGraphics
import SwiftUI

/// DM1c-2: N2's own fast/strong model pair is not chosen yet (DM1d or the
/// Settings toggle work). Until then, an `.arbitrate` disposition just falls
/// through to today's model-in-the-loop path instead of guessing a model.
private struct PassThroughArbiter: Arbitrating {
    func arbitrate(
        utterance: String, shortlist: ArbitrationShortlist
    ) async -> (entry: ShortlistEntry, confidence: Double)? { nil }
}

/// The TTS voices and the realtime voice session itself. Split out of
/// `applicationDidFinishLaunching` when CompanionMain crossed the 400-line
/// gate. `self.voice` is set by the caller, which keeps that stored property
/// private to CompanionMain.swift.
struct VoicePipeline {
    let openAIMouth: OpenAITTSClient
    let mouth: MouthRouter
    let voice: VoiceViewModel
}

/// Verbatim from the TTS/decision-gate/VoiceSession section of the old
/// `applicationDidFinishLaunching`.
func makeVoicePipeline(
    environment env: LaunchEnvironment, providers: ChatProviders, jobs: JobInfrastructure,
    sensing: SensingAndModel
) -> VoicePipeline {
    // Wave 15b-4: cached audio is one voice's phonemes, not another's —
    // switching voices in Settings must not play a stale one from disk.
    // Wave 15c-5: `tts-pcm`, not `tts` — the cached bytes went from mp3
    // to raw PCM, a format the new player would misread as noise; a new
    // folder orphans the old cache instead of decoding it wrong.
    let caches = FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Companion/tts-pcm/\(env.config.voice.voice.rawValue)")
    do {
        try FileManager.default.createDirectory(
            at: caches, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    } catch {
        Log.app("could not create tts cache dir")
    }

    // Player joins the mic engine only while Voice Processing is live, so
    // AEC hears the agent; weak keeps the player from owning the mic.
    let mic = MicCapture(echoCancellation: env.config.voice.echoCancellation)
    let player = RealtimePlayer(
        sharedWith: mic, volume: env.config.voice.volume)
    // 15f-7a: ElevenLabs when its key and a voice are set, OpenAI
    // otherwise — decided per sentence, so a key saved in Settings
    // takes effect on the next hold and nothing reads the Keychain here.
    let openAIMouth = OpenAITTSClient(secrets: env.secrets, transport: env.transport, language: env.config.language)
    let mouth = MouthRouter(
        elevenLabs: ElevenLabsTTSClient(
            secrets: env.secrets, transport: env.transport, language: env.config.language,
            voiceID: { env.configProvider.current.elevenLabsVoiceID }),
        openAI: openAIMouth, secrets: env.secrets,
        voiceID: { env.configProvider.current.elevenLabsVoiceID })
    let synthesizer = SpeechSynthesis(
        cache: PhraseCache(directory: caches),
        fetcher: mouth,
        playback: DataSpeechPlayback(),
        fallback: AVSpeechFallback(language: env.config.language),
        voice: env.config.voice.voice)
    // DM1c-2 (wave-dm1-router.md §8): N1 decides locally, in front of the
    // classic hold — off by default (`Config.decision.enabled`). N2's own
    // model pair is DM1d/settings work; a pass-through arbiter just lets
    // an `.arbitrate` disposition fall through to today's path meanwhile.
    // DM1c-4: the only two irreversible ops with an executor — never
    // Companion's own pid/bundle, guarded by `frontmost.lastOtherPID`.
    let systemActions = SystemActionRunner(
        selfBundleID: Bundle.main.bundleIdentifier ?? "",
        frontmostOtherPID: { sensing.frontmost.lastOtherPID })
    let decisionProvider = OllamaDecisionProvider(
        baseURL: URL(string: env.config.decision.ollamaURL) ?? ProviderDescriptor.ollama.baseURL,
        model: env.config.decision.judgeModel)
    let decisionGate = DecisionGate(
        provider: decisionProvider,
        arbiter: PassThroughArbiter(),
        tools: sensing.parentTools,
        system: systemActions,
        world: {
            DecisionWorld(
                apps: sensing.workspaceOpener.runningApplications()
                    + sensing.workspaceOpener.installedApplications(),
                skills: env.skillStore.catalog().map(\.name))
        },
        budget: env.config.decision.budget)
    // 15d perf: the release path reads app names from memory only.
    let installedApps = InstalledAppsCache(load: { sensing.workspaceOpener.installedApplications() })
    installedApps.prewarm()
    // 15e-0: the hold's only ear, on-device. Spelling bias: the owner,
    // the user's own words (16d), then what is running (most likely
    // named), then what is installed.
    let ear = AnalyzerTranscriber(
        engine: AppleSpeechEngine(),
        vocabulary: {
            [env.configProvider.current.ownerFirstName]
                + VocabularyPreference.words
                + sensing.workspaceOpener.runningApplications()
                + installedApps.names()
        })
    // The model is a one-time ~52 s download; started now so the first
    // hold does not end in "no te oí" waiting for it.
    let earLocale = env.config.language.speechLocaleIdentifier
    Task.detached { await ear.prepare(localeIdentifier: earLocale) }
    let session = VoiceSession(
        transport: RealtimeWSTransport(),
        mic: mic,
        player: player,
        transcriber: ear,
        synthesizer: synthesizer,
        chat: providers.holdChat,
        secrets: env.secrets,
        thread: sensing.model,
        configProvider: env.configProvider,
        jobs: jobs.jobRunner,
        // Realtime hears through OpenAI's live transcription (measured
        // better on mixed-language speech); classic keeps the on-device
        // ear, which needs no key and no network.
        realtimeEar: OpenAITranscriber(
            keyProvider: { try? env.secrets.read(.openAI) ?? nil },
            // The Settings knob drives the server's VAD (9j-1).
            turnDetection: { env.configProvider.current.voice.turnDetection }),
        memoryStore: env.memoryStore,
        // 16k-3: voice gets the composite — parent tools plus the
        // connected apps'. The decision gate above keeps the plain runner:
        // it only routes open_app/open_url and must not grow surface.
        parentTools: sensing.conversationTools,
        sensor: sensing.sensor,
        approvals: jobs.approvals,
        // Wave 12e: a hold with a text field in front dictates into it.
        fieldProbe: sensing.dictation,
        injector: sensing.dictation,
        screen: sensing.screenSight)
    // Wave 12c: what the first hold would otherwise pay for, done now
    // and measured. Never a permission prompt, never a socket. Detached:
    // a utility-priority task inherited by the main actor never ran
    // here (seen live 2026-09-06: "scheduled" logged, nothing after).
    Task.detached { await session.prewarm() }
    // MEDIUM finding (review 2026-09-22): the first decision turn after
    // launch otherwise loses the 2s DecisionGate budget race to Ollama's
    // cold model load and silently passes through. Pays that load once,
    // only when the toggle is on at launch (off means N1 never runs).
    if env.config.decision.enabled {
        Task.detached { await decisionProvider.warm() }
    }
    Task { await session.attachDecision(decisionGate) }
    // 15d-6: opt-in by env; off, the previous run's words are removed.
    let transcriptLog = TranscriptDebugLog.standard(home: env.home)
    if !env.config.debugTranscripts { transcriptLog.discard() }
    Task { await session.attachTranscriptLog(transcriptLog) }
    let ambience = AmbienceObserver(
        sound: ThinkingSound(),
        isEnabled: { ThinkingSoundPref.enabled })
    // Voice-born jobs, the parent's hands and settled permissions reach
    // the thread and the sheet through one stream.
    Task {
        for await event in session.events {
            await MainActor.run { sensing.model.receive(event) }
        }
    }
    sensing.voicePort.session = session
    let voice = VoiceViewModel(
        voice: session, thread: sensing.model,
        outputRoute: AudioOutputWatcher(),
        onSnapshot: { ambience.observe($0.state) },
        session: sensing.sessionModel)

    return VoicePipeline(openAIMouth: openAIMouth, mouth: mouth, voice: voice)
}
