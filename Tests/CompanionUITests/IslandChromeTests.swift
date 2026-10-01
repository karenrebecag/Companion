import AppKit
import CompanionCore
import CompanionTestKit
import CompanionUI
import Testing

// 16f replaced the docked, resizing window with a fixed canvas under the
// notch (NotchTests). What stays here is the ramp of widths per role.

@Test @MainActor func islandChromeTests() {
    testTheRampGrowsWithTheRole()
}

@MainActor func testTheRampGrowsWithTheRole() {
    expect(IslandChrome.barWidth < IslandChrome.nudgeWidth, "island: la píldora es más angosta que el panel")
    expect(IslandChrome.nudgeWidth <= IslandChrome.cardWidth, "island: la tarjeta es la más ancha")
    expectEq(IslandChrome.cardWidth, 492, "island: el ancho medido en la grabación")
}
