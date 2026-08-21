import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import SwiftUI

@main
enum CompanionMain {
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var model: ChatViewModel?
    private var voice: VoiceViewModel?
    private var voicePreview: VoicePreview?
    private var executorChoice: ExecutorChoice?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Own log file: the prototype still writes Companion.log, and mixing
        // both makes voice debugging unreadable. Rename when it is retired.
        Log.configure(
            fileURL: home
                .appendingPathComponent("Library/Logs/CompanionNext.log"))

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/conversations")
        do {
            try FileManager.default.createDirectory(
                at: support, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            // Log without error details to avoid exposing system paths/permissions.
            Log.app("could not create conversations dir")
        }

        let secrets = KeychainSecretStore()
        let transport = URLSessionChatTransport()
        let probe = LiveCapabilityProbe(transport: transport)
        let configProvider = StoredConfigProvider(
            workdir: FileManager.default.homeDirectoryForCurrentUser.path)
        let config = configProvider.current
        let chat = ChatProviderClient(
            secrets: secrets,
            probe: probe,
            transport: transport,
            settings: config.chat,
            ownerFirstName: config.ownerFirstName)
        let store = ConversationStore(directory: support)

        // Job execution infrastructure
        let approvals = Approvals(clock: RealtimeClock())
        let jobQueue = JobQueue()
        let nativeExecutor = NativeExecutor(
            descriptor: ExecutorCatalog.native,
            chatProvider: chat,
            config: config,
            approvals: approvals)
        // The real provider probes for claude and hermes; without them the
        // catalog is just the native executor and nothing changes (ADR 001).
        let executors = ExecutorProvider(
            nativeExecutor: nativeExecutor,
            cliProbe: CLIExecutorProbe(
                processLauncher: RealProcessLauncher(),
                workdir: config.workdir ?? FileManager.default
                    .homeDirectoryForCurrentUser.path),
            workdir: config.workdir,
            approvals: approvals)
        // The picker starts with the native executor and grows when the probe
        // finds a CLI; nothing appears if none is installed (ADR 001).
        let choice = ExecutorChoice(
            available: [ExecutorCatalog.native],
            selected: .native
        ) { id in
            _ = executors.selectExecutor(id: id)
        }
        self.executorChoice = choice
        Task {
            await executors.refreshAvailableExecutors()
            await MainActor.run {
                choice.refresh(
                    executors.getAvailableExecutors(),
                    selected: executors.getSelectedExecutorId())
            }
        }

        let jobRunner = JobRunner(
            executorProvider: executors,
            queue: jobQueue,
            approvals: approvals)

        let sound = SynthesizedUISound(
            isEnabled: { InterfaceSound.enabled })
        let model = ChatViewModel(
            chat: chat, secrets: secrets, store: store, config: config,
            jobSubmitter: jobRunner,
            notices: NoticeCenter(sound: sound))
        self.model = model

        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/tts")
        do {
            try FileManager.default.createDirectory(
                at: caches, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            Log.app("could not create tts cache dir")
        }

        // Player joins the mic engine only while Voice Processing is live, so
        // AEC hears the agent; weak keeps the player from owning the mic.
        let mic = MicCapture(echoCancellation: config.voice.echoCancellation)
        let player = RealtimePlayer(
            sharedWith: mic, volume: config.voice.volume)
        let synthesizer = SpeechSynthesis(
            cache: PhraseCache(directory: caches),
            fetcher: OpenAITTSClient(secrets: secrets, transport: transport),
            playback: DataSpeechPlayback(),
            fallback: AVSpeechFallback(),
            voice: config.voice.voice)
        let session = VoiceSession(
            transport: RealtimeWSTransport(),
            mic: mic,
            player: player,
            transcriber: SystemTranscriber(),
            synthesizer: synthesizer,
            chat: chat,
            secrets: secrets,
            thread: model,
            configProvider: configProvider,
            jobs: jobRunner)
        let voice = VoiceViewModel(
            voice: session, thread: model,
            outputRoute: AudioOutputWatcher())
        self.voice = voice

        // Preview uses the chat audio endpoint, never the realtime session.
        let preview = VoicePreview(sampler: TTSVoiceSampler(
            fetcher: OpenAITTSClient(secrets: secrets, transport: transport),
            playback: DataSpeechPlayback()))
        self.voicePreview = preview

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.minSize = NSSize(width: 440, height: 660)
        window.maxSize = NSSize(width: 680, height: 1020)
        window.title = "Companion"
        window.contentView = NSHostingView(
            rootView: CompanionRootView(
                chat: model, voice: voice,
                voicePreview: preview, executors: choice,
                onAECRearm: { UserDefaultsAECVeto().isVetoed = false }))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        AppMenu.install(routing: MenuRouting(
            openSettings: {
                NotificationCenter.default.post(
                    name: .companionOpenSettings, object: nil)
            },
            attach: {},
            newConversation: {
                voice.hangUp()
                model.newConversation()
            },
            history: {},
            toggleVoice: {
                if voice.isActive { voice.hangUp() } else { voice.start() }
            },
            toggleMute: { voice.toggleMute() },
            hangUp: { voice.hangUp() }
        ))
        Log.app("launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}
