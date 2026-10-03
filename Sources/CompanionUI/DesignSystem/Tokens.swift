import AppKit
import SwiftUI

// MARK: - Extension to NSColor for hex parsing

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        let v = UInt64(s, radix: 16) ?? 0
        // CSS hex is sRGB; calibratedRed (generic RGB) rendered every
        // palette value lighter than its source.
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255,
                       alpha: 1)
    }
}

// MARK: - Rampa neutral completa con tema oscuro
/// Cada paso tiene un uso específico: página, superficies, texto, bordes.
package enum Neutral {
    package static let n50  = Swatch("FAFAFA")
    package static let n100 = Swatch("F5F5F5")
    package static let n150 = Swatch("EFEFEF")
    package static let n200 = Swatch("E5E5E5")
    package static let n300 = Swatch("D4D4D4")
    package static let n400 = Swatch("A3A3A3")
    package static let n500 = Swatch("737373")
    package static let n600 = Swatch("525252")
    package static let n700 = Swatch("404040")
    package static let n770 = Swatch("2E2E2E")
    package static let n800 = Swatch("262626")
    package static let n850 = Swatch("1A1A1A")
    package static let n870 = Swatch("191919")
    package static let n900 = Swatch("171717")
    package static let n950 = Swatch("0A0A0A")
    package static let white = Swatch("FFFFFF")
    package static let black = Swatch("000000")
}

/// Acentos nombrados siguiendo tintes de sistema (Reminders).
/// El lima es la marca de Companion, no un verde de Apple.
package enum Accent {
    package static let lime   = Swatch("C9FE6E")
    package static let blue   = Swatch("0A84FF")
    package static let green  = Swatch("30D158")
    package static let yellow = Swatch("FFD60A")
    package static let pink   = Swatch("FF375F")
    package static let orange = Swatch("FF9F0A")
    package static let purple = Swatch("BF5AF2")
    package static let teal = Swatch("5AC8FA")
}
