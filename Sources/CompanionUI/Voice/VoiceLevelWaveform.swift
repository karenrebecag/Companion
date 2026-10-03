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
    /// The tape is not observable; this redraws a paused timeline when the level moves.
    @State private var revision = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: VoiceLevelWaveformMetrics.frameInterval, paused: reduceMotion)) { timeline in
            Canvas { [revision] context, size in
                _ = revision
                tape?.draw(at: timeline.date, size: size, scale: displayScale,
                           scrolls: !reduceMotion, in: &context)
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
            // HACK: no voice detector reaches the UI yet, so the gate decides.
            // Pass its flag here once the transcriber port exposes `voiced` (gap 4).
            current.history.ingest(level: WaveformHistory.level(meter: value))
            if tape == nil { tape = current }
            revision &+= 1
        }
        .accessibilityHidden(true)
    }
}

/// Holds the history across frames. A class so the renderer can advance it
/// without invalidating the view on every frame.
@MainActor
private final class WaveformTape {
    var history = WaveformHistory()
    private var lastFrame: Date?

    func draw(at date: Date, size: CGSize, scale: CGFloat, scrolls: Bool, in context: inout GraphicsContext) {
        let width = Double(size.width)
        // Mutating while rendering is safe: a second render of the same date
        // advances by zero, so SwiftUI may redraw a frame as often as it likes.
        if scrolls {
            history.advance(elapsed: lastFrame.map { date.timeIntervalSince($0) } ?? 0, width: width)
        }
        lastFrame = scrolls ? date : nil
        for mark in history.marks(width: width, scrolls: scrolls) {
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
