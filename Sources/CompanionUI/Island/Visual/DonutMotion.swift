import Foundation

/// One animated number as a closed-form spring: where it is and how fast it
/// moves at any instant, without a frame loop. Retargeting starts the new
/// spring from the current position and velocity, which is what lets an
/// interrupted morph carry on instead of stopping dead (Arc's motion values).
struct DonutSpring: Equatable {
    let origin: Double
    let initialVelocity: Double
    let target: Double
    let startedAt: Double
    /// Seconds the value holds still before it leaves (the sweep's stagger).
    let delay: Double
    let spring: MotionSpring

    static func resting(_ value: Double) -> DonutSpring {
        DonutSpring(origin: value, initialVelocity: 0, target: value, startedAt: 0, delay: 0,
                    spring: IslandVisualMetrics.donutSettle)
    }

    func retargeted(to target: Double, at now: Double, spring: MotionSpring, delay: Double = 0) -> DonutSpring {
        DonutSpring(origin: value(at: now), initialVelocity: velocity(at: now), target: target,
                    startedAt: now, delay: delay, spring: spring)
    }

    func value(at now: Double) -> Double {
        let elapsed = now - startedAt - delay
        guard elapsed > 0 else { return origin }
        if isSettled(at: now) { return target }
        return target + motion(elapsed).position
    }

    func velocity(at now: Double) -> Double {
        let elapsed = now - startedAt - delay
        if elapsed < 0 { return 0 }
        if isSettled(at: now) { return 0 }
        return motion(elapsed).speed
    }

    func isSettled(at now: Double) -> Bool {
        let elapsed = now - startedAt - delay
        let start = origin - target
        if start == 0, initialVelocity == 0 { return true }
        guard elapsed >= 0 else { return false }
        let state = motion(elapsed)
        return abs(state.position) < tolerance && abs(state.speed) < tolerance * 10
    }

    /// When it comes to rest, sampled at 120 Hz; capped so a broken spring
    /// cannot keep the ring's clock running.
    var settleTime: Double {
        let begin = startedAt + max(delay, 0)
        let step = 1.0 / 120
        for tick in 0 ... 1200 where isSettled(at: begin + Double(tick) * step) {
            return begin + Double(tick) * step
        }
        return begin + 10
    }

    /// Rest is relative to the travel, so a total in the thousands and a
    /// quarter turn of the ring settle on the same terms.
    private var tolerance: Double { max(abs(origin - target) * 0.001, 1e-6) }

    /// Offset from the target and its speed, `elapsed` seconds in.
    private func motion(_ elapsed: Double) -> (position: Double, speed: Double) {
        let omega = 2 * Double.pi / max(spring.response, 1e-3)
        let zeta = spring.damping
        let start = origin - target
        let v0 = initialVelocity
        if zeta >= 1 {
            // Critically damped: the springs of the ring never bounce.
            let b = v0 + omega * start
            let decay = exp(-omega * elapsed)
            return ((start + b * elapsed) * decay, (v0 - omega * b * elapsed) * decay)
        }
        let damped = omega * (1 - zeta * zeta).squareRoot()
        let c = (v0 + zeta * omega * start) / damped
        let decay = exp(-zeta * omega * elapsed)
        let cosine = cos(damped * elapsed)
        let sine = sin(damped * elapsed)
        let position = decay * (start * cosine + c * sine)
        let speed = decay * (-zeta * omega * (start * cosine + c * sine) + damped * (c * cosine - start * sine))
        return (position, speed)
    }
}

/// Every segment's edges and the centre total as springs on one clock, so
/// the ring is a pure function of time: the view only asks for a frame.
/// Segments keep their key and order and are never rebuilt mid-morph.
struct DonutMotion: Equatable {
    struct Frame: Equatable {
        let slice: DonutLayout.Slice
        let arc: DonutLayout.Arc
    }

    /// Everything drawn, leaving segments included until they have closed.
    let order: [DonutLayout.Slice]
    /// The dataset being shown; a key in `order` but not here is leaving.
    let current: [DonutLayout.Slice]
    let starts: [String: DonutSpring]
    let ends: [String: DonutSpring]
    let totalSpring: DonutSpring

    /// At rest on its layout: what a still render (a snapshot, reduced motion) shows.
    init(slices: [DonutLayout.Slice]) {
        let arcs = DonutLayout.arcs(slices)
        self.init(order: slices, current: slices,
                  starts: arcs.mapValues { DonutSpring.resting($0.start) },
                  ends: arcs.mapValues { DonutSpring.resting($0.end) },
                  totalSpring: .resting(slices.reduce(0) { $0 + $1.value }))
    }

    private init(order: [DonutLayout.Slice], current: [DonutLayout.Slice], starts: [String: DonutSpring],
                 ends: [String: DonutSpring], totalSpring: DonutSpring) {
        self.order = order
        self.current = current
        self.starts = starts
        self.ends = ends
        self.totalSpring = totalSpring
    }

    /// The first appearance: every segment leaves the top together and each
    /// trailing edge follows a beat behind the one before.
    func sweeping(at now: Double) -> DonutMotion {
        let arcs = DonutLayout.arcs(current)
        var newStarts: [String: DonutSpring] = [:]
        var newEnds: [String: DonutSpring] = [:]
        for (index, slice) in current.enumerated() {
            let arc = arcs[slice.key] ?? DonutLayout.Arc(start: 0, end: 0)
            newStarts[slice.key] = DonutSpring.resting(0)
                .retargeted(to: arc.start, at: now, spring: IslandVisualMetrics.donutReveal)
            newEnds[slice.key] = DonutSpring.resting(0)
                .retargeted(to: arc.end, at: now, spring: IslandVisualMetrics.donutReveal,
                            delay: DonutLayout.sweepDelay(index: index))
        }
        return DonutMotion(order: current, current: current, starts: newStarts, ends: newEnds,
                           totalSpring: totalSpring)
    }

    /// New data moves every arc from wherever it is on screen. A new segment
    /// opens from the edge of the one before it as it is right now; a
    /// leaving one closes and drops out on the next change after it has.
    func updated(to next: [DonutLayout.Slice], at now: Double, reduced: Bool) -> DonutMotion {
        let live = order.filter { slice in
            current.contains { $0.key == slice.key } || !isClosed(slice.key, at: now)
        }
        let drawn = DonutLayout.drawn(previous: live, next: next)
        let goal = DonutLayout.targets(drawn: drawn, next: next)
        let newTotal = next.reduce(0) { $0 + $1.value }
        if reduced {
            let arcs = DonutLayout.arcs(next)
            return DonutMotion(order: next, current: next,
                               starts: arcs.mapValues { DonutSpring.resting($0.start) },
                               ends: arcs.mapValues { DonutSpring.resting($0.end) },
                               totalSpring: .resting(newTotal))
        }
        var newStarts: [String: DonutSpring] = [:]
        var newEnds: [String: DonutSpring] = [:]
        let settle = IslandVisualMetrics.donutSettle
        for (index, slice) in drawn.enumerated() {
            let to = goal[slice.key] ?? DonutLayout.Arc(start: 0, end: 0)
            let opening = drawn[..<index].reversed().compactMap { ends[$0.key] }.first?.value(at: now) ?? 0
            let start = starts[slice.key] ?? .resting(opening)
            let end = ends[slice.key] ?? .resting(opening)
            newStarts[slice.key] = start.retargeted(to: to.start, at: now, spring: settle)
            newEnds[slice.key] = end.retargeted(to: to.end, at: now, spring: settle)
        }
        return DonutMotion(order: drawn, current: next, starts: newStarts, ends: newEnds,
                           totalSpring: totalSpring.retargeted(to: newTotal, at: now,
                                                               spring: IslandVisualMetrics.donutCount))
    }

    func arcs(at now: Double) -> [Frame] {
        order.map { slice in
            Frame(slice: slice, arc: DonutLayout.Arc(start: starts[slice.key]?.value(at: now) ?? 0,
                                                     end: ends[slice.key]?.value(at: now) ?? 0))
        }
    }

    func total(at now: Double) -> Double { totalSpring.value(at: now) }

    var finalTotal: Double { totalSpring.target }

    func isSettled(at now: Double) -> Bool {
        totalSpring.isSettled(at: now)
            && starts.values.allSatisfy { $0.isSettled(at: now) }
            && ends.values.allSatisfy { $0.isSettled(at: now) }
    }

    /// The moment the last spring comes to rest, so the view can stop its clock.
    var settleTime: Double {
        ([totalSpring.settleTime] + starts.values.map(\.settleTime) + ends.values.map(\.settleTime)).max() ?? 0
    }

    private func isClosed(_ key: String, at now: Double) -> Bool {
        (starts[key]?.isSettled(at: now) ?? true) && (ends[key]?.isSettled(at: now) ?? true)
    }
}
