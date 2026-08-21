import SwiftUI

struct WavyBlobView: View {
    private let color: Color
    private let loopDuration: Double

    init(color: Color, loopDuration: Double = 1) {
        self.color = color
        self.loopDuration = loopDuration
    }

    var body: some View {
        TimelineView(.animation(paused: !loopDuration.isFinite || loopDuration <= 0)) { timeline in
            Canvas { context, size in
                let angle: Double
                if loopDuration > 0, loopDuration.isFinite {
                    let timeNow = timeline.date.timeIntervalSinceReferenceDate
                    angle = (timeNow.remainder(dividingBy: loopDuration)
                        / loopDuration) * 2 * .pi
                } else {
                    angle = 0
                }

                var path = Path()
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.45
                let points: [CGPoint] = (0..<6).map { index in
                    let base = (Double(index) / 6) * 2 * .pi
                    let phase = Double(index) * .pi / 3
                    let x = 0.5 + cos(base) * 0.9 + sin(angle + phase) * 0.15
                    let y = 0.5 + sin(base) * 0.9 + cos(angle + phase) * 0.15
                    return CGPoint(
                        x: (x - 0.5) * radius + center.x,
                        y: (y - 0.5) * radius + center.y)
                }

                path.move(to: points[0])
                for i in 0..<points.count {
                    let next = (i + 1) % points.count
                    let currentAngle = atan2(
                        points[i].y - center.y, points[i].x - center.x)
                    let nextAngle = atan2(
                        points[next].y - center.y, points[next].x - center.x)
                    let handle = radius * 0.33
                    path.addCurve(
                        to: points[next],
                        control1: CGPoint(
                            x: points[i].x + cos(currentAngle + .pi / 2) * handle,
                            y: points[i].y + sin(currentAngle + .pi / 2) * handle),
                        control2: CGPoint(
                            x: points[next].x + cos(nextAngle - .pi / 2) * handle,
                            y: points[next].y + sin(nextAngle - .pi / 2) * handle))
                }
                context.fill(path, with: .color(color))
            }
        }
    }
}
