import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Space UI's thinking orb (MIT), ported: the scene is pure numbers, so the
// geometry is pinned here without a window.

@Test func thinkingOrbHasTheNineSpaceUIModes() {
    expectEq(ThinkingOrbMode.allCases.count, 9, "working, searching, solving, listening, connecting, weaving, composing, breathing, shaping")
    expectEq(ThinkingOrbMode.orbits.caption, "Working", "orbits is the working orb")
    expectEq(ThinkingOrbMode.ring.caption, "Thinking", "the breathing orb reads as thinking")
}

@Test func presetsInterpolateBetweenTheSmallAndLargeProfiles() {
    expect(abs(ThinkingOrbPreset.make(.orbits, pixelSize: 20).speed - 3.9) < 1e-9, "20 px is the small profile")
    expect(abs(ThinkingOrbPreset.make(.orbits, pixelSize: 64).speed - 1.885) < 1e-9, "64 px is the large profile")
    expect(abs(ThinkingOrbPreset.make(.orbits, pixelSize: 400).speed - 1.885) < 1e-9, "beyond 64 px stays large")
    let mid = ThinkingOrbPreset.make(.orbits, pixelSize: 42).speed
    expect(mid < 3.9 && mid > 1.885, "in between interpolates")
    let small = ThinkingOrbPreset.make(.globe, pixelSize: 20).options
    let large = ThinkingOrbPreset.make(.globe, pixelSize: 64).options
    expect((small["latRings"] ?? 0) < (large["latRings"] ?? 0), "a small orb draws fewer rings")
}

@Test func mathHelpersMatchTheSource() {
    expectEq(OrbMath.lerp(0, 10, 0.25), 2.5, "lerp")
    expectEq(OrbMath.clamp(-1), 0, "clamp low")
    expectEq(OrbMath.clamp(2), 1, "clamp high")
    expectEq(OrbMath.hash(1, 2), OrbMath.hash(1, 2), "hash is deterministic")
    expect(OrbMath.hash(1, 2) >= 0 && OrbMath.hash(1, 2) < 1, "hash is in 0..<1")
    for i in 0..<20 {
        let p = OrbMath.fibonacciSphere(i, 20)
        expect(abs(p.0 * p.0 + p.1 * p.1 + p.2 * p.2 - 1) < 1e-9, "fibonacci points sit on the unit sphere")
    }
    expect(abs(OrbMath.angleDelta(0.1, 2 * .pi + 0.1)) < 1e-9, "angleDelta wraps")
}

@Test func everyModeDrawsAValidDeterministicScene() {
    let size = 200.0
    for mode in ThinkingOrbMode.allCases {
        let preset = ThinkingOrbPreset.make(mode, pixelSize: size)
        let a = ThinkingOrbScene.render(mode, size: size, time: 1.3, options: preset.options)
        let b = ThinkingOrbScene.render(mode, size: size, time: 1.3, options: preset.options)
        expect(a == b, "\(mode): same time, same scene")
        expect(!a.dots.isEmpty, "\(mode): has dots")
        for dot in a.dots {
            expect((dot.a ?? 1) >= 0.02, "\(mode): faint dots are culled")
            expect(dot.r >= 0.25, "\(mode): radius has the floor")
            expect(dot.x > -size * 0.3 && dot.x < size * 1.3 && dot.y > -size * 0.3 && dot.y < size * 1.3,
                   "\(mode): dot stays near the canvas")
        }
        expect(zip(a.dots, a.dots.dropFirst()).allSatisfy { $0.z <= $1.z }, "\(mode): painter order, far to near")
        let later = ThinkingOrbScene.render(mode, size: size, time: 2.0, options: preset.options)
        expect(a != later, "\(mode): the scene moves")
    }
}

@Test func onlyTheConnectingOrbDrawsLinks() {
    let size = 200.0
    for mode in ThinkingOrbMode.allCases {
        let scene = ThinkingOrbScene.render(
            mode, size: size, time: 1, options: ThinkingOrbPreset.make(mode, pixelSize: size).options)
        if mode == .web {
            expect(!scene.lines.isEmpty, "web links its nodes")
        } else {
            expect(scene.lines.isEmpty, "\(mode): no links")
        }
    }
}

@Test func morphHoldsAShapeThenBlends() {
    let size = 200.0
    let options = ThinkingOrbPreset.make(.morph, pixelSize: size).options
    let hold = ThinkingOrbScene.render(.morph, size: size, time: 0.2, options: options)
    let hold2 = ThinkingOrbScene.render(.morph, size: size, time: 0.25, options: options)
    let blend = ThinkingOrbScene.render(.morph, size: size, time: 1.9, options: options)
    expect(maxShift(hold, hold2) < maxShift(hold, blend), "a held shape barely moves; a blend moves a lot")
}

private func maxShift(_ a: OrbPass, _ b: OrbPass) -> Double {
    zip(a.dots, b.dots).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
}

/// The voice states Companion already has drive which orb shows.
@Test func turnStatesMapToOrbModes() {
    expectEq(ThinkingOrbMode(state: .idle), .ring, "idle breathes")
    expectEq(ThinkingOrbMode(state: .connecting), .web, "connecting links")
    expectEq(ThinkingOrbMode(state: .listening), .wave, "listening ripples")
    expectEq(ThinkingOrbMode(state: .thinking), .orbits, "thinking works")
    expectEq(ThinkingOrbMode(state: .speaking), .ribbon, "speaking composes")
    expectEq(ThinkingOrbMode(state: .error), .morph, "an error reshapes")
}

@MainActor private func orbBitmap(_ mode: ThinkingOrbMode, surface: ThinkingOrbSurface = .ink) -> Data? {
    let view = ThinkingOrb(mode: mode, surface: surface, size: 160, paused: true)
        .background(surface == .ink ? Color.black : Color.white)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

@Test @MainActor func everyOrbPaintsAndDiffersFromTheOthers() throws {
    var seen: [Data] = []
    for mode in ThinkingOrbMode.allCases {
        let png = try #require(orbBitmap(mode), "render: \(mode)")
        #expect(!seen.contains(png), "\(mode) looks like another orb")
        seen.append(png)
    }
    let ink = try #require(orbBitmap(.orbits, surface: .ink))
    let paper = try #require(orbBitmap(.orbits, surface: .paper))
    #expect(ink != paper, "ink and paper surfaces invert the dots")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func thinkingOrbGallery() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(160)), count: 3), spacing: 12) {
        ForEach(ThinkingOrbMode.allCases, id: \.self) { ThinkingOrb(mode: $0, surface: .ink, size: 160, paused: true) }
    }
    .padding(16).background(Color.black)
    let renderer = ImageRenderer(content: grid)
    renderer.scale = 2
    let tiff = try #require(renderer.nsImage?.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: out.appendingPathComponent("spaceui-thinking-orbs.png"))
}

/// Reference values computed by running Space UI's math.ts in node.
@Test func mathMatchesTheTypeScriptReference() {
    expect(abs(OrbMath.hash(1, 2) - 0.073904103617678629) < 1e-12, "hash")
    expect(abs(OrbMath.valueNoise2D(0.5, 0.5) - 0.46117289151629848) < 1e-12, "valueNoise2D at a cell centre")
    expect(abs(OrbMath.valueNoise2D(3.7, 1.2) - 0.36359922170482062) < 1e-12, "valueNoise2D off-grid")
    expectEq(OrbMath.fract(-0.25), 0.75, "fract of a negative wraps up")
    let p = OrbRotation(rotY: .pi / 2, rotX: 0, cx: 0, cy: 0, scale: 1).project(1, 0, 0)
    expect(abs(p.x) < 1e-12 && abs(p.y) < 1e-12 && abs(p.z + 1) < 1e-12, "a quarter turn about Y sends +x to -z")
}

/// Every hand-copied profile, at both ends, against the TS tables.
@Test func presetSpeedsMatchTheTypeScriptTables() {
    let table: [(ThinkingOrbMode, Double, Double)] = [
        (.orbits, 3.9, 1.885), (.globe, 2.665, 2.015), (.rubik, 1.95, 1.82), (.wave, 3.998, 4.388),
        (.web, 6.63, 3.315), (.braid, 2.75, 1.625), (.ribbon, 3.12, 2.34), (.ring, 3.78, 3.24),
        (.morph, 2.08, 2.405),
    ]
    for (mode, small, large) in table {
        expect(abs(ThinkingOrbPreset.make(mode, pixelSize: 20).speed - small) < 1e-9, "\(mode): small speed")
        expect(abs(ThinkingOrbPreset.make(mode, pixelSize: 64).speed - large) < 1e-9, "\(mode): large speed")
    }
    let ribbon = ThinkingOrbPreset.make(.ribbon, pixelSize: 20).options
    expectEq(ribbon["bandMul"], 4.94, "ribbon carries its band multiplier")
    expectEq(ThinkingOrbPreset.make(.globe, pixelSize: 20).options["scanMul"], 4.335, "globe carries its scan multiplier")
    expectEq(ThinkingOrbPreset.make(.morph, pixelSize: 20).options["spread"], 1.45, "morph carries its spread")
    expect((ThinkingOrbPreset.make(.ring, pixelSize: 20).options["lanes"] ?? 0) >= 2, "scaled counts keep their floor of 2")
}

/// Paused and reduce-motion draw the source's static frame whatever the
/// clock says; running time follows the clock and the speed.
@Test func aStillOrbIgnoresTheClock() {
    expectEq(ThinkingOrb.sceneTime(still: true, now: 10, speed: 1, presetSpeed: 2), 1.2, "still: 0.6 x the preset speed")
    expectEq(ThinkingOrb.sceneTime(still: true, now: 99, speed: 3, presetSpeed: 2), 1.2, "still: the clock and speed do not matter")
    expectEq(ThinkingOrb.sceneTime(still: false, now: 10, speed: 1, presetSpeed: 2), 20, "running: now x speed x preset")
    expectEq(ThinkingOrb.sceneTime(still: false, now: 10, speed: 0, presetSpeed: 2), 10 * 0.05 * 2, "speed has the source's floor of 0.05")
}

@Test func theOrbRedrawsAtTheSourcesFrameRate() {
    expectEq(ThinkingOrb.frameInterval, 1.0 / 45, "Space UI throttles to about 45 fps")
}
