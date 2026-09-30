import CompanionCore
import SwiftUI

package enum SyntaxPalette: Sendable {
    package enum Role: Sendable, Equatable {
        case foreground, mutedForeground, purple, green, orange, blue, pink
    }

    package static func role(for kind: SyntaxKind) -> Role {
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

    package static func color(for kind: SyntaxKind) -> Color {
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

package enum SyntaxHighlighter {
    package static func attributed(
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
