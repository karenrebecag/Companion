import SwiftUI

/// One semantic ramp. Accent is the brand lime, not an asset catalog color.
public enum Tokens {
    public enum Color {
        public static let bg = SwiftUI.Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
        public static let surface = SwiftUI.Color(red: 1, green: 1, blue: 1)
        public static let fg = SwiftUI.Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
        public static let muted = SwiftUI.Color(red: 82 / 255, green: 82 / 255, blue: 82 / 255)
        public static let border = SwiftUI.Color(red: 229 / 255, green: 229 / 255, blue: 229 / 255)
        public static let accent = SwiftUI.Color(red: 201 / 255, green: 254 / 255, blue: 110 / 255)
        public static let destructive = SwiftUI.Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
    }

    public enum Space {
        public static let s4: CGFloat = 4
        public static let s8: CGFloat = 8
        public static let s12: CGFloat = 12
        public static let s16: CGFloat = 16
        public static let s24: CGFloat = 24
    }

    /// Nested `Type` collides with the metatype `Tokens.Type`.
    public enum Typography {
        public static let title = Font.system(.title)
        public static let body = Font.system(.body)
        public static let caption = Font.system(.caption)
    }
}
