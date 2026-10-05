import CompanionCore
import Observation
import SwiftUI

// Incredible 0.2.36's hold companion (referencia local): while the key is held a pill rides
// the cursor, every new observation flashes on its orb, and what the user hands over stacks
// above it and is woven into the transcript.

/// The companion's clocks and amplitudes, Incredible's values.
enum HoldCompanionMotion {
    /// It stays this long after the key is released. Like Incredible's, nothing new is
    /// collected in that time: it only lets the last flash and chips finish.
    static let lingerMs = 1200
    static let flashMs = 1100
    static let appear = IslandMotion.Curve.timing(MotionCurve.standard, 0.18)
    /// The layer stays mounted this long after hiding, so the fade out can play.
    static let fadeMs = 180
    static let appearScale: CGFloat = 0.85
    static let chipIn = IslandMotion.Curve.timing(MotionCurve.bounce, 0.46)
    static let chipOut = IslandMotion.Curve.timing(MotionCurve.chipExit, 0.26)
    static let chipDrop: CGFloat = 18
    static let chipScale: CGFloat = 0.15
    static let slotStep: CGFloat = 31
    static let slotMove = IslandMotion.Curve.timing(MotionCurve.standard, 0.26)
    static let flashOn = IslandMotion.Curve.timing(MotionCurve.standard, 0.16)
    static let flashOff = IslandMotion.Curve.timing(MotionCurve.standard, 0.22)
    static let glyphIn = IslandMotion.Curve.timing(MotionCurve.bounce, 0.42)
    static let glyphOut = IslandMotion.Curve.timing(MotionCurve.standard, 0.26)
    /// The glyph travels 150 % of its own size and blurs on the way.
    static let glyphTravel: CGFloat = 1.5
    static let glyphBlur: CGFloat = 2.5
    /// The orb lands each flash with a small swell.
    static let land = IslandMotion.Curve.timing(MotionCurve.bounce, 0.36)
    static let landDelay = 0.06
    static let landScale: CGFloat = 1.09
    static let gulp = IslandMotion.Curve.timing(MotionCurve.bounce, 0.42)
    static let gulpDelay = 0.16

    /// Incredible keeps the companion under Reduce Motion and drops only its keyframes.
    static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }
}

/// Incredible's two orb keyframes. A CSS timing function eases each segment, so every
/// segment here carries the curve on its own share of the time.
enum HoldCompanionKeyframes {
    private static func segment(_ value: CGSize, _ share: Double, of curve: IslandMotion.Curve)
        -> LinearKeyframe<CGSize> {
        let points = MotionCurve.bounce
        return LinearKeyframe(value, duration: curve.duration * share, timingCurve: .bezier(
            startControlPoint: UnitPoint(x: points[0], y: points[1]),
            endControlPoint: UnitPoint(x: points[2], y: points[3])))
    }

    private static let rest = CGSize(width: 1, height: 1)

    /// Each flash lands with a swell to 1.09 and back.
    static var land: some Keyframes<CGSize> {
        let swell = CGSize(width: HoldCompanionMotion.landScale, height: HoldCompanionMotion.landScale)
        return KeyframeTrack {
            LinearKeyframe(rest, duration: HoldCompanionMotion.landDelay)
            segment(swell, 0.45, of: HoldCompanionMotion.land)
            segment(rest, 0.55, of: HoldCompanionMotion.land)
        }
    }

    /// Swallowing a leaving chip: wide and short, then narrow and tall, then round.
    static var gulp: some Keyframes<CGSize> {
        KeyframeTrack {
            LinearKeyframe(rest, duration: HoldCompanionMotion.gulpDelay)
            segment(CGSize(width: 1.22, height: 0.86), 0.35, of: HoldCompanionMotion.gulp)
            segment(CGSize(width: 0.92, height: 1.08), 0.30, of: HoldCompanionMotion.gulp)
            segment(rest, 0.35, of: HoldCompanionMotion.gulp)
        }
    }
}

enum HoldCompanionMetrics {
    /// Where a chip grows from, relative to its own bottom-left: the orb below it.
    nonisolated static let chipOrigin = CGPoint(x: 16, y: 36)
    static let pillHeight: CGFloat = 46
    static let pillInset: CGFloat = 7
    static let orb: CGFloat = 32
    static let orbCenter = CGPoint(x: pillInset + orb / 2, y: pillHeight / 2)
    /// The stack's bottom edge sits this far above the pill's bottom.
    static let stackLift: CGFloat = 50
    static let chipHeight: CGFloat = 26
    static let chipLead: CGFloat = 7
    static let chipTrail: CGFloat = 11
    static let chipGap: CGFloat = 6
    static let chipMaxWidth: CGFloat = 280
    /// What is left for the label once the icon, the gap and the padding are in.
    static let chipTextMax = chipMaxWidth - chipLead - chipTrail - chipIcon - chipGap
    static let chipIcon: CGFloat = 14
    static let glyph: CGFloat = 16
    static let iconOpacity = 0.85
    static let face = Swatch("17171A")
    static let shadowRadius: CGFloat = 10
    static let shadowY: CGFloat = 3
    static let shadowOpacity = 0.28
}

/// What the companion shows, as a value: each change returns a new state.
struct HoldCompanionState: Equatable {
    private(set) var visible = false
    /// Still on screen while it fades out after `visible` went false.
    private(set) var mounted = false
    private(set) var flash: HoldItem?
    private(set) var flashSeq = 0
    private(set) var stack: [HoldStackEntry] = []
    private(set) var marks: [Int: [String]] = [:]
    /// The clock the stack was last read at: a chip turns to leaving on a tick, not on new data.
    private(set) var clockMs = 0
    private var seen: Set<String> = []
    private var lastFlashTMs: Int?
    private var generation: Int?

    func started() -> HoldCompanionState {
        var next = cleared()
        next.generation = nil
        next.visible = true
        next.mounted = true
        return next
    }

    func hidden() -> HoldCompanionState {
        var next = self
        next.visible = false
        next.flash = nil
        return next
    }

    /// Once the fade out is over the layer can go; never while it is still shown.
    func unmounted() -> HoldCompanionState {
        guard !visible else { return self }
        var next = self
        next.mounted = false
        return next
    }

    func dictating() -> HoldCompanionState {
        var next = cleared()
        next.generation = nil
        return next
    }

    /// The whole list of items the host has seen in this generation; only new ones count.
    func receiving(_ items: [HoldItem], generation: Int, nowMs: Int, words: Int,
                   listening: Bool) -> HoldCompanionState {
        guard listening else { return self }
        var next = self
        next.clockMs = nowMs
        if next.generation != generation {
            if next.generation != nil { next = next.cleared() }
            next.generation = generation
        }
        for item in items where !next.seen.contains(item.id) {
            next.seen.insert(item.id)
            next = next.taking(item, nowMs: nowMs, words: words)
        }
        return next
    }

    func flashCleared(seq: Int) -> HoldCompanionState {
        guard seq == flashSeq else { return self }
        var next = self
        next.flash = nil
        return next
    }

    func pruned(nowMs: Int) -> HoldCompanionState {
        var next = self
        next.clockMs = nowMs
        next.stack = HoldStack.prune(stack, nowMs: nowMs)
        return next
    }

    /// The next moment an entry starts leaving or is gone.
    func nextWakeMs(nowMs: Int) -> Int? {
        stack.flatMap { [$0.atMs + HoldStack.leaveAfterMs, $0.atMs + HoldStack.dropAfterMs] }
            .filter { $0 > nowMs }.min()
    }

    func woven(_ partial: String) -> String {
        HoldCollect.weave(partial, marks: marks)
    }

    private func taking(_ full: HoldItem, nowMs: Int, words: Int) -> HoldCompanionState {
        // The view shows a glyph and a label; what was typed and the full address stay out.
        var item = full
        item.detail = nil
        item.siteURL = nil
        var next = self
        if lastFlashTMs.map({ item.tMs >= $0 }) ?? true {
            next.flash = item
            next.flashSeq += 1
            next.lastFlashTMs = item.tMs
        }
        guard item.kind.stacks else { return next }
        next.marks = HoldCollect.mark(next.marks, item, atWord: words)
        next.stack = HoldStack.push(next.stack, item, atMs: nowMs)
        return next
    }

    private func cleared() -> HoldCompanionState {
        var next = HoldCompanionState()
        next.visible = visible
        next.mounted = mounted
        next.generation = generation
        next.clockMs = clockMs
        return next
    }
}

/// Owns the companion's state and its timers; one for every display.
@MainActor @Observable
package final class HoldCompanionModel {
    private(set) var state = HoldCompanionState()
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var stackTask: Task<Void, Never>?
    @ObservationIgnored private var listening = false
    @ObservationIgnored private let now: @MainActor () -> Int
    @ObservationIgnored private let sleep: @MainActor (Int) async throws -> Void

    package init(now: @escaping @MainActor () -> Int = { HoldCompanionModel.uptimeMs() },
                 sleep: @escaping @MainActor (Int) async throws -> Void = {
                     try await Task.sleep(for: .milliseconds($0))
                 }) {
        self.now = now
        self.sleep = sleep
    }

    package func listening(_ held: Bool) {
        guard held != listening else { return }
        listening = held
        hideTask?.cancel()
        if held {
            state = state.started()
            return
        }
        hideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await sleep(HoldCompanionMotion.lingerMs) } catch { return }
            // A hold that started while this slept owns the companion now.
            guard !Task.isCancelled, !listening else { return }
            state = state.hidden()
            do { try await sleep(HoldCompanionMotion.fadeMs) } catch { return }
            guard !Task.isCancelled, !listening else { return }
            state = state.unmounted()
        }
    }

    package func dictating() {
        state = state.dictating()
    }

    /// One batch from the hold observer; `words` is how far the transcript has got.
    package func observe(_ batch: HoldObservationBatch, words: Int) {
        receive(HoldCollect.items(from: batch.events), generation: batch.generation, words: words)
    }

    package func receive(_ items: [HoldItem], generation: Int, words: Int) {
        let before = state.flashSeq
        state = state.receiving(items, generation: generation, nowMs: now(), words: words,
                                listening: listening)
        if state.flashSeq != before { scheduleFlashClear(seq: state.flashSeq) }
        scheduleStackWake()
    }

    private func scheduleFlashClear(seq: Int) {
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await sleep(HoldCompanionMotion.flashMs) } catch { return }
            state = state.flashCleared(seq: seq)
        }
    }

    private func scheduleStackWake() {
        stackTask?.cancel()
        let start = now()
        guard let wake = state.nextWakeMs(nowMs: start) else { return }
        stackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await sleep(wake - start) } catch { return }
            state = state.pruned(nowMs: now())
            scheduleStackWake()
        }
    }

    package static func uptimeMs() -> Int {
        Int(ProcessInfo.processInfo.systemUptime * 1000)
    }
}
