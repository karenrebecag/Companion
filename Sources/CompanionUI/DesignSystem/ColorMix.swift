import Foundation

/// CSS `color-mix(in oklab, top amount%, bottom)` on two opaque swatches.
/// OKLab, not sRGB, because that is the space the mix it ports is written
/// in: an sRGB average of two greys lands visibly darker.
package enum ColorMix {
    package static func oklab(_ top: Swatch, over bottom: Swatch, amount: Double) -> Swatch {
        let a = lab(rgb(top)), b = lab(rgb(bottom))
        let t = min(max(amount, 0), 1)
        let mixed = (0..<3).map { a[$0] * t + b[$0] * (1 - t) }
        let out = srgb(mixed).map { component -> String in
            String(format: "%02X", Int((min(max(component, 0), 1) * 255).rounded()))
        }
        return Swatch(out.joined())
    }

    private static func rgb(_ swatch: Swatch) -> [Double] {
        let value = UInt64(swatch.hex, radix: 16) ?? 0
        return [16, 8, 0].map { Double((value >> UInt64($0)) & 0xFF) / 255 }
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    // Björn Ottosson's published OKLab matrices (the ones CSS Color 4 uses).
    private static func lab(_ c: [Double]) -> [Double] {
        let r = linear(c[0]), g = linear(c[1]), b = linear(c[2])
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
    }

    private static func srgb(_ c: [Double]) -> [Double] {
        let l = pow(c[0] + 0.3963377774 * c[1] + 0.2158037573 * c[2], 3)
        let m = pow(c[0] - 0.1055613458 * c[1] - 0.0638541728 * c[2], 3)
        let s = pow(c[0] - 0.0894841775 * c[1] - 1.2914855480 * c[2], 3)
        return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s].map { encoded(max($0, 0)) }
    }
}
