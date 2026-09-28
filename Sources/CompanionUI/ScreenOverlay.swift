import AppKit
import CompanionCore
import SwiftUI

// Wave 16o-2: one clear, click-through window per display for what Companion
// draws over the whole screen while it listens (the glow; 16o-3 the pointer).
// Placed once per display change; only what is inside it animates.

final class ScreenOverlayPanel: NSPanel {
    init(screen: NSScreen, content: some View) {
        super.init(contentRect: screen.frame, styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        // Over the menu bar, like the island; created first, so the island stays above it.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Companion's own screenshots must see the screen, not its glow.
        sharingType = .none
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The overlays for every connected display, rebuilt when displays change.
@MainActor
public final class ScreenOverlays {
    private var panels: [ScreenOverlayPanel] = []
    private var observer: NSObjectProtocol?
    private let makeContent: (CGRect) -> AnyView

    public init(session: SessionModel, onFailure: @escaping (String) -> Void) {
        makeContent = { frame in
            AnyView(ScreenOverlayView(session: session, screenFrame: frame, onFailure: onFailure))
        }
        rebuild()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    private func rebuild() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { ScreenOverlayPanel(screen: $0, content: makeContent($0.frame)) }
        panels.forEach { $0.orderFrontRegardless() }
    }
}

struct ScreenOverlayView: View {
    let session: SessionModel
    let screenFrame: CGRect
    let onFailure: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Observed, so turning it off in Settings mid-hold hides it at once.
    @AppStorage(ScreenGlowPreference.key) private var glowEnabled = true
    @State private var opacity = 0.0
    @State private var running = false
    @State private var stopTask: Task<Void, Never>?

    var body: some View {
        let kind = session.projection.kind
        let target = ScreenGlow.target(kind, enabled: glowEnabled, hands: handsHere)
        ZStack {
            // The shader draws at full strength; `listening` is the ceiling.
            ScreenGlowMetalView(running: running, animated: !reduceMotion, onFailure: onFailure)
                .opacity(opacity / ScreenGlow.listening)
            // 16o-3: read when the hold starts; one display draws, not all.
            if PointerOrb.shows(kind: kind, reduceMotion: reduceMotion, screen: screenFrame,
                                cursor: NSEvent.mouseLocation) {
                PointerLayer(screenFrame: screenFrame)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: target, initial: true) { _, new in show(new) }
    }

    /// Read when the projection changes (each call republishes the target),
    /// so a moved window or cursor is picked up on the next call.
    private var handsHere: Bool {
        guard session.projection.handsActing else { return false }
        let screens = NSScreen.screens.map(\.frame)
        let primaryHeight = screens.first?.height ?? screenFrame.height
        let target = session.projection.handsTarget.map {
            ScreenGlow.appKitFrame(fromAX: $0, primaryHeight: primaryHeight)
        }
        return ScreenGlow.handsOnScreen(
            screenFrame: screenFrame, screens: screens, target: target, cursor: NSEvent.mouseLocation)
    }

    private func show(_ target: Double) {
        stopTask?.cancel()
        if target > 0 { running = true }
        let fade = ScreenGlow.fade(from: opacity, to: target)
        withAnimation(MotionCurve.animation(MotionCurve.standard, fade)) { opacity = target }
        guard target == 0 else { return }
        // The renderer stops once the fade is over: an idle Mac spends no GPU.
        stopTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(fade)) } catch { return }
            running = false
        }
    }
}
