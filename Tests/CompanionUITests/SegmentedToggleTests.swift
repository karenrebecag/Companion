import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// WIN-7 of the Incredible audit: `.fr-dev-segment`, a segmented toggle whose
// active segment is white with black text.

@MainActor private func segSame(_ got: Color, _ want: Color, _ label: String) {
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        var a: [CGFloat] = [], b: [CGFloat] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance { a = segRGBA(got); b = segRGBA(want) }
        expectEq(a, b, "\(label) (\(name.rawValue))")
    }
}

private func segRGBA(_ c: Color) -> [CGFloat] {
    let n = NSColor(c).usingColorSpace(.sRGB) ?? .clear
    return [n.redComponent, n.greenComponent, n.blueComponent, n.alphaComponent]
}

@Test @MainActor func segmentedMetricsAreIncredibles() {
    expectEq(SegmentedMetrics.gap, 2, "gap 2px")
    expectEq(SegmentedMetrics.padding, 2, "padding 2px")
    expectEq(SegmentedMetrics.radius, Radius.chip, "radius 10px")
    expectEq(SegmentedMetrics.minHeight, Space.x6, "segment min-height 24px")
    expectEq(SegmentedMetrics.duration, 0.22, ".22 s")
    expectEq(SegmentedMetrics.segmentRadius, Radius.badge, "the segment sits 2px inside the 10px frame")
}

@Test @MainActor func theActiveSegmentIsWhiteWithBlackText() {
    segSame(SegmentedLook.background(selected: true), Neutral.white.color, "active: white")
    segSame(SegmentedLook.foreground(selected: true), Neutral.black.color, "active: black text")
    segSame(SegmentedLook.background(selected: false), .clear, "inactive: no fill")
    segSame(SegmentedLook.foreground(selected: false), Semantic.mutedForeground, "inactive: muted text")
    expectEq(SegmentedLook.weight(selected: true), .semibold, "active: weight 600")
    expectEq(SegmentedLook.weight(selected: false), .medium, "inactive: medium")
}

@Test @MainActor func selectionMovesToTheTappedSegment() {
    var model = SegmentedSelection<String>(options: ["a", "b", "c"], selected: "a")
    expectEq(model.selected, "a", "starts on a")
    model.select("c")
    expectEq(model.selected, "c", "moves to c")
    model.select("zzz")
    expectEq(model.selected, "c", "an unknown value is ignored")
    expectEq(model.move(by: 1), "c", "no wrap past the end")
    expectEq(model.move(by: -1), "b", "arrow left steps back")
    expectEq(model.selected, "b", "and selects it")
}

@Test @MainActor func selectionStaysPutAtTheEdgesAndWithoutOptions() {
    var pair = SegmentedSelection<String>(options: ["a", "b"], selected: "a")
    expectEq(pair.move(by: -1), "a", "no wrap before the start")
    var empty = SegmentedSelection<String>(options: [], selected: "a")
    expectEq(empty.move(by: 1), "a", "no options leaves the selection alone")
}

@MainActor private func segBitmap(_ view: some View, scheme: ColorScheme = .light) -> Data? {
    let renderer = ImageRenderer(content: view.padding(Space.x3).background(Semantic.background).environment(\.colorScheme, scheme))
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

@Test @MainActor func eachSelectionPaintsItsOwnSegment() throws {
    let options = AppearancePreference.allCases.map { ($0, $0.label) }
    var seen: [Data] = []
    for pref in AppearancePreference.allCases {
        let png = try #require(segBitmap(SegmentedToggle(options: options, selection: .constant(pref))), "render: \(pref)")
        #expect(!seen.contains(png), "\(pref) highlights a different segment")
        seen.append(png)
    }
}

@Test @MainActor func settingsAppearanceUsesTheToggleOptions() {
    expectEq(SettingsYouPage.appearanceOptions.map(\.0), AppearancePreference.allCases, "one segment per appearance")
    expectEq(SettingsYouPage.appearanceOptions.map(\.1), AppearancePreference.allCases.map(\.label), "labelled like the dropdown was")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func segmentedToggleGallery() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let options = AppearancePreference.allCases.map { ($0, $0.label) }
    let rows = VStack(spacing: Space.x3) {
        ForEach(AppearancePreference.allCases, id: \.self) { SegmentedToggle(options: options, selection: .constant($0)) }
    }
    for scheme in [ColorScheme.light, .dark] {
        let png = try #require(segBitmap(rows.frame(width: 300), scheme: scheme))
        try png.write(to: out.appendingPathComponent("win7-segmented-\(scheme == .dark ? "dark" : "light").png"))
    }
}
