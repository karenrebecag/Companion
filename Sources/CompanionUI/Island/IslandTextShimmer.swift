import SwiftUI

/// Arc's text-shimmer on the island: a bell-shaped band in the text's own
/// color sweeps over a muted base, rests between passes, and when the work
/// ends the base settles to solid instead of cutting. Reduce Motion holds the
/// muted base while active and settles without the sweep.
struct IslandTextShimmer: ViewModifier {
    let active: Bool
    /// Offscreen renders pin the sweep and the settle.
    var frozen: (sweep: Double, settle: Double)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toggledAt: Date?
    @State private var startedAt = Date()
    @State private var resting = false

    func body(content: Content) -> some View {
        Group {
            if let frozen {
                painted(content, sweep: frozen.sweep, settle: frozen.settle)
            } else if !active && (resting || toggledAt == nil) {
                content
            } else if reduceMotion {
                painted(content, sweep: 0, settle: active ? 0 : 1)
            } else {
                TimelineView(.animation(minimumInterval: ThinkingOrb.frameInterval)) { timeline in
                    let since = toggledAt.map { timeline.date.timeIntervalSince($0) } ?? .infinity
                    painted(content,
                            sweep: TextShimmerMotion.sweep(timeline.date.timeIntervalSince(startedAt)),
                            settle: TextShimmerMotion.settle(active: active, sinceToggle: since))
                }
            }
        }
        .onChange(of: active) {
            toggledAt = Date()
            resting = false
            if active { startedAt = Date() }
        }
        .task(id: toggledAt) {
            guard !active, toggledAt != nil else { return }
            do {
                try await Task.sleep(for: .seconds(TextShimmerMotion.settleOut))
            } catch {
                // Work resumed before the text settled; the new state owns the clock.
                return
            }
            resting = true
        }
        .accessibilityAddTraits(active ? .updatesFrequently : [])
    }

    private func painted(_ content: Content, sweep: Double, settle: Double) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    band(sweep: sweep, settle: settle, width: proxy.size.width)
                }
                .blendMode(.sourceAtop)
            }
            .compositingGroup()
    }

    private func band(sweep: Double, settle: Double, width: CGFloat) -> LinearGradient {
        let ends = TextShimmerMotion.bandEnds(sweep: sweep, width: Double(width), em: Double(TypeScale.apply(TypeSize.base)))
        let base = IslandShimmerInk.base.mixed(toward: .highlight, settle)
        let stops = TextShimmerMotion.falloff.map { stop in
            Gradient.Stop(color: base.mixed(toward: .highlight, stop.strength).color, location: (stop.offset + 1) / 2)
        }
        return LinearGradient(stops: stops, startPoint: UnitPoint(x: ends.start, y: 0.5),
                              endPoint: UnitPoint(x: ends.end, y: 0.5))
    }
}

/// Arc's two shimmer inks: the text's color, and a base 12 % of the way from muted toward it.
struct IslandShimmerInk: Equatable {
    let r, g, b: Double

    static let highlight = IslandShimmerInk(ArcTone.foreground)
    static let base = IslandShimmerInk(ArcTone.mix(ArcTone.foreground, 0.12, over: ArcTone.textMuted))

    init(_ swatch: Swatch) {
        let c = swatch.ns.usingColorSpace(.sRGB) ?? .white
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(toward other: IslandShimmerInk, _ share: Double) -> IslandShimmerInk {
        let t = OrbMath.clamp(share)
        return IslandShimmerInk(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

extension View {
    func islandTextShimmer(active: Bool) -> some View {
        modifier(IslandTextShimmer(active: active))
    }
}
