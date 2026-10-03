import SwiftUI

/// The three moods SF Symbols has no face for (Incredible's SmileyAngry,
/// SmileyMeh and SmileySad; audit ICO-28..30). Drawn as strokes so they sit
/// beside face.smiling with the same round outline, eyes and weight.
nonisolated package enum MoodFace: Sendable, CaseIterable, Hashable {
    case angry, meh, sad
}

/// The face in a 24-point box, as data: the tests read the mood off the
/// mouth's curve and the brows, not off pixels.
nonisolated package struct MoodFaceGeometry: Sendable, Equatable {
    package struct Segment: Sendable, Equatable {
        package var from: CGPoint
        package var to: CGPoint
    }

    /// A quadratic curve: a control above the corners is a frown (y grows down).
    package struct Mouth: Sendable, Equatable {
        package var from: CGPoint
        package var control: CGPoint
        package var to: CGPoint
    }

    package static let viewBox: CGFloat = 24
    package static let radius: CGFloat = 9.5

    package var eyes: [Segment]
    package var mouth: Mouth
    package var brows: [Segment]

    package static func of(_ face: MoodFace) -> MoodFaceGeometry {
        switch face {
        case .meh:
            return MoodFaceGeometry(
                eyes: pair(Segment(from: CGPoint(x: 8.9, y: 9), to: CGPoint(x: 8.9, y: 10.4))),
                mouth: mouth(corners: 15.6, control: 15.6, halfWidth: 3.4), brows: [])
        case .sad:
            return MoodFaceGeometry(
                eyes: pair(Segment(from: CGPoint(x: 8.9, y: 9), to: CGPoint(x: 8.9, y: 10.4))),
                mouth: mouth(corners: 16.6, control: 13.4, halfWidth: 3.6), brows: [])
        case .angry:
            // The eyes sit lower so the brows have room above them.
            return MoodFaceGeometry(
                eyes: pair(Segment(from: CGPoint(x: 8.9, y: 9.8), to: CGPoint(x: 8.9, y: 11))),
                mouth: mouth(corners: 16.4, control: 14.2, halfWidth: 3.2),
                brows: pair(Segment(from: CGPoint(x: 7.2, y: 7.2), to: CGPoint(x: 10.4, y: 8.5))))
        }
    }

    /// The left half, mirrored: the faces are symmetric by construction.
    private static func pair(_ left: Segment) -> [Segment] {
        let mirror = { (p: CGPoint) in CGPoint(x: viewBox - p.x, y: p.y) }
        return [left, Segment(from: mirror(left.from), to: mirror(left.to))]
    }

    private static func mouth(corners: CGFloat, control: CGFloat, halfWidth: CGFloat) -> Mouth {
        let middle = viewBox / 2
        return Mouth(
            from: CGPoint(x: middle - halfWidth, y: corners),
            control: CGPoint(x: middle, y: control),
            to: CGPoint(x: middle + halfWidth, y: corners))
    }
}

package struct MoodFaceShape: Shape {
    /// Matched by eye against face.smiling at the regular weight, side by side.
    nonisolated package static let weight: CGFloat = 1.4 / MoodFaceGeometry.viewBox

    /// Proportional, as a symbol's line is: a fixed width would read bold at 12 and hairline at 64.
    nonisolated package static func lineWidth(forSide side: CGFloat) -> CGFloat {
        side * weight
    }

    package var face: MoodFace

    package init(face: MoodFace) {
        self.face = face
    }

    package func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / MoodFaceGeometry.viewBox
        // Centered in a non-square box, as a symbol is in its line.
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
        let geometry = MoodFaceGeometry.of(face)
        let radius = MoodFaceGeometry.radius * scale
        var path = Path()
        path.addEllipse(in: CGRect(
            x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
        for segment in geometry.eyes + geometry.brows {
            path.move(to: pt(segment.from))
            path.addLine(to: pt(segment.to))
        }
        path.move(to: pt(geometry.mouth.from))
        path.addQuadCurve(to: pt(geometry.mouth.to), control: pt(geometry.mouth.control))
        return path
    }
}

/// A drawn face sized by face.smiling at the current font, so the row of
/// moods lines up whichever of them is a symbol and which is drawn.
package struct MoodFaceGlyph: View {
    let face: MoodFace

    package init(face: MoodFace) {
        self.face = face
    }

    package var body: some View {
        Image(systemName: "face.smiling")
            .hidden()
            .overlay {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    MoodFaceShape(face: face)
                        .stroke(style: StrokeStyle(
                            lineWidth: MoodFaceShape.lineWidth(forSide: side), lineCap: .round, lineJoin: .round))
                }
            }
            .accessibilityHidden(true)
    }
}
