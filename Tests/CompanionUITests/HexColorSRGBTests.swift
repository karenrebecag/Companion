import AppKit
@testable import CompanionUI
import Testing

// Every palette hex is a CSS value (Incredible, Tailwind, Apple's system
// colours), and CSS hex is sRGB. A swatch must read back as exactly the hex
// it was written as, or every token renders a little off its source.

private let hexes = ["E3F1E8", "0A84FF", "727276", "FF375F", "000000", "FFFFFF"]

@Test(arguments: hexes)
@MainActor func aHexReadsBackExactlyInSRGB(_ hex: String) {
    #expect(srgbHex(NSColor.fromHex(hex)) == hex)
    #expect(srgbHex(NSColor.fromHex("#" + hex)) == hex)
    #expect(srgbHex(Swatch(hex).ns) == hex)
}

@Test @MainActor func paletteTokensReadBackAsTheirHex() {
    #expect(srgbHex(Palette.surfaceSecondary.ns) == "F9F9F9")
    #expect(srgbHex(Palette.textMuted.ns) == "727276")
    #expect(srgbHex(Accent.blue.ns) == "0A84FF")
    #expect(srgbHex(Neutral.n850.ns) == "1A1A1A")
}

private func srgbHex(_ color: NSColor) -> String {
    guard let c = color.usingColorSpace(.sRGB) else { return "unconvertible" }
    return [c.redComponent, c.greenComponent, c.blueComponent]
        .map { String(format: "%02X", Int(($0 * 255).rounded())) }
        .joined()
}
