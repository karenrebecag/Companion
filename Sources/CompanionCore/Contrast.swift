import Foundation

/// WCAG contrast on hex swatches. Dynamic NSColor is unstable under swift test.
public enum Contrast: Sendable {
    public static let aaNormal = 4.5

    public static func ratio(hex a: String, hex b: String) -> Double {
        let la = luminance(rgb(a))
        let lb = luminance(rgb(b))
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func passesAA(hex a: String, hex b: String) -> Bool {
        ratio(hex: a, hex: b) >= aaNormal
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        let v = UInt64(s, radix: 16) ?? 0
        return (
            Double((v >> 16) & 0xFF) / 255,
            Double((v >> 8) & 0xFF) / 255,
            Double(v & 0xFF) / 255
        )
    }

    private static func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0)
            + 0.7152 * channel(rgb.1)
            + 0.0722 * channel(rgb.2)
    }
}
