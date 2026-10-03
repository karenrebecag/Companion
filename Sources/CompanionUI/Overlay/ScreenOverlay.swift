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
package final class ScreenOverlays {
    private var panels: [ScreenOverlayPanel] = []
    private var observer: NSObjectProtocol?
    private let makeContent: (CGRect) -> AnyView

    package init(session: SessionModel, onFailure: @escaping (String) -> Void) {
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
    @State private var mode = ScreenGlow.Mode.off
    @State private var running = false
    @State private var stopTask: Task<Void, Never>?
    @State private var rippleStart: Date?
    @State private var rippleTask: Task<Void, Never>?

    var body: some View {
        let kind = session.projection.kind
        let next = ScreenGlow.mode(kind, enabled: glowEnabled, hands: handsHere, previous: mode)
        ZStack {
            glow
            // 16o-3: read when the hold starts; one display draws, not all.
            if PointerOrb.shows(kind: kind, reduceMotion: reduceMotion, screen: screenFrame,
                                cursor: NSEvent.mouseLocation) {
                PointerLayer(screenFrame: screenFrame)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: next, initial: true) { _, new in show(new) }
    }

    /// Incredible's container: the shader and the ring, turned with the glow, shrunk a hair
    /// while waiting, and held a moment before fading when it goes off.
    private var glow: some View {
        let off = mode == .off
        return ZStack {
            ScreenGlowMetalView(running: running, mode: mode, animated: !reduceMotion, onFailure: onFailure)
            if let rippleStart, !reduceMotion {
                ScreenGlowRipple(start: rippleStart)
            }
        }
        .scaleEffect(mode == .waiting ? ScreenGlow.waitingScale : 1)
        .animation(ScreenGlow.scaleAnimation(off: off, reduceMotion: reduceMotion), value: mode == .waiting)
        .opacity(off ? 0 : 1)
        .animation(ScreenGlow.opacityAnimation(off: off, reduceMotion: reduceMotion), value: off)
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

    private func show(_ next: ScreenGlow.Mode) {
        let lighting = mode == .off && next != .off
        mode = next
        stopTask?.cancel()
        guard next == .off else {
            running = true
            if lighting { ripple() }
            return
        }
        // The renderer stops once the light is gone: an idle Mac spends no GPU.
        let linger = ScreenGlow.linger(reduceMotion: reduceMotion)
        stopTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(linger)) } catch { return }
            // A relight can cancel after the sleep ends but before this runs.
            guard !Task.isCancelled else { return }
            running = false
        }
    }

    /// The ring plays once per lighting, then leaves the tree.
    private func ripple() {
        rippleTask?.cancel()
        guard !reduceMotion else { return }
        rippleStart = Date()
        rippleTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(ScreenGlow.Ripple.duration)) } catch { return }
            guard !Task.isCancelled else { return }
            rippleStart = nil
        }
    }
}

/// Two blurred rings that grow from the notch while the glow lights.
struct ScreenGlowRipple: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { context in
            let state = ScreenGlow.Ripple.state(at: context.date.timeIntervalSince(start))
            GeometryReader { proxy in
                let radius = ScreenGlow.Ripple.radius(in: proxy.size)
                ZStack {
                    ring(ScreenGlow.Ripple.outer, radius: radius)
                    ring(ScreenGlow.Ripple.inner, radius: radius)
                }
            }
            .blur(radius: ScreenGlow.Ripple.blur)
            .scaleEffect(state.scale, anchor: .top)
            .opacity(state.opacity)
        }
    }

    private func ring(_ stops: [ScreenGlow.Ripple.Stop], radius: CGFloat) -> some View {
        RadialGradient(
            stops: stops.map { Gradient.Stop(color: $0.swatch.color.opacity($0.alpha), location: $0.at) },
            center: .top, startRadius: 0, endRadius: radius)
    }
}
