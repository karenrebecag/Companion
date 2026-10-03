import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The Apps page card is Incredible 0.2.36's connector card (main-BL-DABKy.js
// `function Ch`, rendered by the page's `pr` grid), and the skeleton that
// stands in for it draws the same box so nothing jumps when the list lands.

@Test @MainActor func appCardMatchesIncrediblesConnectorCard() {
    #expect(AppCardMetrics.padding == 18, "p-indent")
    #expect(AppCardMetrics.radius == 22, "rounded-card")
    #expect(AppCardMetrics.gap == 16, "gap-4")
    #expect(AppCardMetrics.icon == 48, "Na size 48")
    #expect(AppCardMetrics.iconRadius == 20, "Na rounded-xl")
    #expect(AppCardMetrics.iconInset == 8, "Na fillRatio .66: a 32 mark in 48")
    #expect(AppCardMetrics.initialsSize == 13, "Na fallback max(10, 48 * .28)")
    #expect(AppCardMetrics.textGap == 4, "mt-1")
    #expect(AppCardMetrics.titleSize == 14, "text-row-title")
    #expect(AppCardMetrics.descriptionLines == 2, "line-clamp-2")
    #expect(AppCardMetrics.badgePaddingX == 12, "px-3")
    #expect(AppCardMetrics.badgePaddingY == 6, "py-1.5")
    #expect(AppCardMetrics.badgeGap == 6, "gap-1.5")
    #expect(AppCardMetrics.badgeIcon == 12, "check size 12")
    #expect(AppCardMetrics.hoverDuration == MotionTime.fast, "duration-150")
}

// Incredible's Na (main-BL-DABKy.js @148041) shows `name.slice(0,2)
// .toUpperCase()`: the first two UTF-16 units, uppercased, nothing trimmed.
// Kept where it gives a mark; the degenerate inputs it would render as a
// blank or a three-letter tile are bounded here: trimmed, never a split
// grapheme, at most two characters, and nil (the generic glyph) when empty.
struct InitialsRow: Sendable, CustomTestStringConvertible {
    let name: String
    let expected: String?
    var testDescription: String { "\(name.debugDescription) -> \(expected.debugDescription)" }
}

private let initialsRows: [InitialsRow] = [
    InitialsRow(name: "slack", expected: "SL"),
    InitialsRow(name: "Google Drive", expected: "GO"),
    InitialsRow(name: "X", expected: "X"),
    InitialsRow(name: " slack", expected: "SL"),
    InitialsRow(name: "slack ", expected: "SL"),
    InitialsRow(name: " a b", expected: "A"),
    InitialsRow(name: "   ", expected: nil),
    InitialsRow(name: "", expected: nil),
    InitialsRow(name: "日本語", expected: "日本"),
    InitialsRow(name: "🚀Rocket", expected: "🚀"),
    InitialsRow(name: "ßa", expected: "SS"),
    InitialsRow(name: "\u{E9}", expected: "\u{C9}"),
    InitialsRow(name: "e\u{301}", expected: "E\u{301}"),
]

@Test(arguments: initialsRows)
@MainActor func appIconInitialsFollowIncredible(_ row: InitialsRow) {
    let got = AppIconView.initials(of: row.name)
    #expect(got == row.expected)
    if let got { #expect(got.count <= 2, "never more than two characters") }
}

@Test @MainActor func appCardTrailingFollowsTheConnectState() {
    #expect(AppCardTrailing.kind(for: nil) == .connect)
    #expect(AppCardTrailing.kind(for: .reconnect) == .reconnect)
    #expect(AppCardTrailing.kind(for: .connected) == .connected)
    #expect(AppCardTrailing.connect.titleKey == "apps.connect")
    #expect(AppCardTrailing.connect.systemImage == "plus")
    #expect(AppCardTrailing.connect.actionKey == "apps.connect")
    #expect(AppCardTrailing.reconnect.titleKey == "apps.reconnect")
    #expect(AppCardTrailing.reconnect.systemImage == nil)
    #expect(AppCardTrailing.reconnect.actionKey == "apps.reconnect")
    #expect(AppCardTrailing.connected.titleKey == "apps.connected")
    #expect(AppCardTrailing.connected.actionKey == nil, "a connected card offers no Connect action")
}

/// Incredible's grid stretches each card to its row (CSS align-items:
/// stretch); a one-line blurb beside a two-line one must not sit shorter.
@Test @MainActor func cardsInOneGridRowShareTheirHeight() {
    let short = CatalogApp(slug: "linear", name: "Linear", description: "Create and update issues.", icon: nil)
    let long = CatalogApp(
        slug: "gmail", name: "Gmail",
        description: "Read, search and draft email without leaving the conversation, across every label.",
        icon: nil)
    let heights = HeightBox()
    let grid = AppsGrid(items: [short, long]) { app in
        AppCard(app: app, state: nil, onOpen: {}, onConnect: {})
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { heights.values[app.slug] = $0 }
    }
    .frame(width: 840)
    let host = NSHostingView(rootView: grid)
    host.frame = CGRect(x: 0, y: 0, width: 840, height: 600)
    host.layoutSubtreeIfNeeded()
    let short1 = heights.values["linear"], long1 = heights.values["gmail"]
    #expect(short1 != nil && long1 != nil, "both cards measured")
    #expect(short1 == long1, "linear \(String(describing: short1)) vs gmail \(String(describing: long1))")
}

@MainActor private final class HeightBox {
    var values: [String: CGFloat] = [:]
}

@Test @MainActor func appsSkeletonDrawsTheCardItStandsIn() {
    #expect(AppsSkeletonMetrics.cardPadding == AppCardMetrics.padding)
    #expect(AppsSkeletonMetrics.cardRadius == AppCardMetrics.radius)
    #expect(AppsSkeletonMetrics.cardGap == AppCardMetrics.gap)
    #expect(AppsSkeletonMetrics.icon == AppCardMetrics.icon)
    #expect(AppsSkeletonMetrics.iconRadius == AppCardMetrics.iconRadius)
}

@Test @MainActor func appCardColoursFollowIncredible() {
    expectSame(AppCardChrome.border(hovering: false), Semantic.borderChrome, "rest: border-border-chrome")
    expectSame(AppCardChrome.border(hovering: true), Semantic.cardHoverBorder, "hover: border-black/[0.14]")
    expectDifferent(Semantic.cardHoverBorder, Semantic.borderChrome, "hover is visible")
    let light = rgba(Semantic.cardHoverBorder, .aqua)
    #expect(light == rgba(Color.black.opacity(0.14), .aqua), "#00000024")
    #expect(hex(Semantic.connectedWash, .aqua) == "E3F1E8")
    #expect(hex(Semantic.connectedInk, .aqua) == "2C7A4B")
    // Incredible has no dark theme: white 14 % for the hover border, and the
    // island's signal green as ink over a 14 % wash of itself.
    #expect(rgba(Semantic.cardHoverBorder, .darkAqua) == rgba(Color.white.opacity(0.14), .darkAqua))
    #expect(hex(Semantic.connectedInk, .darkAqua) == "78D6A8")
    #expect(rgba(Semantic.connectedWash, .darkAqua) == [0x78, 0xD6, 0xA8, Int((0.14 * 255).rounded())])
}

@Test @MainActor func oklabMixMatchesCSSColorMix() {
    let black = Swatch("000000"), white = Swatch("FFFFFF")
    #expect(ColorMix.oklab(white, over: black, amount: 0).hex == "000000")
    #expect(ColorMix.oklab(white, over: black, amount: 1).hex == "FFFFFF")
    // Reference values computed outside the codebase with the published
    // OKLab matrices: white/black meet at L .5, not at sRGB 128.
    #expect(ColorMix.oklab(white, over: black, amount: 0.5).hex == "636363")
    #expect(ColorMix.oklab(Swatch("FF0000"), over: Swatch("0000FF"), amount: 0.5).hex == "8C53A2")
    #expect(ColorMix.oklab(Swatch("404040"), over: Swatch("171717"), amount: 0.38).hex == "262626")
    #expect(ColorMix.oklab(Swatch("FF8000"), over: Swatch("3366CC"), amount: 0.25).hex == "6E76AF")
}

@Test @MainActor func oklabMixClampsAndKeepsItsOrder() {
    let top = Swatch("FF8000"), bottom = Swatch("3366CC")
    #expect(ColorMix.oklab(top, over: bottom, amount: -0.2).hex == bottom.hex, "below 0 is the bottom")
    #expect(ColorMix.oklab(top, over: bottom, amount: 1.4).hex == top.hex, "above 1 is the top")
    #expect(ColorMix.oklab(top, over: bottom, amount: 0.25).hex != ColorMix.oklab(bottom, over: top, amount: 0.25).hex)
    #expect(ColorMix.oklab(bottom, over: top, amount: 0.25).hex == "D08265")
    // Both of these leave sRGB on the way back (red > 1, red < 0); the
    // channel is clamped, not wrapped.
    #expect(ColorMix.oklab(Swatch("FF0000"), over: Swatch("FFFF00"), amount: 0.5).hex == "FFA000")
    #expect(ColorMix.oklab(Swatch("00FF00"), over: Swatch("0000FF"), amount: 0.5).hex == "00AABF")
}

@Test @MainActor func skeletonFillKeepsIncredibleLightAndArcsDarkContrast() {
    #expect(hex(Semantic.skeletonFill, .aqua) == hex(Semantic.surfaceSecondary, .aqua), "light: #f9f9f9")
    // Dark: the strong border mixed 38 % over the card surface the blocks sit on.
    let border = hex(Semantic.borderStrong, .darkAqua)
    let surface = hex(Semantic.surface, .darkAqua)
    let want = ColorMix.oklab(Swatch(border), over: Swatch(surface), amount: SkeletonFill.darkMix).hex
    #expect(SkeletonFill.darkMix == 0.38)
    #expect(hex(Semantic.skeletonFill, .darkAqua) == want)
    #expect(hex(Semantic.skeletonFill, .darkAqua) == "262626")
    #expect(hex(Semantic.skeletonFill, .darkAqua) != surface, "dark blocks stand off the card")
}

/// Swatches are built in sRGB (#220), so a palette hex reads back exactly
/// only in sRGB.
private func rgba(_ c: Color, _ name: NSAppearance.Name) -> [Int] {
    var out: [Int] = []
    NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .clear
        out = [n.redComponent, n.greenComponent, n.blueComponent, n.alphaComponent].map { Int(($0 * 255).rounded()) }
    }
    return out
}

private func hex(_ c: Color, _ name: NSAppearance.Name) -> String {
    rgba(c, name).prefix(3).map { String(format: "%02X", $0) }.joined()
}
