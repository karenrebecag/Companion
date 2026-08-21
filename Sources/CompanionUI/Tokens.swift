import AppKit
import SwiftUI

// MARK: - Extension to NSColor for hex parsing

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        let v = UInt64(s, radix: 16) ?? 0
        return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255,
                       alpha: 1)
    }
}

// MARK: - Rampa neutral completa con tema oscuro
/// Cada paso tiene un uso específico: página, superficies, texto, bordes.
public enum Neutral {
    public static let n50  = Swatch("FAFAFA")
    public static let n100 = Swatch("F5F5F5")
    public static let n150 = Swatch("EFEFEF")
    public static let n200 = Swatch("E5E5E5")
    public static let n300 = Swatch("D4D4D4")
    public static let n400 = Swatch("A3A3A3")
    public static let n500 = Swatch("737373")
    public static let n600 = Swatch("525252")
    public static let n700 = Swatch("404040")
    public static let n770 = Swatch("2E2E2E")
    public static let n800 = Swatch("262626")
    public static let n850 = Swatch("1A1A1A")
    public static let n870 = Swatch("191919")
    public static let n900 = Swatch("171717")
    public static let n950 = Swatch("0A0A0A")
    public static let white = Swatch("FFFFFF")
    public static let black = Swatch("000000")
}

/// Acentos nombrados siguiendo tintes de sistema (Reminders).
/// El lima es la marca de Companion, no un verde de Apple.
public enum Accent {
    public static let lime   = Swatch("C9FE6E")
    public static let blue   = Swatch("0A84FF")
    public static let green  = Swatch("30D158")
    public static let yellow = Swatch("FFD60A")
    public static let pink   = Swatch("FF375F")
    public static let orange = Swatch("FF9F0A")
    public static let purple = Swatch("BF5AF2")
}

/// Color de énfasis elegible desde Ajustes.
/// `standard` queda como rawValue para no invalidar lo ya persistido.
