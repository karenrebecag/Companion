import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

// The bottom fade says there is more below, and goes once the scroll is at the end.

@Test @MainActor func aColumnThatFitsOrIsAtItsEndHasNoFade() {
    expect(!IslandColumnFade.showsMore(offset: 0, content: 200, viewport: 300), "cabe entero: sin desvanecido")
    expect(!IslandColumnFade.showsMore(offset: 600, content: 900, viewport: 300), "al final: sin desvanecido")
}

@Test @MainActor func aColumnWithMoreBelowFades() {
    expect(IslandColumnFade.showsMore(offset: 0, content: 900, viewport: 300), "arriba: se desvanece abajo")
    expect(IslandColumnFade.showsMore(offset: -12, content: 900, viewport: 300),
           "el rebote por arriba sigue mostrando que hay mas")
}
