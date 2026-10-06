import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

// Arc's scroll-area: the edges fade only where there is more to scroll to.

@Test @MainActor func aColumnThatFitsHasNoFade() {
    let edges = IslandColumnFade.edges(offset: 0, content: 200, viewport: 300)
    expect(!edges.top && !edges.bottom, "cabe entero: sin desvanecido")
}

@Test @MainActor func onlyTheEdgesWithMoreContentFade() {
    let top = IslandColumnFade.edges(offset: 0, content: 900, viewport: 300)
    expect(!top.top && top.bottom, "arriba del todo: solo abajo")
    let middle = IslandColumnFade.edges(offset: 200, content: 900, viewport: 300)
    expect(middle.top && middle.bottom, "a mitad: ambos")
    let bottom = IslandColumnFade.edges(offset: 600, content: 900, viewport: 300)
    expect(bottom.top && !bottom.bottom, "abajo del todo: solo arriba")
}

@Test @MainActor func aBounceDoesNotFlickerTheFade() {
    let past = IslandColumnFade.edges(offset: -12, content: 900, viewport: 300)
    expect(!past.top, "el rebote por arriba no enciende el borde de arriba")
    let pastEnd = IslandColumnFade.edges(offset: 640, content: 900, viewport: 300)
    expect(!pastEnd.bottom, "el rebote por abajo no enciende el de abajo")
}
