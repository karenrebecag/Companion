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
    /// Set by `presentWindow` (CompanionMainWindow.swift), read there and in
    /// `showMain`/`installDictationTap`/`startHoldKeyIfAllowed` below —
    /// internal instead of private so that sibling file can reach it.
    var window: NSWindow?
    private var model: ChatViewModel?
    private var voice: VoiceViewModel?
    /// Set by `presentWindow`.
    var voicePreview: VoicePreview?
    private var executorChoice: ExecutorChoice?
    /// Set by `presentWindow`.
    var updates: UpdateState?
    /// Set by `presentWindow`, read by its own closures.
    var island: IslandPanel?
    /// Set by `presentWindow`.
    var screenOverlays: ScreenOverlays?
    /// Set by `presentWindow`.
    var statusMenu: StatusBarMenu?
    /// Set by `presentWindow`, read by `startHoldKeyIfAllowed` below.
    var holdKey: HoldKeyTap?
    /// 15b-1: the dictation key, separate from FN — `nil` when the setting
    /// is `.off`, same Accessibility permission as `holdKey`.
    private var dictationTap: HoldKeyTap?
    /// Set by `presentWindow`, read by `startHoldKeyIfAllowed` below.
    var holdSettings: HoldSettingsModel?
    /// Wave 17: the local MCP bridge for Claude Code, off unless the setting
    /// is on. Read by `presentWindow` (the status menu's "Detener manos").
    var bridgeHost: BridgeHost?

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

    /// The composition root: builds every adapter and wires them together.
    /// Broken into stages (CompanionMainEnvironment/Providers/Sensing/Voice)
    /// plus the self-heavy final stage (CompanionMainWindow's `presentWindow`)
    /// when this method crossed the 400-line gate — each stage is the
    /// original code verbatim, only wrapped in a factory function.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = makeLaunchEnvironment()
        let providers = makeChatProviders(environment: env)
        let jobs = makeJobInfrastructure(environment: env, chat: providers.chat)
        self.executorChoice = jobs.choice
        let sensing = makeSensingAndModel(environment: env, providers: providers, jobs: jobs)
        self.model = sensing.model
        let pipeline = makeVoicePipeline(
            environment: env, providers: providers, jobs: jobs, sensing: sensing)
        self.voice = pipeline.voice
        installBridge(environment: env, jobs: jobs, sensing: sensing)
        presentWindow(
            model: sensing.model, voice: pipeline.voice, sessionModel: sensing.sessionModel,
            choice: jobs.choice, memoryStore: env.memoryStore, secrets: env.secrets, hostSecrets: env.hostSecrets,
            openAIMouth: pipeline.openAIMouth, mouth: pipeline.mouth, transport: env.transport,
            voicePort: sensing.voicePort)
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

    /// Wave 17: the same `parentTools`/`approvals` the chat and the voice
    /// already use — the bridge is a third caller of the same seam, not a
    /// second set of hands. Starts only if the setting was already on from
    /// a previous launch; the toggle in Settings starts/stops it live.
    private func installBridge(
        environment env: LaunchEnvironment, jobs: JobInfrastructure, sensing: SensingAndModel
    ) {
        let accessibility = AccessibilityPermission()
        // Only its window-frame read is used, which keeps no handles.
        let windows = AXScreen(
            selfBundleID: Bundle.main.bundleIdentifier ?? "",
            trust: { accessibility.isTrusted() })
        let bridgeHost = BridgeHost(
            tools: sensing.parentTools, approvals: jobs.approvals,
            language: { env.configProvider.current.language },
            accessibility: { accessibility.isTrusted() },
            sessionModel: sensing.sessionModel,
            targetFrame: {
                guard let pid = sensing.frontmost.lastOtherPID else { return nil }
                return windows.windowFrame(pid: pid)
            })
        bridgeHost.apply(enabled: HandsLendingPreference.enabled)
        self.bridgeHost = bridgeHost
        NotificationCenter.default.addObserver(
            forName: .companionHandsLendingDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in bridgeHost.apply(enabled: HandsLendingPreference.enabled) }
        }
        NotificationCenter.default.addObserver(
            forName: .companionStopHands, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in bridgeHost.stopHands() }
        }
    }

    /// Called from CompanionMainWindow.swift's `presentWindow`.
    func showMain() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Code review 2026-09-23 (medio): builds (or tears down) `dictationTap`
    /// from the CURRENT setting — called at launch and again on
    /// `.companionDictationKeyDidChange`, so a change in Settings takes
    /// effect without a restart. `DictationTapChange.decide` (Core, pure)
    /// is the actual decision; this just acts on it.
    ///
    /// Called from CompanionMainWindow.swift's `presentWindow`.
    func installDictationTap(voicePort: VoicePortBox, sessionModel: SessionModel) {
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

    /// Called from CompanionMainWindow.swift's `presentWindow`.
    func startHoldKeyIfAllowed() {
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
