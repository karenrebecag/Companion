import SwiftUI

/// Arc's morph-loader: a ring (or dots) while loading that folds into a check
/// on success and a cross on error, in the same footprint. Completion never
/// rests on color alone: the shape changes too.
struct MorphLoader: View {
    var status: MorphLoaderStatus
    var variant: MorphLoaderShape.Variant = .ring
    var size: CGFloat = 24
    /// Colors the check with success and the cross with danger.
    var tone = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var poses: MorphLoaderPoses
    @State private var started = Date()
    @State private var settledAngle: Double = 0

    init(status: MorphLoaderStatus, variant: MorphLoaderShape.Variant = .ring, size: CGFloat = 24, tone: Bool = true) {
        self.status = status
        self.variant = variant
        self.size = size
        self.tone = tone
        _poses = State(initialValue: MorphLoaderPoses(MorphLoaderGeometry.poses(
            MorphLoaderShape(status: status, variant: variant))))
    }

    private var shape: MorphLoaderShape { MorphLoaderShape(status: status, variant: variant) }
    private var loops: Bool { !reduceMotion && !shape.settles }

    var body: some View {
        Group {
            if loops {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(started)
                    strokes(offsets: MorphLoaderGeometry.loopOffsets(shape, t: t),
                            angle: shape == .ring ? MorphLoaderGeometry.ringDegrees(elapsed: t) : 0)
                }
            } else {
                strokes(offsets: Array(repeating: .zero, count: 4), angle: settledAngle)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(ink)
        .keyframeAnimator(initialValue: 1.0, trigger: shape.settles && !reduceMotion ? status : nil) { content, pop in
            content.scaleEffect(pop)
        } keyframes: { _ in
            // The finished mark pops once.
            CubicKeyframe(MorphLoaderGeometry.popScale, duration: MorphLoaderGeometry.popRise)
            CubicKeyframe(1, duration: MorphLoaderGeometry.popFall)
        }
        .animation(ArcMotion.fade(), value: status)
        .onChange(of: shape) { old, new in morph(from: old, to: new) }
        .accessibilityElement()
        .accessibilityLabel(Localized.string(label))
    }

    private func strokes(offsets: [MorphStrokeOffset], angle: Double) -> some View {
        MorphStrokes(poses: poses, offsets: offsets, scale: size / MorphLoaderGeometry.grid)
            .rotationEffect(.degrees(angle))
    }

    private var ink: AnyShapeStyle {
        guard tone else { return AnyShapeStyle(.foreground) }
        switch status {
        case .loading: return AnyShapeStyle(.foreground)
        case .success: return AnyShapeStyle(ArcTone.success.color)
        case .error: return AnyShapeStyle(ArcTone.danger.color)
        }
    }

    private var label: String {
        switch status {
        case .loading: "loader.loading"
        case .success: "loader.success"
        case .error: "loader.error"
        }
    }

    private func morph(from old: MorphLoaderShape, to new: MorphLoaderShape) {
        let current = poses.poses
        let target = zip(current, MorphLoaderGeometry.poses(new)).map { now, next -> MorphStrokePose in
            var turned = next
            turned.angle = MorphLoaderGeometry.nearestAngle(
                from: now.angle, to: next.angle, symmetric: next.bend == 0 && now.bend < 0.004)
            return turned
        }
        guard !reduceMotion else {
            poses = MorphLoaderPoses(target)
            settledAngle = 0
            return
        }
        if new.settles, old == .ring {
            // Carry the turn on from where the ring was, forward to upright.
            let live = MorphLoaderGeometry.ringDegrees(elapsed: Date().timeIntervalSince(started))
                .truncatingRemainder(dividingBy: 360)
            settledAngle = live
            withAnimation(MorphLoaderGeometry.turn.animation) {
                settledAngle = MorphLoaderGeometry.uprightAngle(after: live)
            }
        } else if !new.settles {
            started = Date()
            settledAngle = 0
        }
        // The check draws itself with a little settle; loading shapes gather at once.
        let spring = new.settles ? MorphLoaderGeometry.settle : MorphLoaderGeometry.gather
        withAnimation(spring.animation) { poses = MorphLoaderPoses(target) }
    }
}

/// The four strokes, animatable as one vector.
private struct MorphStrokes: View, Animatable {
    var poses: MorphLoaderPoses
    let offsets: [MorphStrokeOffset]
    let scale: CGFloat

    var animatableData: MorphLoaderPoses {
        get { poses }
        set { poses = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            for (pose, offset) in zip(poses.poses, offsets) where pose.opacity > 0.001 {
                var moved = pose
                moved.cy += offset.dy
                moved.length = max(0.01, pose.length + offset.length)
                let width = max(0, pose.width + offset.width) * scale
                var layer = context
                layer.opacity = min(1, max(0, pose.opacity))
                layer.stroke(MorphLoaderGeometry.path(moved, scale: scale), with: .foreground,
                             style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
