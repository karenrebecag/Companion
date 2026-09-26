import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import CoreGraphics
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
    private var island: IslandPanel?
    private var screenOverlays: ScreenOverlays?
    private var statusMenu: StatusBarMenu?
    private var holdKey: HoldKeyTap?
    /// 15b-1: the dictation key, separate from FN — `nil` when the setting
    /// is `.off`, same Accessibility permission as `holdKey`.
    private var dictationTap: HoldKeyTap?
    private var holdSettings: HoldSettingsModel?

    /// A net, not a guarantee, and the difference matters: this runs on an
    /// orderly quit and on nothing else. A crash or a Force Quit gives the app
    /// no chance, and macOS has no way to ask the kernel to take our children
    /// with us. What we started under those conditions survives us — stated
    /// here so nobody reads this method as a promise it cannot keep.
    func applicationWillTerminate(_ notification: Notification) {
        holdKey?.stop()
        dictationTap?.stop()
        ProcessRegistry.shared.terminateAll()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // The bundle around the binary decides which app this is; the log
        // follows it so two builds never interleave their turns.
        let identity = ProductIdentity.of(
            bundleID: Bundle.main.bundleIdentifier)
        Log.configure(
            fileURL: home.appendingPathComponent(
                "Library/Logs/\(identity.logFileName)"))
        Fonts.register()
        // Before any request: older builds cached keys and request bodies.
        LegacyURLCachePurge.runAtLaunch(bundleID: Bundle.main.bundleIdentifier)

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

        // Envuelto: el bucle de routing pide la misma clave dos veces por
        // proveedor y la voz otra vez al abrir sesion. Sin cache eso son
        // varias lecturas del llavero por mensaje, y cuando el ACL del item no
        // reconoce a la app, cada lectura es un dialogo de contrasena.
        let secrets = CachingSecretStore(KeychainSecretStore())
        let transport = URLSessionChatTransport()
        let probe = LiveCapabilityProbe(transport: transport)
        // No default reach. Handing over the whole home folder on first launch
        // was a security decision taken by omission: nobody chose it and
        // nobody was asked. Without a folder the specialist simply has none,
        // and the question arrives when reach is actually needed instead of
        // as friction at startup.
        // 9j-2: memory lives in plain markdown the user can open and edit.
        // The profile already written in Settings seeds the core on first run.
        let memoryStore = FileMemoryStore()
        memoryStore.ensureCore(seed: [UserProfile.about, UserProfile.instructions]
            .filter { !$0.isEmpty }.joined(separator: "\n\n"))
        // Wave 11a: skills and knowledge next to memory. The system skills
        // are seeded from the bundle at every launch; a bundle that does not
        // load is logged and the app runs without a catalog, promising none.
        let skillsLocation = SkillsLocation.standard()
        let bundledSkills: [BundledSkill]
        do {
            bundledSkills = try BundledSkills.load()
        } catch {
            Log.app("skills: bundle not loaded (\(error)); no system skills this launch")
            bundledSkills = []
        }
        let skillStore = SkillStore(location: skillsLocation, bundled: bundledSkills)
        let seeded = skillStore.seed()
        if !seeded.isEmpty { Log.app("skills: seeded \(seeded.joined(separator: ", "))") }
        let configProvider = StoredConfigProvider(
            workdir: nil, memory: memoryStore, skills: skillStore, location: skillsLocation)
        let config = configProvider.current
        // Which local model exists is a fact about THIS Mac, so the Ollama row
        // is resolved at runtime instead of shipping a fixed tag. Scanned once
        // at launch; the router reads the result per request.
        let localCatalog = LocalCatalog(
            scan: OllamaModelScan(transport: transport))
        // The router needs this even when onboarding never runs: someone with
        // a key still deserves the local model as a fallback. The onboarding
        // probe below refreshes it again only when there is NO key, which is
        // one extra GET to localhost in exchange for never routing to a model
        // the daemon does not have.
        Task {
            await localCatalog.refresh(
                preferred: ProviderPreference.localModel)
        }
        // One shape for every chat client below: they differ only in which
        // providers they may ask and how patiently.
        let makeChat: (
            [ProviderDescriptor], (@Sendable () -> [ProviderDescriptor])?, Int, Bool
        ) -> ChatProviderClient = { catalog, catalogSource, maxAttempts, voice in
            ChatProviderClient(
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
                },
                languageSource: { configProvider.current.language },
                memorySource: { configProvider.current.memory },
                skillsSource: { configProvider.current.skills },
                catalog: catalog,
                catalogSource: catalogSource,
                maxAttempts: maxAttempts,
                voice: voice)
        }
        let chat = makeChat(
            ProviderDescriptor.catalog, { localCatalog.effective() },
            RetryPolicy.maxAttempts, false)
        // Wave 15c-3/15e-3: the hold's own brain — Cerebras, one attempt;
        // its ladder falls to OpenAI's mini (`HoldBrainCatalog`).
        // 15d-9: both hold clients speak; only they get the voice rules.
        let fastBrain = makeChat(HoldBrainCatalog.fast, nil, 1, true)
        let holdLadder = makeChat(
            HoldBrainCatalog.ladder(ProviderDescriptor.catalog),
            { HoldBrainCatalog.ladder(localCatalog.effective()) },
            RetryPolicy.maxAttempts, true)
        let holdChat = FastBrainChatProvider(fast: fastBrain, ladder: holdLadder)
        let store = ConversationStore(directory: support)

        // Job execution infrastructure
        let approvals = Approvals(clock: RealtimeClock())
        let jobQueue = JobQueue()
        let nativeExecutor = NativeExecutor(
            descriptor: ExecutorCatalog.native,
            chatProvider: chat,
            config: config,
            approvals: approvals,
            webSearch: BraveWebSearch(transport: transport, secrets: secrets),
            skills: skillsLocation,
            skillsSource: { configProvider.current.skills })
        // The real provider probes for claude and hermes; without them the
        // catalog is just the native executor and nothing changes (ADR 001).
        let sessions = FileExecutorSessionStore(
            fileURL: support
                .deletingLastPathComponent()
                .appendingPathComponent("executor-sessions.json"))
        let executors = ExecutorProvider(
            nativeExecutor: nativeExecutor,
            cliProbe: CLIExecutorProbe(),
            workdir: config.workdir,
            approvals: approvals,
            sessions: sessions,
            skills: { configProvider.current.skills })
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
            approvals: approvals,
            language: { configProvider.current.language })

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
        // Shared with DecisionGate's world below: the router needs the same
        // installed/running app list the parent's own hands already read.
        let workspaceOpener = NSWorkspaceOpener()
        // What the app perceives around each turn (Wave 10a). Accessibility
        // is read per sense and never requested from here.
        let accessibility = AccessibilityPermission()
        let dictation = AXTextInjector(
            selfBundleID: Bundle.main.bundleIdentifier ?? "",
            trust: { accessibility.isTrusted() })
        if dictation == nil { Log.app("dictation: no bundle id — dictation off") }
        let frontmost = FrontmostAppSensor(
            selfBundleID: Bundle.main.bundleIdentifier ?? "", watch: true)
        // The parent's hands (Wave 10b): open, look, list — no job, no sheet.
        // Wave 15g: type, press, raise, read on the app the user was in —
        // the dictation adapter keyed to the sensor's last app that was not
        // us; offered only while Accessibility is trusted.
        let pointer = PointerSampler()
        let screenSight = ScreenSight(
            capture: ScreenCapture(
                bundleID: Bundle.main.bundleIdentifier ?? "",
                trusted: { ScreenRecordingPermission().isGranted() }),
            vision: ScreenVision(
                secrets: secrets, transport: transport),
            // Wave 15b-6: same window, read for its text instead of a
            // pixel — the pid is the one `OpenDocumentsSensor` already
            // reads (the app in front that is not us).
            axHarvest: AXScreenText(trusted: { accessibility.isTrusted() }).harvest,
            pid: { frontmost.lastOtherPID },
            appName: { frontmost.lastOtherName },
            // Wave 16a-3: pixels only when asked for, through `see`.
            visionPerTurn: false,
            // Wave 16o-3: what the cursor points at while the user speaks.
            pointerStart: { pointer.start() },
            pointerStop: { pointer.stop() })
        let parentTools = ParentToolRunner(
            workspace: workspaceOpener, places: MapKitPlacesSearch(),
            skills: skillStore,
            hands: dictation.map { ax in
                // Wave 16a: prime each app as it comes to the front, so its
                // tree exists by the time the user asks about it.
                let sight = AXScreen(
                    selfBundleID: Bundle.main.bundleIdentifier ?? "",
                    trust: { accessibility.isTrusted() })
                // Off the notification's thread: priming is two AX round
                // trips to an app that may be hung (code review 16).
                frontmost.onActivate = { pid, bundle in
                    Task.detached(priority: .utility) { sight.prime(pid: pid, bundle: bundle) }
                }
                if let pid = frontmost.lastOtherPID {
                    sight.prime(pid: pid, bundle: AXTextInjector.bundleID(of: pid))
                }
                return ScreenHands(ax: ax, screen: sight, target: { frontmost.lastOtherPID },
                                   selfInFront: { frontmost.selfInFront },
                                   see: { app in await screenSight.see(app: app) })
            })
        let sensor = SystemContextSensor(
            focused: frontmost,
            // Documents of the app the user was IN, not of Companion.
            documents: OpenDocumentsSensor(
                trusted: { accessibility.isTrusted() }, pid: { frontmost.lastOtherPID }),
            clipboard: ClipboardSensor())
        // One reducer for the chrome (Wave 12a): the chat, the voice and the
        // specialist all send here; the views read the projection. The voice
        // port is wired once the session exists (below).
        let voicePort = VoicePortBox()
        let sessionModel = SessionModel(
            jobs: jobRunner, approvals: approvals, voice: voicePort, log: { Log.app($0) })
        let model = ChatViewModel(
            chat: chat, secrets: secrets, store: store, config: config,
            jobSubmitter: jobRunner,
            notices: NoticeCenter(sound: sound),
            attachments: attachmentStore,
            startupProbe: localCatalog,
            parentTools: parentTools,
            sensor: sensor,
            accessibility: accessibility,
            screenRecording: ScreenRecordingPermission(),
            // The parent's open_url gate waits on the same actor as jobs.
            approvals: approvals,
            session: sessionModel,
            log: { Log.app($0) })
        self.model = model

        // Wave 15b-4: cached audio is one voice's phonemes, not another's —
        // switching voices in Settings must not play a stale one from disk.
        // Wave 15c-5: `tts-pcm`, not `tts` — the cached bytes went from mp3
        // to raw PCM, a format the new player would misread as noise; a new
        // folder orphans the old cache instead of decoding it wrong.
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/tts-pcm/\(config.voice.voice.rawValue)")
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
        // 15f-7a: ElevenLabs when its key and a voice are set, OpenAI
        // otherwise — decided per sentence, so a key saved in Settings
        // takes effect on the next hold and nothing reads the Keychain here.
        let openAIMouth = OpenAITTSClient(secrets: secrets, transport: transport, language: config.language)
        let mouth = MouthRouter(
            elevenLabs: ElevenLabsTTSClient(
                secrets: secrets, transport: transport, language: config.language,
                voiceID: { configProvider.current.elevenLabsVoiceID }),
            openAI: openAIMouth, secrets: secrets,
            voiceID: { configProvider.current.elevenLabsVoiceID })
        let synthesizer = SpeechSynthesis(
            cache: PhraseCache(directory: caches),
            fetcher: mouth,
            playback: DataSpeechPlayback(),
            fallback: AVSpeechFallback(language: config.language),
            voice: config.voice.voice)
        // DM1c-2 (wave-dm1-router.md §8): N1 decides locally, in front of the
        // classic hold — off by default (`Config.decision.enabled`). N2's own
        // model pair is DM1d/settings work; a pass-through arbiter just lets
        // an `.arbitrate` disposition fall through to today's path meanwhile.
        // DM1c-4: the only two irreversible ops with an executor — never
        // Companion's own pid/bundle, guarded by `frontmost.lastOtherPID`.
        let systemActions = SystemActionRunner(
            selfBundleID: Bundle.main.bundleIdentifier ?? "",
            frontmostOtherPID: { frontmost.lastOtherPID })
        let decisionProvider = OllamaDecisionProvider(
            baseURL: URL(string: config.decision.ollamaURL) ?? ProviderDescriptor.ollama.baseURL,
            model: config.decision.judgeModel)
        let decisionGate = DecisionGate(
            provider: decisionProvider,
            arbiter: PassThroughArbiter(),
            tools: parentTools,
            system: systemActions,
            world: {
                DecisionWorld(
                    apps: workspaceOpener.runningApplications()
                        + workspaceOpener.installedApplications(),
                    skills: skillStore.catalog().map(\.name))
            },
            budget: config.decision.budget)
        // 15d perf: the release path reads app names from memory only.
        let installedApps = InstalledAppsCache(load: { workspaceOpener.installedApplications() })
        installedApps.prewarm()
        // 15e-0: the hold's only ear, on-device. Spelling bias: the owner,
        // the user's own words (16d), then what is running (most likely
        // named), then what is installed.
        let ear = AnalyzerTranscriber(
            engine: AppleSpeechEngine(),
            vocabulary: {
                [configProvider.current.ownerFirstName]
                    + VocabularyPreference.words
                    + workspaceOpener.runningApplications()
                    + installedApps.names()
            })
        // The model is a one-time ~52 s download; started now so the first
        // hold does not end in "no te oí" waiting for it.
        let earLocale = config.language.speechLocaleIdentifier
        Task.detached { await ear.prepare(localeIdentifier: earLocale) }
        let session = VoiceSession(
            transport: RealtimeWSTransport(),
            mic: mic,
            player: player,
            transcriber: ear,
            synthesizer: synthesizer,
            chat: holdChat,
            secrets: secrets,
            thread: model,
            configProvider: configProvider,
            jobs: jobRunner,
            // Realtime hears through OpenAI's live transcription (measured
            // better on mixed-language speech); classic keeps the on-device
            // ear, which needs no key and no network.
            realtimeEar: OpenAITranscriber(
                keyProvider: { try? secrets.read(.openAI) ?? nil },
                // The Settings knob drives the server's VAD (9j-1).
                turnDetection: { configProvider.current.voice.turnDetection }),
            memoryStore: memoryStore,
            parentTools: parentTools,
            sensor: sensor,
            approvals: approvals,
            // Wave 12e: a hold with a text field in front dictates into it.
            fieldProbe: dictation,
            injector: dictation,
            screen: screenSight)
        // Wave 12c: what the first hold would otherwise pay for, done now
        // and measured. Never a permission prompt, never a socket. Detached:
        // a utility-priority task inherited by the main actor never ran
        // here (seen live 2026-09-06: "scheduled" logged, nothing after).
        Task.detached { await session.prewarm() }
        // MEDIUM finding (review 2026-09-22): the first decision turn after
        // launch otherwise loses the 2s DecisionGate budget race to Ollama's
        // cold model load and silently passes through. Pays that load once,
        // only when the toggle is on at launch (off means N1 never runs).
        if config.decision.enabled {
            Task.detached { await decisionProvider.warm() }
        }
        Task { await session.attachDecision(decisionGate) }
        // 15d-6: opt-in by env; off, the previous run's words are removed.
        let transcriptLog = TranscriptDebugLog.standard(home: home)
        if !config.debugTranscripts { transcriptLog.discard() }
        Task { await session.attachTranscriptLog(transcriptLog) }
        let ambience = AmbienceObserver(
            sound: ThinkingSound(),
            isEnabled: { ThinkingSoundPref.enabled })
        // Voice-born jobs, the parent's hands and settled permissions reach
        // the thread and the sheet through one stream.
        Task {
            for await event in session.events {
                await MainActor.run { model.receive(event) }
            }
        }
        voicePort.session = session
        let voice = VoiceViewModel(
            voice: session, thread: model,
            outputRoute: AudioOutputWatcher(),
            onSnapshot: { ambience.observe($0.state) },
            session: sessionModel)
        self.voice = voice
        // Wave 12h: FN is an Accessibility HID tap (same permission as
        // dictation). Solo FN is swallowed; Input Monitoring is not used.
        let holdSettings = HoldSettingsModel(permission: AccessibilityPermission())
        self.holdSettings = holdSettings
        let holdKey = HoldKeyTap()
        self.holdKey = holdKey
        holdSettings.onPermissionChanged = { [weak self] in
            self?.startHoldKeyIfAllowed()
        }
        Task {
            for await event in holdKey.events {
                await MainActor.run {
                    switch event {
                    // FN opens the mic on the way down; the threshold's
                    // `.confirmed` is what makes it a hold.
                    case .pressed: sessionModel.send(.pressedProvisionally)
                    case .confirmed: sessionModel.send(.holdConfirmed)
                    case .released: sessionModel.send(.released)
                    case .tapped: sessionModel.send(.tapped)
                    case .cancelled: sessionModel.send(.holdCancelled)
                    }
                }
            }
        }
        // 15b-1: dictation is its own hold now, off FN. `nil` when the
        // setting is `.off` — nothing installed, nothing to permission-gate.
        installDictationTap(voicePort: voicePort, sessionModel: sessionModel)
        // Code review 2026-09-23 (medio): the tap above was only ever built
        // from the setting read at launch — changing "Tecla de dictado" in
        // Settings did nothing until restart. Same pattern as
        // `companionShortcutsDidChange`: the UI persists and posts, the App
        // layer rebuilds.
        NotificationCenter.default.addObserver(
            forName: .companionDictationKeyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.installDictationTap(voicePort: voicePort, sessionModel: sessionModel)
            }
        }
        // Follow up (spec 16j §8): the window steps aside so the task
        // continues in the island, as Incredible's does.
        NotificationCenter.default.addObserver(
            forName: .companionFollowUp, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.window?.orderOut(nil) }
        }
        startHoldKeyIfAllowed()

        // Preview uses the chat audio endpoint, never the realtime session.
        // 15f-6: the ElevenLabs sample goes through the hold's own router,
        // so what Settings plays is what the hold will say.
        let preview = VoicePreview(
            sampler: TTSVoiceSampler(fetcher: openAIMouth, playback: DataSpeechPlayback()),
            mouth: TTSVoiceSampler(fetcher: mouth, playback: DataSpeechPlayback()))
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
            updates: updates,
            welcome: WelcomeModel(
                devices: SystemWelcomeDevices(),
                keyReady: { [weak model] in model.map { !$0.needsOnboarding } ?? false }),
            memory: memoryStore,
            apps: AppsModel(secrets: secrets, makeService: { HTTPAppsService(base: $0, key: $1) }))
        let hosting = NSHostingView(rootView: root)
        WindowChrome.install(hosting, in: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        // The sheet has one host at a time: main while it is key, the
        // island otherwise.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { _ in
                Task { @MainActor in
                    holdSettings.mainInFront = window.isKeyWindow
                }
            }
        }
        holdSettings.mainInFront = window.isKeyWindow
        // Before the island: at the same level, the later window stays on top.
        screenOverlays = ScreenOverlays(session: sessionModel, onFailure: { Log.app($0) })
        let islandGeometry = IslandGeometry()
        let island = IslandPanel(
            content: IslandView(
                chat: model, voice: voice, hold: holdSettings, geometry: islandGeometry,
                onShowMain: { [weak self] in self?.showMain() },
                onSize: { [weak self] size, height in
                    self?.island?.present(size: size, contentHeight: height)
                    Log.app("island: \(size)")
                },
                onReleaseKey: { [weak self] in self?.island?.releaseKey() }),
            geometry: islandGeometry,
            onHover: { over in sessionModel.send(over ? .hoverEntered : .hoverLeft) })
        island.onResignKey = {
            NotificationCenter.default.post(name: .islandResignedKey, object: nil)
        }
        self.island = island
        island.present(size: holdSettings.pebbleHidden ? .hidden : .pebble, contentHeight: 0)
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
        statusMenu = StatusBarMenu(actions: [
            .cancel: {
                if model.session.projection.job != nil { model.cancelJob() }
                sessionModel.send(.stop)
            },
            .show: { [weak self] in self?.showMain() },
            .settings: { [weak self] in
                self?.showMain()
                NotificationCenter.default.post(name: .companionOpenSettings, object: nil)
            },
            .checkUpdates: { [weak self] in
                self?.showMain()
                NotificationCenter.default.post(
                    name: .companionOpenSettings, object: SettingsTab.system.rawValue)
                updates.requestCheck()
            },
            .quit: { NSApp.terminate(nil) },
        ])
        Log.app("launched")
    }

    /// The hold lives outside the window (Wave 12b): closing main leaves
    /// the island and the key. Cmd+Q still quits.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        showMain()
        return false
    }

    /// The permission may have been granted in System Settings meanwhile:
    /// coming back to the app is the moment to try the tap again.
    func applicationDidBecomeActive(_ notification: Notification) {
        holdSettings?.refresh()
        startHoldKeyIfAllowed()
        // Wave 15a §10: Karen chose "already clean" — the thread archives
        // here, before the window can show it stale.
        model?.rolloverIfIdle()
    }

    private func showMain() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Code review 2026-09-23 (medio): builds (or tears down) `dictationTap`
    /// from the CURRENT setting — called at launch and again on
    /// `.companionDictationKeyDidChange`, so a change in Settings takes
    /// effect without a restart. `DictationTapChange.decide` (Core, pure)
    /// is the actual decision; this just acts on it.
    private func installDictationTap(voicePort: VoicePortBox, sessionModel: SessionModel) {
        dictationTap?.stop()
        dictationTap = nil
        let setting = VoiceProfile.settings.dictationKey
        guard case .rebuild(let keyCode, let flag) = DictationTapChange.decide(for: setting) else {
            Log.app("dictation: tap off")
            return
        }
        let tap = HoldKeyTap(
            keyCode: keyCode, flag: CGEventFlags(rawValue: flag), swallowsRelease: false,
            armsOnDown: false)
        dictationTap = tap
        Task {
            for await event in tap.events {
                await MainActor.run {
                    // Marked BEFORE the reducer sees the press: the very
                    // next hold this session opens is the dictating one.
                    if event == .pressed { voicePort.dictatesNextHold = true }
                    switch event {
                    case .pressed: sessionModel.send(.pressed)
                    case .released: sessionModel.send(.released)
                    case .tapped: sessionModel.send(.tapped)
                    case .cancelled: sessionModel.send(.holdCancelled)
                    case .confirmed: sessionModel.send(.holdConfirmed)
                    }
                }
            }
        }
        startHoldKeyIfAllowed()
    }

    private func startHoldKeyIfAllowed() {
        guard let holdKey else { return }
        holdSettings?.refresh()
        guard holdSettings?.granted == true else {
            holdKey.stop()
            dictationTap?.stop()
            Log.app("hold: FN tap not installed (Accessibility not granted)")
            return
        }
        if holdKey.start() {
            Log.app("hold: FN tap listening")
        } else {
            Log.app("hold: FN tap not installed (Accessibility not granted)")
        }
        // 15b-1: same permission as FN; `nil` when the setting is `.off`.
        if let dictationTap, dictationTap.start() {
            Log.app("hold: dictation tap listening")
        }
    }
}

/// DM1c-2: N2's own fast/strong model pair is not chosen yet (DM1d or the
/// Settings toggle work). Until then, an `.arbitrate` disposition just falls
/// through to today's model-in-the-loop path instead of guessing a model.
private struct PassThroughArbiter: Arbitrating {
    func arbitrate(
        utterance: String, shortlist: ArbitrationShortlist
    ) async -> (entry: ShortlistEntry, confidence: Double)? { nil }
}

/// The voice port for the session reducer, filled once the voice session
/// exists: the reducer is built before the session that obeys it.
final class VoicePortBox: VoiceControlling, @unchecked Sendable {
    var session: VoiceSession?
    /// 15b-1: set by the dictation tap's own press, just before it reaches
    /// the session reducer — the very next `hold()` consumes and clears it,
    /// so a later FN press never inherits a stale dictation intent.
    var dictatesNextHold = false

    func setSpeed(_ speed: Double) async { await session?.setSpeed(speed) }
    func setVolume(_ volume: Double) async { await session?.setVolume(volume) }
    func start() async { await session?.start() }
    func advance() async { await session?.advance() }
    func hangUp() async { await session?.hangUp() }
    func toggleMute() async { await session?.toggleMute() }
    func push(attachment: AttachmentRef) async { await session?.push(attachment: attachment) }
    func hold() async {
        let dictate = dictatesNextHold
        dictatesNextHold = false
        await session?.hold(dictate: dictate)
    }
    func holdProvisionally() async {
        let dictate = dictatesNextHold
        dictatesNextHold = false
        await session?.hold(dictate: dictate, provisional: true)
    }
    func confirmHold() async { await session?.confirmHold() }
    func release() async { await session?.release() }
    func discard() async { await session?.discard() }
    func interrupt() async { await session?.interrupt() }
    var snapshots: AsyncStream<TurnSnapshot> { session?.snapshots ?? AsyncStream { $0.finish() } }
    var levels: AsyncStream<VoiceLevels> { session?.levels ?? AsyncStream { $0.finish() } }
}
