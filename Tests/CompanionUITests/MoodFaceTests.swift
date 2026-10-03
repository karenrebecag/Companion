import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CoreGraphics
import Testing

// Gap 11 (audit ICO-27..30): the three moods SF Symbols has no face for are
// drawn, beside face.smiling, as a circle, eyes and a mouth whose curve says
// the mood. Incredible's feedback row: angry, sad, meh, happy, love
// (main-BL-DABKy.js, the `ej` mood list).

private let box = MoodFaceGeometry.viewBox

@Test func eachMoodMapsToIncrediblesFace() {
    expectEq(FeedbackMood.upset.glyph, .face(.angry), "frustrated: the angry face")
    expectEq(FeedbackMood.bad.glyph, .face(.sad), "disappointed: the sad face")
    expectEq(FeedbackMood.meh.glyph, .face(.meh), "neutral: the flat face")
    expectEq(FeedbackMood.good.glyph, .symbol("face.smiling"), "happy: SF's own smiling face")
    expectEq(FeedbackMood.love.glyph, .symbol("heart"), "love: the heart")
}

@Test func theMouthCurvesTheWayTheMoodReads() {
    for face in MoodFace.allCases {
        let mouth = MoodFaceGeometry.of(face).mouth
        // y grows downward: a control above the corners bends the mouth into a frown.
        let bend = mouth.control.y - mouth.from.y
        switch face {
        case .meh: expectEq(bend, 0, "meh: a flat mouth")
        case .sad, .angry: expect(bend < 0, "\(face): a frown, the middle above the corners")
        }
        expectEq(mouth.from.y, mouth.to.y, "\(face): the corners level")
    }
    let sad = MoodFaceGeometry.of(.sad).mouth
    let angry = MoodFaceGeometry.of(.angry).mouth
    expect(sad.control.y - sad.from.y < angry.control.y - angry.from.y, "sad droops more than angry")
}

@Test func onlyTheAngryFaceHasBrowsAndTheyFrown() {
    expectEq(MoodFaceGeometry.of(.meh).brows, [], "meh: no brows")
    expectEq(MoodFaceGeometry.of(.sad).brows, [], "sad: no brows")
    let brows = MoodFaceGeometry.of(.angry).brows
    expectEq(brows.count, 2, "angry: two brows")
    for brow in brows {
        let inner = abs(brow.from.x - box / 2) < abs(brow.to.x - box / 2) ? brow.from : brow.to
        let outer = inner == brow.from ? brow.to : brow.from
        expect(inner.y > outer.y, "angry: the inner end lower, slanting toward the nose")
    }
}

@Test func everyFaceIsMirrorSymmetric() {
    let axis = box / 2
    for face in MoodFace.allCases {
        let geometry = MoodFaceGeometry.of(face)
        let mirrored = { (p: CGPoint) in CGPoint(x: 2 * axis - p.x, y: p.y) }
        let pairs = [geometry.eyes] + (geometry.brows.isEmpty ? [] : [geometry.brows])
        for pair in pairs {
            expectEq(pair.count, 2, "\(face): a pair")
            expectEq(mirrored(pair[0].from), pair[1].from, "\(face): mirrored start")
            expectEq(mirrored(pair[0].to), pair[1].to, "\(face): mirrored end")
        }
        expectEq(geometry.mouth.control.x, axis, "\(face): the mouth's middle on the axis")
        expectEq(mirrored(geometry.mouth.from), geometry.mouth.to, "\(face): the mouth's corners mirrored")
    }
}

@Test func theStrokedFaceStaysInsideItsBoxAtAnySize() {
    for side in [12.0, 17, 24, 64] as [CGFloat] {
        let rect = CGRect(x: 3, y: 5, width: side, height: side)
        let half = side * MoodFaceShape.weight / 2
        for face in MoodFace.allCases {
            let bounds = MoodFaceShape(face: face).path(in: rect).boundingRect
            expect(rect.insetBy(dx: half, dy: half).contains(bounds), "\(face) at \(side): inside with its stroke")
            expect(abs(bounds.midX - rect.midX) < 0.001, "\(face) at \(side): centered")
        }
    }
}

@Test func theStrokeScalesWithTheFaceLikeAnSFSymbol() {
    expect(MoodFaceShape.weight > 0.04 && MoodFaceShape.weight < 0.08, "a regular SF weight, 1-2 pt at 24")
    let wide = CGRect(x: 0, y: 0, width: 40, height: 20)
    let bounds = MoodFaceShape(face: .meh).path(in: wide).boundingRect
    expect(abs(bounds.midX - wide.midX) < 0.001 && bounds.width <= 20, "a wide box: a round face, centered")
}

@Test func everyFeatureSitsInsideTheOutlineWithRoomForBothStrokes() {
    let center = CGPoint(x: box / 2, y: box / 2)
    // A feature's stroke and the outline's stroke must not touch: each takes half a line.
    let limit = MoodFaceGeometry.radius - MoodFaceShape.weight * box
    for face in MoodFace.allCases {
        let geometry = MoodFaceGeometry.of(face)
        let mouth = geometry.mouth
        // A quadratic stays inside the hull of its three points.
        let points = (geometry.eyes + geometry.brows).flatMap { [$0.from, $0.to] }
            + [mouth.from, mouth.control, mouth.to]
        for p in points {
            let distance = hypot(p.x - center.x, p.y - center.y)
            expect(distance < limit, "\(face): \(p) clear of the outline")
        }
    }
}

@Test func aNonSquareBoxDrawsTheSameFaceCentered() {
    let side: CGFloat = 20
    let cases: [(CGRect, CGRect)] = [
        (CGRect(x: 0, y: 0, width: 40, height: 20), CGRect(x: 10, y: 0, width: side, height: side)),
        (CGRect(x: 0, y: 0, width: 20, height: 40), CGRect(x: 0, y: 10, width: side, height: side)),
    ]
    for face in MoodFace.allCases {
        for (box, square) in cases {
            let shape = MoodFaceShape(face: face)
            expectEq(shape.path(in: box), shape.path(in: square),
                     "\(face) in \(box.size): the square face, every feature moved to the middle")
        }
    }
}

@Test func theLineWidthGrowsWithTheFace() {
    expect(abs(MoodFaceShape.lineWidth(forSide: 24) - 1.4) < 1e-9, "1.4 pt at 24, like a regular SF symbol")
    let ratio = MoodFaceShape.lineWidth(forSide: 64) / MoodFaceShape.lineWidth(forSide: 12)
    expect(abs(ratio - 64.0 / 12) < 1e-9, "the line keeps its proportion at any size")
}

@Test func anEmptyBoxDrawsNothingBroken() {
    for face in MoodFace.allCases {
        let bounds = MoodFaceShape(face: face).path(in: .zero).boundingRect
        expect(bounds.width.isFinite && bounds.height.isFinite && !bounds.minX.isNaN,
               "\(face): a zero box, no NaN")
    }
}

@Test func theAngryBrowsSitAboveTheEyes() {
    let geometry = MoodFaceGeometry.of(.angry)
    let lowestBrow = geometry.brows.flatMap { [$0.from.y, $0.to.y] }.max() ?? .infinity
    let highestEye = geometry.eyes.flatMap { [$0.from.y, $0.to.y] }.min() ?? -.infinity
    expect(lowestBrow < highestEye, "angry: the brows above the eyes")
}
