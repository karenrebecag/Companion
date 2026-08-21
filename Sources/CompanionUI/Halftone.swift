import SwiftUI

/// Identity texture. Opacity stays very low so it never fights copy or cards.
struct HalftoneOverlay: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = (scheme == .dark ? Color.white : Color.black).opacity(0.035)
        Canvas { context, size in
            let cell: CGFloat = 11
            let radius: CGFloat = 0.7
            var y: CGFloat = 0
            var row = 0
            while y < size.height + cell {
                var x = row.isMultiple(of: 2) ? CGFloat(0) : cell / 2
                while x < size.width + cell {
                    let t = y / max(size.height, 1)
                    let r = radius * (1.15 - 0.45 * t)
                    let rect = CGRect(
                        x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(ink))
                    x += cell
                }
                y += cell
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
