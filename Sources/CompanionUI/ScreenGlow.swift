import CompanionCore
import Foundation

// Wave 16o-2: Incredible's screen glow while it listens, measured in
// docs/research/incredible-fn-glow-pointer.md. The values are theirs; the
// shader that draws it is ours (ScreenGlowShader).

public enum ScreenGlow {
    /// The wheel of four hues that turns around the screen's centre.
    public static let colors = [Swatch("1C69F0"), Swatch("0AB4AF"), Swatch("8C46E6"), Swatch("1496DC")]
    /// Opacity ceiling while listening; waiting on an answer halves it.
    public static let listening = 0.5
    public static let waiting = 0.25
    public static let fadeIn = 0.26
    public static let fadeOut = 0.9
    /// Points inward from each edge, before the waves move it.
    public static let reach: CGFloat = 120
    /// Seconds for one full turn of the wheel.
    public static let period = 71.0

    /// Speaking is the answer arriving: the edges have done their job.
    /// `hands`: an agent is acting through the bridge right now (Wave 20b:
    /// lit per executed call and dark 4 s after the last, on the target's
    /// display only — not while a session merely stays open). At rest it is
    /// the one full-screen mark that someone else is driving; during the
    /// user's own turn the voice levels win unchanged.
    public static func target(_ kind: SessionKind, enabled: Bool, hands: Bool = false) -> Double {
        guard enabled else { return 0 }
        switch kind {
        case .listening: return listening
        case .processing(.pending), .processing(.thinking),
             .processing(.toolExecuting), .processing(.subAgentRunning): return waiting
        case .idle, .hover: return hands ? waiting : 0
        case .processing(.speaking), .processing(.completed): return 0
        }
    }

    /// AX frames are global with the origin at the primary display's top-left;
    /// NSScreen's have it at the primary's bottom-left, so y flips around the
    /// primary's height (a display below the primary ends up negative).
    public static func appKitFrame(fromAX frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The one display the hands aura belongs on: where most of the target
    /// window sits (`target` in AppKit space), else where the cursor is
    /// (Incredible's criterion). Ties go to the first display so exactly
    /// one panel ever lights.
    public static func handsOnScreen(
        screenFrame: CGRect, screens: [CGRect], target: CGRect?, cursor: CGPoint
    ) -> Bool {
        if let target {
            let overlaps = screens.map { area(of: $0.intersection(target)) }
            if let best = overlaps.max(), best > 0, let index = overlaps.firstIndex(of: best) {
                return screens[index] == screenFrame
            }
        }
        return screens.first { $0.contains(cursor) } == screenFrame
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    /// Rising is arriving; anything lower is leaving, at the slow pace.
    public static func fade(from: Double, to: Double) -> Double {
        to > from ? fadeIn : fadeOut
    }

    /// Where the wheel stands `time` seconds in. Reduce Motion holds it still.
    public static func rotation(at time: Double, phase: Double, animated: Bool = true) -> Double {
        let turn = 2 * Double.pi
        guard animated else { return phase }
        return (phase + turn * time / period).truncatingRemainder(dividingBy: turn)
    }
}

/// Incredible's `screen_glow_enabled`: on unless the user turned it off.
public enum ScreenGlowPreference {
    static let key = "companion.screenGlow.enabled"

    public static func enabled(in store: UserDefaults = .standard) -> Bool {
        store.object(forKey: key) == nil ? true : store.bool(forKey: key)
    }

    public static func set(_ enabled: Bool, in store: UserDefaults = .standard) {
        store.set(enabled, forKey: key)
    }
}
