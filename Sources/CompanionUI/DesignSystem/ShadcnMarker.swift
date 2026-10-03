import SwiftUI

// shadcn's Marker: a muted line of text, optionally flanked by rules or
// underlined by one, that says where the conversation is (a day, a handoff).

package enum MarkerVariant: Sendable, CaseIterable {
    case `default`, separator, border

    package var drawsRules: Bool { self == .separator }
    package var drawsBottomBorder: Bool { self == .border }
}

package struct Marker: View {
    let title: String
    let systemImage: String?
    let variant: MarkerVariant

    package init(_ title: String, systemImage: String? = nil, variant: MarkerVariant = .default) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
    }

    package var body: some View {
        HStack(spacing: Space.x2) {
            if variant.drawsRules { rule }
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(title)
            if variant.drawsRules { rule }
            if !variant.drawsRules { Spacer(minLength: Space.none) }
        }
        .font(Fonts.sans(TypeSize.rowTitle))
        .foregroundStyle(Semantic.mutedForeground)
        .padding(.bottom, variant.drawsBottomBorder ? Space.x2 : Space.none)
        .overlay(alignment: .bottom) {
            if variant.drawsBottomBorder { Semantic.border.frame(height: Stroke.hairline) }
        }
    }

    private var rule: some View {
        Semantic.border.frame(height: Stroke.hairline)
    }
}
