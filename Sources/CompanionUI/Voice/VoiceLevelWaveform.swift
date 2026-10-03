import CompanionCore
import SwiftUI

/// Incredible 0.2.36's island strip (firstRun-BOTAwJJ8.css, bytes 217745-218452).
enum VoiceLevelWaveformMetrics {
    static let height: CGFloat = 26
    static let maxWidth: CGFloat = 180
    /// The oldest columns fade in over this run from the left edge.
    static let fade: CGFloat = 56
    /// A column every 5 pt at 56 pt/s needs no more than this to scroll smoothly.
    static let frameInterval: TimeInterval = 1.0 / 30
    /// With motion reduced nothing scrolls, but a meter that holds still
    /// sends no change; this slow tick feeds the gate the held value, so the
    /// live column settles within half a hangover.
    static let settleInterval: TimeInterval = VoiceActivityGate.hangover / 2
}

/// The microphone as a scrolling timeline: bars while there is voice, dots
/// while there is not (spec gap 3, `WaveformHistory`).
struct VoiceLevelWaveform: View {
    /// Companion's mic meter (`VoiceLevels.mic`), not a decibel position.
    let amplitude: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    /// Optional so the island's frequent body passes do not build a tape each time.
    @State private var tape: WaveformTape?
    /// The tape is not observable; this redraws as soon as the level moves.
    @State private var revision = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? VoiceLevelWaveformMetrics.settleInterval
                                                              : VoiceLevelWaveformMetrics.frameInterval)) { timeline in
            // The tick's date is captured so every tick redraws; the clock the
            // tape counts on is the one onChange stamps frames with.
            Canvas { [revision, amplitude, tick = timeline.date] context, size in
                _ = (revision, tick)
                tape?.draw(now: ProcessInfo.processInfo.systemUptime, meter: amplitude, size: size,
                           scale: displayScale, scrolls: !reduceMotion, in: &context)
            }
        }
        .frame(idealWidth: VoiceLevelWaveformMetrics.maxWidth, maxWidth: VoiceLevelWaveformMetrics.maxWidth)
        .frame(height: VoiceLevelWaveformMetrics.height)
        // The status line beside it is greedy; the strip keeps its width first.
        .layoutPriority(1)
        .mask {
            HStack(spacing: Space.none) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: VoiceLevelWaveformMetrics.fade)
                Rectangle()
            }
        }
        .onChange(of: amplitude, initial: true) { _, value in
            let current = tape ?? WaveformTape()
            // The flag is worked out here, frame by frame with its level: watched
            // apart, it could land in a different column than the level it judged.
            current.ingest(meter: value, at: ProcessInfo.processInfo.systemUptime)
            if tape == nil { tape = current }
            revision &+= 1
        }
        .accessibilityHidden(true)
    }
}

/// Holds the history across frames. A class so the renderer can advance it
/// without invalidating the view on every frame. Internal, not private, so the
/// gallery can feed it frames on a stepped clock instead of wall time.
@MainActor
final class WaveformTape {
    var history = WaveformHistory()
    private var gate = VoiceActivityGate()
    private var lastTick: TimeInterval?

    /// Room noise must draw dots, as under Incredible's VAD; the history's own
    /// 0.08 level gate sits far under this mic's 0.12 floor.
    func ingest(meter: Double, at time: TimeInterval) {
        history.ingest(level: WaveformHistory.level(meter: meter), voiced: gate.voiced(meter: meter, at: time))
    }

    /// One timeline tick. onChange skips a meter that repeats, so a held
    /// value (speech clipped at 1.0, a stopped mic at 0) only reaches the gate
    /// here: it keeps a held voice re-armed and lets a held silence run out
    /// the hangover. A frame onChange already fed costs nothing twice: a
    /// column keeps its loudest level and ORs its flags. `now` is the clock
    /// `ingest` gets, so the hangover is counted on one clock.
    func frame(meter: Double, now: TimeInterval, width: Double, scrolls: Bool) -> [WaveformMark] {
        // Mutating while rendering is safe: a second render at the same
        // instant advances by zero and re-feeds a frame already counted.
        if scrolls {
            history.advance(elapsed: lastTick.map { now - $0 } ?? 0, width: width)
        }
        lastTick = scrolls ? now : nil
        // After the scroll, so the held frame lands in the live column and a
        // freshly pushed one never shows empty.
        ingest(meter: meter, at: now)
        return history.marks(width: width, scrolls: scrolls)
    }

    func draw(now: TimeInterval, meter: Double, size: CGSize, scale: CGFloat, scrolls: Bool,
              in context: inout GraphicsContext) {
        let width = Double(size.width)
        for mark in frame(meter: meter, now: now, width: width, scrolls: scrolls) {
            column(mark, height: Double(size.height), scale: scale, in: &context)
        }
    }

    private func column(_ mark: WaveformMark, height: Double, scale: CGFloat, in context: inout GraphicsContext) {
        // Snapped to device pixels, or the scroll shimmers as columns cross them.
        let x = (CGFloat(mark.x) * scale).rounded() / scale
        let middle = CGFloat(height) / 2
        switch WaveformHistory.column(mark.sample, gate: WaveformHistory.gate, height: height) {
        case .dot:
            let side = CGFloat(WaveformHistory.dotDiameter)
            let rect = CGRect(x: x - side / 2, y: middle - side / 2, width: side, height: side)
            context.fill(Path(ellipseIn: rect), with: .color(IslandInk.muted))
        case .bar(let barHeight):
            let width = CGFloat(WaveformHistory.barWidth)
            let tall = CGFloat(barHeight)
            let rect = CGRect(x: x - width / 2, y: middle - tall / 2, width: width, height: tall)
            context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(IslandInk.secondary))
        }
    }
}
