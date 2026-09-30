import CompanionCore
import SwiftUI

public enum SyntaxPalette: Sendable {
    public enum Role: Sendable, Equatable {
        case foreground, mutedForeground, purple, green, orange, blue, pink
    }

    public static func role(for kind: SyntaxKind) -> Role {
        switch kind {
        case .text: .foreground
        case .keyword: .purple
        case .string: .green
        case .comment: .mutedForeground
        case .number: .orange
        case .typeName: .blue
        case .attr: .pink
        }
    }

    public static func color(for kind: SyntaxKind) -> Color {
        switch role(for: kind) {
        case .foreground: Semantic.foreground
        case .mutedForeground: Semantic.mutedForeground
        case .purple: Accent.purple.color
        case .green: Accent.green.color
        case .orange: Accent.orange.color
        case .blue: Accent.blue.color
        case .pink: Accent.pink.color
        }
    }
}

public enum SyntaxHighlighter {
    public static func attributed(
        _ source: String, language: String
    ) -> AttributedString {
        var out = AttributedString()
        for token in SyntaxTokenizer.tokenize(source, language: language) {
            var piece = AttributedString(token.text)
            piece.foregroundColor = SyntaxPalette.color(for: token.kind)
            out.append(piece)
        }
        return out
    }
}
