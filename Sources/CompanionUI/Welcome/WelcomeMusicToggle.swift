import AppKit
import SwiftUI

/// The welcome's music switch, drawn from Incredible's `.fr-music`
/// (styles-CTdsYdwA.css @25479-26254): a 40 pt frosted square at the window's
/// bottom-right whose two icons crossfade instead of swapping.
struct WelcomeMusicToggle: View {
    let playing: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private static let size: CGFloat = 40
    private static let icon: CGFloat = 18
    private static let restWash = 0.55
    private static let hoverWash = 0.8
    private static let ring = 0.5
    private static let pressedScale = 0.96
    /// The hidden icon sits at scale .25 and blur 4, as the CSS leaves it.
    private static let hiddenScale = 0.25
    private static let hiddenBlur: CGFloat = 4

    var body: some View {
        Button(action: action) {
            ZStack {
                glyph(Self.iconName(playing: true), visible: playing)
                glyph(Self.iconName(playing: false), visible: !playing)
            }
            .foregroundStyle(Semantic.mutedForeground)
            .frame(width: Self.size, height: Self.size)
            .background(shape.fill(.ultraThinMaterial))
            // Incredible's .fr-music wash is white at .55 / .8 on hover.
            .background(shape.fill(Neutral.white.color.opacity(hovering ? Self.hoverWash : Self.restWash)))
            .overlay(shape.strokeBorder(Neutral.white.color.opacity(Self.ring), lineWidth: 1))
            // The CSS pair `0 1px 2px #0000000a, 0 6px 16px -4px #0000001a`;
            // SwiftUI radius is half the CSS blur, and the negative spread has no equivalent.
            .shadow(color: Neutral.black.color.opacity(0.04), radius: 1, y: 1)
            .shadow(color: Neutral.black.color.opacity(0.1), radius: 8, y: 6)
            .contentShape(shape)
        }
        .buttonStyle(PressScale(scale: Self.pressedScale, reduceMotion: reduceMotion))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : MotionCurve.animation(MotionCurve.standard, MotionTime.fast), value: hovering)
        .help(Localized.string("welcome.music"))
        .accessibilityLabel(Localized.string("welcome.music"))
        .accessibilityValue(Localized.string(Self.accessibilityValueKey(playing: playing)))
        .accessibilityAddTraits(.isToggle)
    }

    static func accessibilityValueKey(playing: Bool) -> String {
        playing ? "welcome.music.on" : "welcome.music.off"
    }

    static func iconName(playing: Bool) -> String {
        playing ? "speaker.wave.2" : "speaker.slash"
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.control) }

    private func glyph(_ name: String, visible: Bool) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: Self.icon, height: Self.icon)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : Self.hiddenScale)
            .blur(radius: visible ? 0 : Self.hiddenBlur)
            .animation(
                reduceMotion ? nil : MotionCurve.animation(MotionCurve.standard, MotionTime.base),
                value: visible)
    }
}

private struct PressScale: ButtonStyle {
    let scale: Double
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(
                reduceMotion ? nil : MotionCurve.animation(MotionCurve.easeOut, MotionTime.base),
                value: configuration.isPressed)
    }
}

/// Reports whether the hosting window is actually on screen. The welcome
/// window is reused (never released, the app survives its last window), so
/// close, Cmd-W, minimize and orderOut never fire `onDisappear`; only the
/// window's own notifications say the music has no visible control.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    static func windowShows(isVisible: Bool, miniaturized: Bool, occludedVisible: Bool) -> Bool {
        isVisible && !miniaturized && occludedVisible
    }

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else {
                onChange(false)
                return
            }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            tokens = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.report(window)
                }
            }
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in self?.onChange(false) })
            report(window)
        }

        private func report(_ window: NSWindow) {
            onChange(WindowVisibilityReader.windowShows(
                isVisible: window.isVisible, miniaturized: window.isMiniaturized,
                occludedVisible: window.occlusionState.contains(.visible)))
        }

        private func stopObserving() {
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            tokens = []
        }

        deinit { stopObserving() }
    }
}
