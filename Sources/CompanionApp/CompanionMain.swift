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
    private var updates: UpdateState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Own log file: the prototype still writes Companion.log, and mixing
        // both makes voice debugging unreadable. Rename when it is retired.
        Log.configure(
            fileURL: home
                .appendingPathComponent("Library/Logs/CompanionNext.log"))
        Fonts.register()

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
            ownerFirstName: config.ownerFirstName,
            ownerAbout: config.ownerAbout,
            ownerInstructions: config.ownerInstructions,
            profileSource: {
                let live = configProvider.current
                return (live.ownerFirstName, live.ownerAbout,
                        live.ownerInstructions)
            })
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
            cliProbe: CLIExecutorProbe(),
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
        let attachRoot = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/attachments")
        do {
            try FileManager.default.createDirectory(
                at: attachRoot, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            Log.app("could not create attachments dir")
        }
        let attachmentStore = AttachmentStore(root: attachRoot)
        let model = ChatViewModel(
            chat: chat, secrets: secrets, store: store, config: config,
            jobSubmitter: jobRunner,
            notices: NoticeCenter(sound: sound),
            attachments: attachmentStore)
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
        // Voice-born jobs paint through the same seam as chat-born ones:
        // steps, thoughts and approvals land in the thread and the sheet.
        let onJobEvent: @Sendable (JobEvent) -> Void = { event in
            Task { @MainActor in model.receiveJobEvent(event) }
        }
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
            jobs: jobRunner,
            onJobEvent: onJobEvent)
        let ambience = AmbienceObserver(
            sound: ThinkingSound(),
            isEnabled: { ThinkingSoundPref.enabled })
        let voice = VoiceViewModel(
            voice: session, thread: model,
            outputRoute: AudioOutputWatcher(),
            onSnapshot: { ambience.observe($0.state) })
        self.voice = voice

        // Preview uses the chat audio endpoint, never the realtime session.
        let preview = VoicePreview(sampler: TTSVoiceSampler(
            fetcher: OpenAITTSClient(secrets: secrets, transport: transport),
            playback: DataSpeechPlayback()))
        self.voicePreview = preview

        // Update check: once per day, after launch settles; a hit shows the
        // W3 toast and lights the Settings row. Silence on any failure.
        let checker = UpdateChecker(transport: transport)
        let updates = UpdateState(checkNow: {
            guard let info = await checker.checkNow() else { return nil }
            return .init(tag: info.tag, pageURL: info.pageURL)
        })
        self.updates = updates
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard let info = await checker.checkIfDue() else { return }
            updates.found(.init(tag: info.tag, pageURL: info.pageURL))
            model.toast("Versión \(info.tag) disponible — Ajustes → Sistema")
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowChrome.designSize),
            styleMask: WindowChrome.styleMask,
            backing: .buffered,
            defer: false)
        window.title = "Companion"
        WindowChrome.configure(window)
        let root = CompanionRootView(
            chat: model, voice: voice,
            voicePreview: preview, executors: choice,
            onAECRearm: { UserDefaultsAECVeto().isVetoed = false },
            updates: updates)
        let hosting = NSHostingView(rootView: root)
        WindowChrome.install(hosting, in: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        AppMenu.install(routing: MenuRouting(
            openSettings: {
                NotificationCenter.default.post(
                    name: .companionOpenSettings, object: nil)
            },
            attach: {
                NotificationCenter.default.post(
                    name: .companionAttach, object: nil)
            },
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
