import Foundation

/// What one column of the voice waveform draws.
package enum WaveformColumn: Sendable, Equatable {
    /// A column without voice: the line keeps moving so silence still reads
    /// as "I am listening", not as a frozen meter.
    case dot
    case bar(height: Double)
}

/// One column to draw: where its center sits and the sample it shows.
package struct WaveformMark: Sendable, Equatable {
    package let x: Double
    package let sample: Double

    package init(x: Double, sample: Double) {
        self.x = x
        self.sample = sample
    }
}

/// The island's voice waveform as Incredible 0.2.36 draws it: a history of
/// columns scrolling left, each one the loudest frame it saw, scaled against
/// a slowly decaying peak so a quiet voice and a loud one both fill the strip.
/// Levels are positions on a 60 dB range (0 is -60 dB, 1 is full scale).
package struct WaveformHistory: Sendable {
    package static let decibelRange = 60.0
    /// The peak never drops under this amplitude, or room noise would be
    /// stretched to full height after a pause.
    package static let peakFloor = 0.08
    package static let peakDecay = 0.991
    /// How far the peak may climb in one column, so a click does not
    /// flatten the next second of speech.
    package static let peakGrowth = 2.0
    /// Decibels under the peak that still draw taller than the gate.
    package static let window = 22.0
    /// Without a voice flag, a level at or under this is silence.
    package static let gate = 0.08
    package static let columnStep = 5.0
    package static let pointsPerSecond = 56.0
    package static let barWidth = 2.5
    package static let dotDiameter = barWidth
    /// A display that stalled (sleep, a hidden window) resumes with one
    /// second of scroll, not with the whole gap replayed column by column.
    package static let longestStep = 1.0
    /// MicCapture reports RMS x 6 clipped at 1; the waveform needs the RMS itself.
    package static let micMeterGain = 6.0

    package private(set) var samples: [Double] = []
    package private(set) var carry = 0.0
    package private(set) var reference = peakFloor
    private var peak = 0.0
    private var latest = 0.0
    private var voiced = false
    /// Once a voice detector speaks, its flag replaces the gate for good.
    private var hasDetector = false

    package init() {}

    package static func amplitude(level: Double) -> Double {
        pow(10, (level * decibelRange - decibelRange) / 20)
    }

    package static func level(amplitude: Double) -> Double {
        guard amplitude > 0 else { return 0 }
        return min(max((20 * log10(amplitude) + decibelRange) / decibelRange, 0), 1)
    }

    /// Incredible's native level is a dBFS position, which is what its gate
    /// and window are tuned on; Companion's meter is undone to the same scale.
    package static func level(meter: Double) -> Double {
        level(amplitude: meter / micMeterGain)
    }

    package static func maxColumns(width: Double) -> Int {
        max(0, Int((width / columnStep).rounded(.down)))
    }

    /// The loudest frame since the last column, or the latest when none came.
    package var current: Double { max(peak, latest) }

    /// `voiced` is the seam for a voice detector; nil leaves the gate deciding.
    package mutating func ingest(level raw: Double, voiced flag: Bool? = nil) {
        // As Incredible's audio source does: a broken frame is silence, not a poisoned peak.
        let level = raw.isFinite ? min(max(raw, 0), 1) : 0
        latest = level
        peak = max(peak, level)
        if let flag {
            hasDetector = true
            voiced = voiced || flag
        }
    }

    package func isVoiced(_ level: Double) -> Bool {
        hasDetector ? voiced : level > Self.gate
    }

    /// 0 for silence; otherwise a height in (gate, 1] by distance to the peak.
    package func sample(for level: Double) -> Double {
        guard isVoiced(level) else { return 0 }
        let amplitude = Self.amplitude(level: level)
        let decibels = 20 * log10(max(amplitude, 1e-6) / max(reference, Self.peakFloor))
        let position = min(max((decibels + Self.window) / Self.window, 0), 1)
        return Self.gate + position * (1 - Self.gate)
    }

    package mutating func advance(elapsed: Double, width: Double) {
        // NaN fails every comparison and would freeze the carry for good.
        let step = elapsed.isNaN ? 0 : min(max(elapsed, 0), Self.longestStep)
        carry += step * Self.pointsPerSecond
        let limit = Self.maxColumns(width: width)
        while carry >= Self.columnStep {
            carry -= Self.columnStep
            push(current, limit: limit)
        }
    }

    private mutating func push(_ level: Double, limit: Int) {
        if isVoiced(level) {
            reference = max(Self.peakFloor,
                            min(Self.amplitude(level: level), reference * Self.peakGrowth),
                            reference * Self.peakDecay)
        } else {
            reference = max(Self.peakFloor, reference * Self.peakDecay)
        }
        samples.append(sample(for: level))
        peak = 0
        voiced = false
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    /// What a frame draws: the history only while it scrolls, then the live
    /// column, which follows the voice even when motion is reduced.
    package func marks(width: Double, scrolls: Bool) -> [WaveformMark] {
        var marks: [WaveformMark] = []
        if scrolls {
            for index in samples.indices {
                let x = Self.x(index: index, count: samples.count, width: width, carry: carry)
                marks.append(WaveformMark(x: x, sample: samples[index]))
            }
        }
        marks.append(WaveformMark(x: Self.headX(width: width), sample: sample(for: current)))
        return marks.filter { $0.x >= -Self.barWidth }
    }

    package static func column(_ sample: Double, gate: Double, height: Double) -> WaveformColumn {
        guard sample > gate else { return .dot }
        let position = (sample - gate) / (1 - gate)
        return .bar(height: max(barWidth + 2, pow(position, 0.85) * (height - 4)))
    }

    /// The live column sits half a step in from the right edge.
    package static func headX(width: Double) -> Double {
        width - columnStep / 2
    }

    /// Older columns step left from the head and slide with the carry, so
    /// the scroll is continuous between columns.
    package static func x(index: Int, count: Int, width: Double, carry: Double) -> Double {
        headX(width: width) - Double(count - 1 - index) * columnStep - carry
    }
}
