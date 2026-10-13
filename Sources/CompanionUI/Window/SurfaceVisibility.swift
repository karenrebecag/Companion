import AppKit
import SwiftUI

extension EnvironmentValues {
    /// False while the window holding the view is off screen (ordered out,
    /// minimized, fully covered). Frame loops read it: an idle orb never
    /// settles on its own, so without it a hidden window kept drawing at
    /// display rate for nobody.
    @Entry var surfaceVisible = true
}

enum SurfaceVisibility {
    static func visible(_ occlusion: NSWindow.OcclusionState) -> Bool {
        occlusion.contains(.visible)
    }
}

/// Publishes the hosting window's occlusion to the subtree as `surfaceVisible`.
struct TracksSurfaceVisibility: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .environment(\.surfaceVisible, visible)
            .background(OcclusionReader(visible: $visible))
    }
}

private struct OcclusionReader: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> OcclusionView {
        let view = OcclusionView()
        view.onChange = report
        return view
    }

    func updateNSView(_ view: OcclusionView, context: Context) {
        view.onChange = report
    }

    private func report(_ shown: Bool) {
        guard visible != shown else { return }
        visible = shown
    }
}

final class OcclusionView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        // Moving to a window happens inside a SwiftUI update; writing state
        // there is undefined, so the first reading lands on the next turn.
        DispatchQueue.main.async { [weak self] in self?.report() }
    }

    private func report() {
        guard let window else { return }
        onChange?(SurfaceVisibility.visible(window.occlusionState))
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
