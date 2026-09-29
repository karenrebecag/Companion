import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import CoreGraphics
import SwiftUI

/// The hold key, the main window, the island and the menus — the last stage
/// of launch, and the one most tied to `self` (weak-self closures, other
/// AppDelegate methods). Split out of `applicationDidFinishLaunching` when
/// CompanionMain crossed the 400-line gate. Stays an AppDelegate extension
/// rather than a free function for that reason; the stored properties it
/// sets and the helpers it calls (`installDictationTap`, `showMain`,
/// `startHoldKeyIfAllowed`) were widened from `private` to `internal` in
/// CompanionMain.swift so this file can reach them.
extension AppDelegate {
    /// Verbatim from the hold-key/window/island/menu section of the old
    /// `applicationDidFinishLaunching`.
    func presentWindow(
        model: ChatViewModel, voice: VoiceViewModel, sessionModel: SessionModel,
        memoryStore: FileMemoryStore, secrets: CachingSecretStore,
        openAIMouth: OpenAITTSClient, mouth: MouthRouter, transport: URLSessionChatTransport,
        voicePort: VoicePortBox
    ) {
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
            voicePreview: preview,
            updates: updates,
            welcome: WelcomeModel(
                devices: SystemWelcomeDevices(),
                keyReady: { [weak model] in model.map { !$0.needsOnboarding } ?? false }),
            memory: memoryStore,
            apps: AppsModel(
                secrets: secrets, makeService: { HTTPAppsService(base: $0, key: $1) },
                // 16k-4: the Apps page edits the same mcp.json the user
                // could edit by hand; only this root touches the disk.
                readMCP: { MCPConfigFile.read() },
                saveMCP: { try MCPConfigFile.save($0) }))
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
                onReleaseKey: { [weak self] in self?.island?.releaseKey() },
                grabber: ScreenRegionGrabber(directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("companion-captures", isDirectory: true))),
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
            .stopHands: { [weak self] in self?.bridgeHost?.stopHands() },
            .quit: { NSApp.terminate(nil) },
        ])
        Log.app("launched")
    }
}
