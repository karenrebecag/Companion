import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Each permission needs a drawing of its own that reads at any size and in
// both schemes, because gap 5 reuses it beside the rows.

private struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// Share of pixels whose colour differs from `other` by more than
    /// antialiasing noise; `centerOnly` limits the count to the middle half,
    /// where the scene is and the frame's corners and ring are not.
    func difference(from other: Pixels, centerOnly: Bool = false) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        let inset = centerOnly ? width / 4 : 0
        var differing = 0
        var total = 0
        for y in inset..<(height - inset) {
            for x in inset..<(width - inset) {
                let i = (y * width + x) * 4
                let delta = (0..<3).reduce(0) { $0 + abs(Int(bytes[i + $1]) - Int(other.bytes[i + $1])) }
                total += 1
                if delta > 24 { differing += 1 }
            }
        }
        return Double(differing) / Double(max(total, 1))
    }
}

@MainActor private func pixels(_ view: some View, scheme: ColorScheme = .light) -> Pixels? {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { return nil }
    let width = cg.width
    let height = cg.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drew ? Pixels(width: width, height: height, bytes: bytes) : nil
}

/// What the art would be with no scene: the bare frame colour, same size.
@MainActor private func emptyFrame(_ size: CGFloat, scheme: ColorScheme = .light) -> Pixels? {
    pixels(Semantic.surfaceSecondary.frame(width: size, height: size), scheme: scheme)
}

@Test @MainActor func everyPermissionHasItsOwnGuideArt() throws {
    let kinds = WelcomePermission.allCases
    var rendered: [WelcomePermission: Pixels] = [:]
    for kind in kinds { rendered[kind] = try #require(pixels(PermissionGuideArt(kind: kind)), "render: \(kind)") }
    for (i, a) in kinds.enumerated() {
        for b in kinds[(i + 1)...] {
            let ratio = try #require(rendered[a]).difference(from: try #require(rendered[b]))
            #expect(ratio > 0.02, "\(a) and \(b) differ in only \(ratio) of their pixels")
        }
    }
}

@Test @MainActor func theArtKeepsItsSquareAtAnySizeAndIsNeverBlank() throws {
    #expect(PermissionGuideArt.defaultSize == 240, "the brief's guide size")
    let sizes: [CGFloat] = [120, PermissionGuideArt.defaultSize, 360]
    for kind in WelcomePermission.allCases {
        for size in sizes {
            let art = try #require(pixels(PermissionGuideArt(kind: kind, size: size)), "render \(kind) \(size)")
            #expect(art.width == Int(size) && art.height == Int(size), "\(kind) at \(size): not square")
            let bare = try #require(emptyFrame(size))
            #expect(art.difference(from: bare, centerOnly: true) > 0.03,
                    "\(kind) at \(size): nothing drawn inside the frame")
        }
    }
    let plain = try #require(pixels(PermissionGuideArt(kind: .microphone)))
    #expect(plain.width == Int(PermissionGuideArt.defaultSize), "default size is the guide size")
}

// The frame fill alone flips with the scheme, so light != dark proves little;
// the centre check against the bare frame of the same scheme is what shows
// the scene itself is drawn in both.
@Test @MainActor func theSceneIsDrawnInBothSchemes() throws {
    for kind in WelcomePermission.allCases {
        let light = try #require(pixels(PermissionGuideArt(kind: kind)))
        let dark = try #require(pixels(PermissionGuideArt(kind: kind), scheme: .dark))
        #expect(light.difference(from: dark) > 0.5, "\(kind): the scheme changes nothing")
        for (scheme, art) in [(ColorScheme.light, light), (.dark, dark)] {
            let bare = try #require(emptyFrame(PermissionGuideArt.defaultSize, scheme: scheme))
            #expect(art.difference(from: bare, centerOnly: true) > 0.03, "\(kind) \(scheme): scene missing")
        }
    }
}

// The single-element wiring (children ignored plus the label) is not asserted:
// NSHostingView accessibility needs a live window and is unstable offscreen.
@Test @MainActor func theGuideLabelIsLocalizedForEveryKind() async {
    for kind in WelcomePermission.allCases {
        let key = "welcome.guide." + kind.rawValue
        var texts: [AppLanguage: String] = [:]
        for language in [AppLanguage.es, .en] {
            texts[language] = await Localized.scoped(to: language) {
                let text = PermissionGuideArt.accessibilityText(for: kind)
                expectEq(text, Localized.string(key), "\(language) \(kind): label comes from the catalog")
                expect(!text.isEmpty && text != key, "\(language) \(kind): label is real copy")
                return text
            }
        }
        expect(texts[.es] != texts[.en], "\(kind): es and en say different things")
    }
}
