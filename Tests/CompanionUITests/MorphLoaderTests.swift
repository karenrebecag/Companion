import CompanionTestKit
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Arc's morph-loader: every shape, and the check and cross it ends on, is the
// same four strokes in a new pose, so a status change morphs instead of swapping.

private func near(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) < eps }

@Test @MainActor func everyShapeIsFourStrokes() {
    for shape in MorphLoaderShape.allCases {
        expectEq(MorphLoaderGeometry.poses(shape).count, 4, "\(shape): cuatro trazos")
    }
}

@Test @MainActor func theCheckRunsFromLowerLeftToUpperRight() {
    let check = MorphLoaderGeometry.poses(.success)
    let first = MorphLoaderGeometry.ends(check[0])
    let last = MorphLoaderGeometry.ends(check[3])
    expect(near(first.0.x, 5) && near(first.0.y, 12.5), "check: empieza en (5, 12.5)")
    expect(near(last.1.x, 19) && near(last.1.y, 7.5), "check: termina en (19, 7.5)")
    // The strokes chain: each one starts where the previous ended.
    for i in 1..<4 {
        let prev = MorphLoaderGeometry.ends(check[i - 1]).1
        let next = MorphLoaderGeometry.ends(check[i]).0
        expect(near(prev.x, next.x, 1e-4) && near(prev.y, next.y, 1e-4), "check: trazo \(i) encadenado")
    }
}

@Test @MainActor func theCrossMeetsAtTheCenter() {
    let cross = MorphLoaderGeometry.poses(.error)
    for pose in cross {
        let (a, b) = MorphLoaderGeometry.ends(pose)
        expect((near(a.x, 12, 1e-4) && near(a.y, 12, 1e-4)) || (near(b.x, 12, 1e-4) && near(b.y, 12, 1e-4)),
               "cruz: cada trazo toca el centro")
    }
}

@Test @MainActor func theRingIsFourArcsOnOneCircle() {
    for pose in MorphLoaderGeometry.poses(.ring) {
        expect(near(pose.bend, 1 / 8.5), "anillo: curvatura de radio 8.5")
        let (a, b) = MorphLoaderGeometry.ends(pose)
        let ra = hypot(a.x - 12, a.y - 12), rb = hypot(b.x - 12, b.y - 12)
        expect(near(ra, 8.5, 1e-4) && near(rb, 8.5, 1e-4), "anillo: extremos sobre el circulo")
    }
}

@Test @MainActor func theDotsHideTheirFourthStroke() {
    let dots = MorphLoaderGeometry.poses(.dots)
    expectEq(dots[3].opacity, 0, "puntos: el cuarto no se ve")
    expect(dots[0..<3].allSatisfy { $0.opacity == 1 }, "puntos: tres visibles")
}

@Test @MainActor func aStatusPicksItsShape() {
    expectEq(MorphLoaderShape(status: .loading, variant: .ring), .ring, "cargando: la variante")
    expectEq(MorphLoaderShape(status: .success, variant: .ring), .success, "exito: el check")
    expectEq(MorphLoaderShape(status: .error, variant: .dots), .error, "error: la cruz")
}

// Straight strokes look the same reversed, so they may flip by 180 instead of turning far.
@Test @MainActor func strokesTurnTheShortWay() {
    expectEq(MorphLoaderGeometry.nearestAngle(from: 350, to: 10, symmetric: false), 370, "gira 20, no 340")
    expectEq(MorphLoaderGeometry.nearestAngle(from: 170, to: -10, symmetric: true), 170, "simetrico: media vuelta gratis")
}

@Test @MainActor func aSettledMarkLandsUpright() {
    expectEq(MorphLoaderGeometry.uprightAngle(after: 0), 0, "ya derecho")
    expectEq(MorphLoaderGeometry.uprightAngle(after: 200), 360, "sigue hacia adelante a la vuelta completa")
    expectEq(MorphLoaderGeometry.uprightAngle(after: 361), 360, "un grado de mas ya cuenta como derecho")
    expectEq(MorphLoaderGeometry.uprightAngle(after: 380), 720, "nunca gira hacia atras")
}

@Test @MainActor func theLoopOnlyMovesWhileLoading() {
    let t = 0.35
    expect(MorphLoaderGeometry.loopOffsets(.ring, t: t).contains { $0.length != 0 }, "anillo: respira")
    expect(MorphLoaderGeometry.loopOffsets(.dots, t: t).contains { $0.dy != 0 }, "puntos: rebotan")
    expect(MorphLoaderGeometry.loopOffsets(.success, t: t).allSatisfy { $0 == .zero }, "check: quieto")
    expectEq(MorphLoaderGeometry.ringDegrees(elapsed: 1), 330, "anillo: 330 grados por segundo")
}

@Test @MainActor func posesInterpolateAsOneVector() {
    let a = MorphLoaderPoses(MorphLoaderGeometry.poses(.ring))
    let b = MorphLoaderPoses(MorphLoaderGeometry.poses(.success))
    var half = b - a
    half.scale(by: 0.5)
    let mid = a + half
    expectEq(mid.poses.count, 4, "la mezcla conserva cuatro trazos")
    expect(near(mid.poses[0].cx, (a.poses[0].cx + b.poses[0].cx) / 2), "la mezcla esta a medio camino")
    expectEq(MorphLoaderPoses.zero + a, a, "cero es neutro")
}

@Test @MainActor func theLoaderRendersInEveryStatus() throws {
    for status in [MorphLoaderStatus.loading, .success, .error] {
        let image = ImageRenderer(content: MorphLoader(status: status, size: 24).environment(\.colorScheme, .dark)).nsImage
        let size = try #require(image).size
        expectEq(size.width, 24, "\(status): huella fija de 24")
    }
}

private func points(_ path: Path) -> [CGPoint] {
    var out: [CGPoint] = []
    path.forEach { element in
        switch element {
        case .move(let to), .line(let to): out.append(to)
        default: break
        }
    }
    return out
}

// QA review: the drawn arc, not only its chord, lies on the ring's circle.
@Test @MainActor func theRingArcsAreDrawnOnTheirCircle() {
    for pose in MorphLoaderGeometry.poses(.ring) where pose.opacity > 0 {
        let drawn = points(MorphLoaderGeometry.path(pose, scale: 1))
        expect(drawn.count > 2, "un arco, no una recta")
        for point in drawn {
            let r = ((point.x - 12) * (point.x - 12) + (point.y - 12) * (point.y - 12)).squareRoot()
            expect(abs(r - 8.5) < 0.05, "sobre el circulo de 8.5: \(r)")
            expect((0...24).contains(point.x) && (0...24).contains(point.y), "dentro de la caja de 24")
        }
    }
}

@Test @MainActor func anAlmostStraightStrokeDrawsAsALine() {
    let pose = MorphStrokePose(cx: 12, cy: 12, length: 10, angle: 0, bend: 0.003, width: 2, opacity: 1)
    expectEq(points(MorphLoaderGeometry.path(pose, scale: 1)).count, 2, "casi recto: una linea")
}
