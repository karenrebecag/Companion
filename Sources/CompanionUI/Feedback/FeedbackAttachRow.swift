import SwiftUI

/// One attach button: a capsule chip with an icon and its word.
struct FeedbackAttachChip: View {
    let key: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(Localized.string(key), systemImage: symbol) }
            .buttonStyle(CapsuleChipStyle(ink: .choice(selected: false), density: .compact))
            // A button keeps its label on one line; the row wraps whole buttons.
            .lineLimit(1)
            .fixedSize()
    }
}

/// The three ways to attach a screenshot.
struct FeedbackAttachRow: View {
    let onRegion: () -> Void
    let onFile: () -> Void
    let onPaste: () -> Void

    var body: some View {
        WrappingRow(spacing: Space.x2) {
            FeedbackAttachChip(key: "feedback.capture.add", symbol: "camera.viewfinder", action: onRegion)
                .accessibilityHint(Localized.string("feedback.note.captureAction"))
            FeedbackAttachChip(key: "feedback.capture.file", symbol: "photo", action: onFile)
            FeedbackAttachChip(key: "feedback.capture.paste", symbol: "doc.on.clipboard", action: onPaste)
        }
    }
}

/// Lays children left to right at their ideal size and moves a whole child to
/// the next line when it would overflow, so a narrow width never squeezes a
/// label into two lines.
private struct WrappingRow: Layout {
    let spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Subviews.Element]] {
        var rows: [[Subviews.Element]] = [[]]
        var used: CGFloat = 0
        for view in subviews {
            let need = view.sizeThatFits(.unspecified).width
            if used > 0, used + spacing + need > width { rows.append([]); used = 0 }
            used += (used > 0 ? spacing : 0) + need
            rows[rows.count - 1].append(view)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var widest: CGFloat = 0
        var total: CGFloat = 0
        for row in rows(subviews, width: proposal.width ?? .infinity) {
            var rowWidth: CGFloat = 0
            var rowHeight: CGFloat = 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                rowWidth += size.width
                rowHeight = max(rowHeight, size.height)
            }
            widest = max(widest, rowWidth + spacing * CGFloat(row.count - 1))
            total += rowHeight
        }
        let lines = CGFloat(rows(subviews, width: proposal.width ?? .infinity).count)
        return CGSize(width: widest, height: total + spacing * (lines - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing
        }
    }
}
