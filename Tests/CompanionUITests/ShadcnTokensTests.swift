import CompanionCore
import CompanionTestKit
import CompanionUI
import Foundation
import Testing

@Test @MainActor func shadcnTokensTests() async {
    testButtonSizeTokens()
    testButtonColorTokens()
    testGapTokens()
}

@MainActor func testButtonSizeTokens() {
    // Height ordering
    expectEq(ButtonSize.xs.height, 24, "xs height is 24")
    expectEq(ButtonSize.sm.height, 32, "sm height is 32")
    expectEq(ButtonSize.default.height, 36, "default height is 36")
    expectEq(ButtonSize.lg.height, 40, "lg height is 40")
    expect(ButtonSize.xs.height < ButtonSize.sm.height)
    expect(ButtonSize.sm.height < ButtonSize.default.height)
    expect(ButtonSize.default.height < ButtonSize.lg.height)

    // Padding X
    expectEq(ButtonSize.xs.paddingX, Space.x2, "xs paddingX is x2")
    expectEq(ButtonSize.sm.paddingX, Space.x3, "sm paddingX is x3")
    expectEq(ButtonSize.default.paddingX, Space.x4, "default paddingX is x4")
    expectEq(ButtonSize.lg.paddingX, Space.x6, "lg paddingX is x6")

    // Padding Y
    expectEq(ButtonSize.xs.paddingY, Space.x0_5, "xs paddingY is x0_5")
    expectEq(ButtonSize.sm.paddingY, Space.x1, "sm paddingY is x1")
    expectEq(ButtonSize.default.paddingY, Space.x1, "default paddingY is x1")
    expectEq(ButtonSize.lg.paddingY, Space.x1_5, "lg paddingY is x1_5")

    // Font sizes
    expectEq(ButtonSize.xs.fontSize, TypeSize.caption, "xs fontSize is caption")
    expectEq(ButtonSize.sm.fontSize, TypeSize.caption, "sm fontSize is caption")
    expectEq(ButtonSize.default.fontSize, TypeSize.body, "default fontSize is body")
    expectEq(ButtonSize.lg.fontSize, TypeSize.rowTitle, "lg fontSize is rowTitle")
}

@MainActor func testButtonColorTokens() {
    // Default variant
    expectEq(ButtonColors.default.background, Semantic.primary, "default background is primary")
    expectEq(ButtonColors.default.foreground, Semantic.primaryForeground, "default foreground is primaryForeground")

    // Destructive variant
    expectEq(ButtonColors.destructive.background, Semantic.destructive, "destructive background is destructive")
    expectEq(ButtonColors.destructive.foreground, Semantic.destructiveForeground, "destructive foreground is destructiveForeground")
    expectEq(ButtonColors.destructive.backgroundHover, Semantic.dangerHover, "destructive hover is dangerHover")

    // Outline variant
    expectEq(ButtonColors.outline.background, Color.clear, "outline background is clear")
    expectEq(ButtonColors.outline.foreground, Semantic.foreground, "outline foreground is foreground")
    expectEq(ButtonColors.outline.backgroundHover, Semantic.hover, "outline hover is hover")

    // Secondary variant
    expectEq(ButtonColors.secondary.background, Semantic.surfaceSecondary, "secondary background is surfaceSecondary")
    expectEq(ButtonColors.secondary.foreground, Semantic.foreground, "secondary foreground is foreground")

    // Ghost variant
    expectEq(ButtonColors.ghost.background, Color.clear, "ghost background is clear")
    expectEq(ButtonColors.ghost.foreground, Semantic.foreground, "ghost foreground is foreground")
    expectEq(ButtonColors.ghost.backgroundHover, Semantic.hover, "ghost hover is hover")

    // Link variant
    expectEq(ButtonColors.link.background, Color.clear, "link background is clear")
    expectEq(ButtonColors.link.foreground, Semantic.primary, "link foreground is primary")
    expectEq(ButtonColors.link.backgroundHover, Color.clear, "link hover background is clear")
}

@MainActor func testGapTokens() {
    // Gap values
    expectEq(Gap.xs, Space.x1, "xs gap is x1")
    expectEq(Gap.sm, Space.x2, "sm gap is x2")
    expectEq(Gap.default, Space.x2, "default gap is x2")
}
