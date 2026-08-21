import RiveRuntime
import SwiftUI

/// The prototype's mascot. The .riv carries its own pointer listeners, so the
/// click that makes it react needs no app code; what the file cannot know is
/// the app's state, and that travels through the bound flags.
@MainActor
final class MascotBridge: ObservableObject {
    let rive = RiveViewModel(
        fileName: "hello",
        stateMachineName: "State Machine_Main",
        fit: .contain,
        autoPlay: true,
        loadCdn: false)

    /// The runtime needs a strong reference to the bound instance.
    private var instance: RiveDataBindingViewModel.Instance?

    init() {
        rive.riveModel?.enableAutoBind { [weak self] instance in
            self?.instance = instance
        }
    }

    /// Trailing spaces in the paths are in the .riv itself, not a typo.
    func apply(excited: Bool) {
        guard let instance else { return }
        var changed = false
        // The sales-pitch mode stays off by force on every sync: the file's
        // own listeners can turn it on too.
        if let flag = instance.booleanProperty(fromPath: "Ai sell "), flag.value {
            flag.value = false
            changed = true
        }
        if let flag = instance.booleanProperty(fromPath: "Excited "),
           flag.value != excited {
            flag.value = excited
            changed = true
        }
        // rive-ios #383: a data-binding change does not wake a settled state
        // machine on its own.
        if changed { rive.play() }
    }
}

/// Artboard is 475x453; keeping its ratio avoids dead air inside the hero.
private let artboardAspect = 475.0 / 453.0

public struct MascotView: View {
    private let excited: Bool
    @Environment(\.colorScheme) private var scheme
    @StateObject private var bridge = MascotBridge()

    public init(excited: Bool) {
        self.excited = excited
    }

    public var body: some View {
        bridge.rive.view()
            .aspectRatio(artboardAspect, contentMode: .fit)
            // The character is black line art: in dark mode it would vanish.
            // Inverting leaves the alpha alone, so it just turns white.
            .colorInvert(scheme == .dark)
            .onAppear { bridge.apply(excited: excited) }
            .onChange(of: excited) { _, value in bridge.apply(excited: value) }
    }
}

private extension View {
    @ViewBuilder
    func colorInvert(_ active: Bool) -> some View {
        if active { colorInvert() } else { self }
    }
}
