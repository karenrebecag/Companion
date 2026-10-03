import AppKit
import CompanionCore
import CompanionTestKit
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

@Test @MainActor func shadcnTokensTests() async {
    testButtonSizeTokens()
    testButtonVariantTokens()
    testButtonStateResolution()
    testButtonVariantMappings()
}

/// shadcn's h-6/8/9/10, px-2/3/4/6 and gap-1/1.5/2 are Companion's own
/// Space steps; a size that is not one of them would be a second scale.
@MainActor func testButtonSizeTokens() {
    expectEq(ButtonSize.xs.height, Space.x6, "xs is h-6")
    expectEq(ButtonSize.sm.height, Space.x8, "sm is h-8")
    expectEq(ButtonSize.default.height, Space.x9, "default is h-9")
    expectEq(ButtonSize.lg.height, Space.x10, "lg is h-10")

    expectEq(ButtonSize.xs.paddingX, Space.x2, "xs px-2")
    expectEq(ButtonSize.sm.paddingX, Space.x3, "sm px-3")
    expectEq(ButtonSize.default.paddingX, Space.x4, "default px-4")
    expectEq(ButtonSize.lg.paddingX, Space.x6, "lg px-6")

    expectEq(ButtonSize.xs.gap, Space.x1, "xs gap-1")
    expectEq(ButtonSize.sm.gap, Space.x1_5, "sm gap-1.5")
    expectEq(ButtonSize.default.gap, Space.x2, "default gap-2")
    expectEq(ButtonSize.lg.gap, Space.x2, "lg gap-2")

    expectEq(ButtonSize.xs.fontSize, TypeSize.caption, "xs text-xs")
    expectEq(ButtonSize.default.fontSize, TypeSize.rowTitle, "default text-sm")
    expectEq(ButtonSize.lg.fontSize, TypeSize.rowTitle, "lg text-sm")
    expectEq(ButtonSize.default.radius, Radius.md, "rounded-md")
}

/// Semantic roles build a fresh dynamic Color on every read, so equality is
/// by what they resolve to in each appearance.
@MainActor func expectSame(_ got: Color?, _ want: Color, _ label: String) {
    guard let got else { expect(false, label); return }
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        var a: [CGFloat] = [], b: [CGFloat] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            a = rgba(got); b = rgba(want)
        }
        expectEq(a, b, "\(label) (\(name.rawValue))")
    }
}

private func rgba(_ c: Color) -> [CGFloat] {
    let n = NSColor(c).usingColorSpace(.sRGB) ?? .clear
    return [n.redComponent, n.greenComponent, n.blueComponent, n.alphaComponent]
}

/// The opposite check: a hover or ring role that resolves to its rest value
/// in either appearance would be invisible.
@MainActor func expectDifferent(_ a: Color, _ b: Color, _ label: String) {
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        var x: [CGFloat] = [], y: [CGFloat] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            x = rgba(a); y = rgba(b)
        }
        expect(x != y, "\(label) (\(name.rawValue))")
    }
}

@MainActor func testButtonVariantTokens() {
    expectSame(ButtonVariant.default.background(hovering: false), Semantic.primary, "default: bg-primary")
    expectSame(ButtonVariant.default.background(hovering: true), Semantic.primaryHover, "default: hover primary/90")
    expectSame(ButtonVariant.default.foreground, Semantic.primaryForeground, "default: text-primary-foreground")

    expectSame(ButtonVariant.secondary.background(hovering: false), Semantic.muted, "secondary: bg-secondary")
    expectSame(ButtonVariant.secondary.background(hovering: true), Semantic.secondaryHover, "secondary: hover /80")

    expectSame(ButtonVariant.destructive.background(hovering: false), Semantic.destructive, "destructive: bg")
    expectSame(ButtonVariant.destructive.background(hovering: true), Semantic.dangerHover, "destructive: hover")
    expectSame(ButtonVariant.destructive.foreground, Semantic.destructiveForeground, "destructive: text")

    expectSame(ButtonVariant.outline.background(hovering: false), Semantic.surface, "outline: bg-background")
    expectSame(ButtonVariant.outline.background(hovering: true), Semantic.hover, "outline: hover accent")
    expectSame(ButtonVariant.outline.border, Semantic.borderStrong, "outline: border")

    expectSame(ButtonVariant.ghost.background(hovering: false), Color.clear, "ghost: no rest fill")
    expectSame(ButtonVariant.ghost.background(hovering: true), Semantic.hover, "ghost: hover accent")

    expectSame(ButtonVariant.link.background(hovering: true), Color.clear, "link: never fills")
    expectSame(ButtonVariant.link.foreground, Semantic.primary, "link: text-primary")
    expect(ButtonVariant.link.underlinesOnHover, "link underlines on hover")

    for variant in ButtonVariant.allCases where variant != .outline {
        expect(variant.border == nil, "only outline draws a border: \(variant)")
        if variant != .link {
            expect(!variant.underlinesOnHover, "only link underlines: \(variant)")
        }
    }
}

/// Disabled wins over everything; pressing shrinks like every pressable in
/// the app, and reduce-motion turns the shrink off.
@MainActor func testButtonStateResolution() {
    let rest = ButtonLook.resolve(enabled: true, hovering: false, pressed: false, focused: false, reduceMotion: false)
    expectEq(rest.opacity, 1, "rest: opaque")
    expectEq(rest.scale, 1, "rest: no scale")
    expectEq(rest.ring, 0, "rest: no ring")

    let off = ButtonLook.resolve(enabled: false, hovering: true, pressed: true, focused: true, reduceMotion: false)
    expectEq(off.opacity, StateAlpha.disabled, "disabled: opacity-50")
    expectEq(off.scale, 1, "disabled: does not respond")
    expectEq(off.ring, 0, "disabled: no ring")
    expect(!off.hovering, "disabled: hover ignored")

    let pressed = ButtonLook.resolve(enabled: true, hovering: true, pressed: true, focused: false, reduceMotion: false)
    expectEq(pressed.scale, PressMotion.pressedScale, "pressed: shrinks")
    let still = ButtonLook.resolve(enabled: true, hovering: true, pressed: true, focused: false, reduceMotion: true)
    expectEq(still.scale, 1, "reduce motion: no shrink")

    let focus = ButtonLook.resolve(enabled: true, hovering: false, pressed: false, focused: true, reduceMotion: false)
    expectEq(focus.ring, Stroke.ring, "focus: 3 pt ring")
}

/// The app's kinds and Settings' pill roles map onto shadcn variants.
@MainActor func testButtonVariantMappings() {
    expectEq(ButtonVariant(pill: .neutral), .secondary, "neutral pill is secondary")
    expectEq(ButtonVariant(pill: .primary), .default, "primary pill is default")
    expectEq(ButtonVariant(pill: .destructive), .destructive, "destructive pill is destructive")
    expectEq(ButtonVariant(kind: .primary), .default, "primary kind")
    expectEq(ButtonVariant(kind: .neutral), .default, "neutral kind")
    expectEq(ButtonVariant(kind: .secondary), .secondary, "secondary kind")
    expectEq(ButtonVariant(kind: .ghost), .ghost, "ghost kind")
    expectEq(ButtonVariant(kind: .destructive), .destructive, "destructive kind")
}

/// The values behind the roles, not just the wiring: shadcn's ring is 3 pt
/// and its hover states are a step away from the rest fill.
@Test @MainActor func shadcnRoleValues() {
    expectEq(Stroke.ring, 3, "focus-visible:ring-[3px]")
    expectDifferent(Semantic.primaryHover, Semantic.primary, "primary/90 differs from primary")
    expectDifferent(Semantic.secondaryHover, Semantic.muted, "secondary/80 differs from secondary")
    expectDifferent(Semantic.focusRing, Semantic.accent, "ring/50 is translucent")
}
