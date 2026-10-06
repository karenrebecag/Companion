import CompanionTestKit
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Arc's grid on the island: one column rule for every state, so the orb,
// a step's node, a notice's icon and a receipt's check share the lead column
// and every line of text starts at the same x. The island is the surface:
// what sits in it is rows, not nested cards.

@Test @MainActor func everyRowSharesOneColumnRule() {
    expectEq(IslandGrid.lead, 32, "columna guia: 32")
    expectEq(IslandGrid.gap, 12, "separacion: 12, sobre la reticula de 4")
    expectEq(IslandGrid.contentInset, 44, "el texto empieza en guia + separacion")
    expect(IslandGrid.lead.truncatingRemainder(dividingBy: 4) == 0, "guia en la reticula de 4")
}

// The orb is one piece in every state: the same size wherever it sits.
@Test @MainActor func theOrbFillsTheLeadColumnEverywhere() {
    expectEq(IslandChrome.meterSide, IslandGrid.lead, "orbe del estado = columna guia")
    expectEq(IslandFieldMetrics.orb, IslandGrid.lead, "orbe del campo = columna guia")
}

@Test @MainActor func stepNodesSitInsideTheLeadColumn() {
    expect(AgentRunMetrics.node <= IslandGrid.lead, "el nodo cabe en la guia")
    expect(AgentRunMetrics.loader <= IslandGrid.lead, "el loader cabe en la guia")
}

// Arc: a nested corner is the outer radius minus the padding between them.
@Test @MainActor func nestedCornersAreConcentric() {
    expectEq(IslandGrid.innerRadius(outer: 22, padding: 16), 6, "22 - 16 = 6")
    expectEq(IslandGrid.innerRadius(outer: 22, padding: 20), IslandGrid.minRadius, "nunca menor que el minimo")
    expectEq(IslandGrid.nestedRadius, IslandGrid.innerRadius(outer: NotchShape.openRadius,
                                                             padding: IslandChrome.shellMargin),
             "lo anidado en la isla abierta")
}

private struct ContentX: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) { value += nextValue() }
}

private extension View {
    func reportsX() -> some View {
        background(GeometryReader { Color.clear.preference(key: ContentX.self, value: [$0.frame(in: .named("grid")).minX]) })
    }
}

// QA review: the grid's promise, measured: whatever the lead holds (nothing,
// a dot, the orb), the text starts at the content inset.
@Test @MainActor func textStartsAtTheSameXWhateverTheLeadHolds() throws {
    var xs: [CGFloat] = []
    let rows = VStack(alignment: .leading, spacing: 0) {
        IslandGridRow { EmptyView() } content: { Text(verbatim: "vacia").reportsX() }
        IslandGridRow { Circle().frame(width: 8, height: 8) } content: { Text(verbatim: "punto").reportsX() }
        IslandGridRow { Circle().frame(width: 32, height: 32) } content: { Text(verbatim: "orbe").reportsX() }
    }
    .coordinateSpace(.named("grid"))
    .onPreferenceChange(ContentX.self) { xs = $0 }
    .frame(width: 300)
    _ = try #require(ImageRenderer(content: rows).nsImage)
    expectEq(xs.count, 3, "las tres filas midieron")
    expect(xs.allSatisfy { abs($0 - IslandGrid.contentInset) < 0.5 }, "todas en x = 44: \(xs)")
}
