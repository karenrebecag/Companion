import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

/// Semantic roles build a fresh dynamic Color on every read, so equality is
/// by what they resolve to in each appearance.
@MainActor private func badgeSame(_ got: Color?, _ want: Color, _ label: String) {
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

@MainActor private func bitmap(_ view: some View, scheme: ColorScheme = .light) -> Data? {
    let framed = view
        .padding(Space.x4)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

/// shadcn's badge is a capsule with px-2 py-0.5, text-xs medium and gap-1.
@Test @MainActor func badgeMetricsFollowTheScales() {
    expectEq(BadgeMetrics.paddingX, Space.x2, "px-2")
    expectEq(BadgeMetrics.paddingY, Space.x0_5, "py-0.5")
    expectEq(BadgeMetrics.gap, Space.x1, "gap-1")
    expectEq(BadgeMetrics.fontSize, TypeSize.caption, "text-xs")
}

@Test @MainActor func badgeVariantRoles() {
    badgeSame(BadgeVariant.default.background, Semantic.primary, "default: bg-primary")
    badgeSame(BadgeVariant.default.foreground, Semantic.primaryForeground, "default: text")
    badgeSame(BadgeVariant.secondary.background, Semantic.muted, "secondary: bg-secondary")
    badgeSame(BadgeVariant.secondary.foreground, Semantic.foreground, "secondary: text")
    badgeSame(BadgeVariant.destructive.background, Semantic.destructive, "destructive: bg")
    badgeSame(BadgeVariant.destructive.foreground, Semantic.destructiveForeground, "destructive: text")
    badgeSame(BadgeVariant.outline.background, .clear, "outline: transparent")
    badgeSame(BadgeVariant.outline.border, Semantic.borderStrong, "outline: border")
    badgeSame(BadgeVariant.ghost.background, .clear, "ghost: transparent")
    badgeSame(BadgeVariant.link.foreground, Semantic.primary, "link: text-primary")
    for variant in BadgeVariant.allCases where variant != .outline {
        expect(variant.border == nil, "only outline has a border: \(variant)")
    }
}

@Test @MainActor func everyBadgeVariantRendersDistinctly() throws {
    var seen: [BadgeVariant: Data] = [:]
    for variant in BadgeVariant.allCases {
        let png = try #require(bitmap(Badge("Connected", variant: variant)), "render: \(variant)")
        for (other, data) in seen where variant != .ghost && other != .ghost {
            #expect(png != data, "\(variant) looks like \(other)")
        }
        seen[variant] = png
    }
}

@Test @MainActor func badgeCarriesItsGlyphAndLabel() throws {
    let plain = try #require(bitmap(Badge("Connected", variant: .secondary)))
    let withDot = try #require(bitmap(Badge("Connected", variant: .secondary, dot: Semantic.success)))
    #expect(plain != withDot, "the status dot is drawn")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func shadcnBadgeGallery() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let row = HStack(spacing: Space.x3) {
        ForEach(BadgeVariant.allCases, id: \.self) { Badge("Badge", variant: $0) }
        Badge("Connected", variant: .secondary, dot: Semantic.success)
    }
    for scheme in [ColorScheme.light, .dark] {
        let png = try #require(bitmap(row, scheme: scheme))
        try png.write(to: out.appendingPathComponent(
            "shadcn-badge-\(scheme == .dark ? "dark" : "light").png"))
    }
}
