import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import CoreGraphics
import SwiftUI

/// What the app perceives around a turn (Wave 10a/10b), the reducer that
/// carries the chrome's state, and the chat model built on top of it. Split
/// out of `applicationDidFinishLaunching` when CompanionMain crossed the
/// 400-line gate. `self.model` is set by the caller, which keeps that stored
/// property private to CompanionMain.swift.
struct SensingAndModel {
    let attachmentStore: AttachmentStore
    let workspaceOpener: NSWorkspaceOpener
    let dictation: AXTextInjector?
    let frontmost: FrontmostAppSensor
    let screenSight: ScreenSight
    let parentTools: ParentToolRunner
    /// 16k-3: parent tools PLUS the connected apps' tools — what chat and
    /// both voice modes get. The bridge keeps `parentTools` on purpose:
    /// an MCP client lends the hands, it does not inherit Karen's Slack.
    let conversationTools: any ParentToolExecuting
    /// Wave 18-3c: the browser's listener, runner and installer. Its tools
    /// ride in `conversationTools` and, without the apps', in the bridge.
    let browserHost: BrowserHost
    let appTools: AppToolRunner
    let sensor: SystemContextSensor
    let voicePort: VoicePortBox
    let sessionModel: SessionModel
    let model: ChatViewModel
}

/// Verbatim from the sensing/parent-tools/model section of the old
/// `applicationDidFinishLaunching`.
func makeSensingAndModel(
    environment env: LaunchEnvironment, providers: ChatProviders, jobs: JobInfrastructure
) -> SensingAndModel {
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
    let receipts = ReceiptRelay()
    let pointer = PointerSampler()
    // Gap 1: sight waits for one real probe; the preflight alone can be
    // true with captures failing. The first capture probes, not the launch:
    // the system's periodic re-approval alert then follows the user's ask.
    let screenRecording = ScreenRecordingGate(checker: ScreenRecordingPermission(), log: { Log.app($0) })
    let screenSight = ScreenSight(
        capture: ScreenCapture(
            bundleID: Bundle.main.bundleIdentifier ?? "",
            trusted: { ScreenRecordingPermission().isGranted() },
            gate: screenRecording),
        vision: ScreenVision(
            secrets: env.secrets, transport: env.transport),
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
    // 16h-3: "nearby" is the city typed in Settings, else the system's (asked
    // once, cached, never coordinates). The search provider's guess is never
    // consulted.
    let location = UserLocationSource(
        manualCity: { [configProvider = env.configProvider] in configProvider.ownerCity },
        system: CachedCityLocator(CoreLocationCityLocator()))
    let parentTools = ParentToolRunner(
        workspace: workspaceOpener, places: MapKitPlacesSearch(),
        skills: env.skillStore,
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
                               see: { request in await screenSight.see(request) },
                               changes: AXChangeWatcher(trust: { accessibility.isTrusted() }),
                               gate: screenRecording)
        },
        // Wave 20b D2: with Claude Code installed no delegation reaches the
        // native lane, so the parent carries the deliverables itself.
        workdir: env.config.workdir,
        documents: NativeDocumentRenderer(),
        sheets: AppleEventSheets(),
        onAct: { receipts.send($0) },
        location: location,
        // 16q-2: the same switch the turn's context reads (pinned by a test and Gate 3).
        locationChannelOn: { ContextPreference.locationChannelOn })
    // 16h-3: what the island did (cards shown, closed, ignored, a stop) waits
    // here for the next turn, voice or chat.
    let islandEvents = IslandEventBuffer()
    let sensor = SystemContextSensor(
        focused: frontmost,
        // Documents of the app the user was IN, not of Companion.
        documents: OpenDocumentsSensor(
            trusted: { accessibility.isTrusted() }, pid: { frontmost.lastOtherPID }),
        clipboard: ClipboardSensor(),
        window: FocusedWindowSensor(
            trusted: { accessibility.isTrusted() }, pid: { frontmost.lastOtherPID }),
        location: location, islandEvents: islandEvents)
    // One reducer for the chrome (Wave 12a): the chat, the voice and the
    // specialist all send here; the views read the projection. The voice
    // port is wired once the session exists (below).
    let voicePort = VoicePortBox()
    let sessionModel = SessionModel(
        jobs: jobs.jobRunner, approvals: jobs.approvals, voice: voicePort, log: { Log.app($0) })
    sessionModel.islandEvents = islandEvents
    sessionModel.armPresence()
    // Wave 20d B: what ran without the sheet reaches the island with its
    // undo; the press is the user's alone.
    receipts.connect { receipt in
        Task { @MainActor in sessionModel.send(.actionDone(receipt)) }
    }
    screenRecording.onLost {
        Task { @MainActor in sessionModel.send(.screenRecordingLost) }
    }
    let undoer = ActionUndoer(sheets: AppleEventSheets())
    sessionModel.onUndo = { receipt in
        guard let step = receipt.undo else { return }
        Task {
            let undone = await undoer.undo(step)
            await MainActor.run {
                sessionModel.send(.actionDone(UndoReceipt(
                    kind: undone ? .undone : .couldNotUndo, subject: receipt.subject)))
            }
        }
    }
    // 16k-3: the connected apps' tools ride next to the parent's. The
    // service is rebuilt per use from the same two settings the Apps page
    // reads (endpoint in defaults, key in the Keychain); the suggestion
    // callback raises the island's "Conectar X" card through the reducer.
    let appTools = AppToolRunner(
        service: { [secrets = env.secrets, hostSecrets = env.hostSecrets, pin = env.appsPin] in
            let found: (url: URL, key: String?)?
            do {
                found = try AppsCredentials.currentKey(
                    endpoint: UserDefaults.standard.string(forKey: AppsModel.endpointDefault),
                    legacy: secrets, bound: hostSecrets, pin: pin, log: { Log.app($0) })
            } catch {
                // Distinguishable in the log: a Keychain failure is not
                // "not configured" (review 16k-3 L2).
                Log.app("apps: keychain read failed for the runner")
                return nil
            }
            guard let url = found?.url, let key = found?.key, key.count >= 32 else { return nil }
            return HTTPAppsService(base: url, key: key)
        },
        catalog: CatalogSeed.apps(language: .en).map {
            AppMention.Candidate(slug: $0.slug, name: $0.name)
        },
        suggest: { slug, name in
            Task { @MainActor in
                _ = sessionModel.send(.connectAppSuggested(slug: slug, name: name))
            }
        },
        signIn: { slug, name in
            Task { @MainActor in
                _ = sessionModel.send(.signInAppSuggested(slug: slug, name: name))
            }
        })
    Task.detached(priority: .utility) { await appTools.refresh() }
    // The Apps page says when an account changed; the TTL is only the
    // fallback for changes made outside this app.
    NotificationCenter.default.addObserver(
        forName: .companionAppsChanged, object: nil, queue: nil
    ) { _ in
        Task.detached(priority: .utility) { await appTools.refresh() }
    }
    let browserHost = BrowserHost(
        directory: BridgePaths.directory,
        installer: NativeHostInstaller(
            home: FileManager.default.homeDirectoryForCurrentUser,
            // No executable path means an unstable one: connecting then asks to move the app.
            executable: Bundle.main.executableURL ?? URL(fileURLWithPath: "/")),
        language: { env.configProvider.current.language })
    // Conversation only, like the connected apps: the bridge never lends it.
    let windowTools = WindowArrangeRunner(
        arranging: AXWindowArranger(trust: { accessibility.isTrusted() }))
    let conversationTools = browserHost.conversationTools(
        parent: CompositeParentTools([parentTools, windowTools]), apps: appTools)
    let model = ChatViewModel(
        chat: providers.chat, secrets: env.secrets, store: providers.store, config: env.config,
        jobSubmitter: jobs.jobRunner,
        notices: NoticeCenter(sound: sound),
        attachments: attachmentStore,
        startupProbe: providers.localCatalog,
        parentTools: conversationTools,
        sensor: sensor,
        accessibility: accessibility,
        screenRecording: ScreenRecordingPermission(),
        // The parent's open_url gate waits on the same actor as jobs.
        approvals: jobs.approvals,
        session: sessionModel,
        log: { Log.app($0) })

    return SensingAndModel(
        attachmentStore: attachmentStore, workspaceOpener: workspaceOpener,
        dictation: dictation, frontmost: frontmost, screenSight: screenSight,
        parentTools: parentTools, conversationTools: conversationTools, browserHost: browserHost,
        appTools: appTools, sensor: sensor, voicePort: voicePort,
        sessionModel: sessionModel, model: model)
}
