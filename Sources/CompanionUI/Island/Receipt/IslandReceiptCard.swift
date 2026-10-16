import CompanionCore
import SwiftUI

enum IslandReceipt {
    /// "Done and verified" only where a read-back verified it; otherwise "Done".
    static func checkLabel(_ line: ReceiptLine, language: AppLanguage) -> String {
        Localized.string(line.verified ? "island.receipt.check" : "island.receipt.done", language: language)
    }

    /// The short word on a ledger row's pill; VoiceOver gets `checkLabel`.
    static func pillLabel(_ line: ReceiptLine, language: AppLanguage) -> String {
        Localized.string(line.verified ? "island.receipt.verified" : "island.receipt.done", language: language)
    }

    /// What VoiceOver says when the card appears: the title, then each line.
    /// The block announces a change of state, not its own arrival.
    static func announcement(_ receipt: ActionReceipt, language: AppLanguage) -> String {
        ([Localized.string("island.receipt.title", language: language)] + receipt.lines)
            .joined(separator: ". ")
    }
}

/// The receipt as a ledger document: what was asked on top with the mark of
/// a finished job, then one row per thing done, each with the proof it earned.
struct IslandReceiptDoc: View {
    /// Nil: a receipt names nothing of the user's own, the ledger's label says what it is.
    let title: String?
    let receipt: ActionReceipt
    let maxHeight: CGFloat
    var onDismiss: (() -> Void)?
    var onContinue: (() -> Void)?

    var body: some View {
        IslandDocFrame(accent: DocCardInk.receipt, maxHeight: maxHeight, onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: DocReceiptMetrics.ledgerTop) {
                head
                ledger
            }
        }
    }

    private var head: some View {
        HStack(alignment: .center, spacing: DocReceiptMetrics.headGap) {
            identity
            VStack(alignment: .leading, spacing: DocReceiptMetrics.subGap) {
                if let title {
                    Text(title)
                        .font(Fonts.geist(DocReceiptMetrics.titleSize).weight(.semibold))
                        .tracking(DocReceiptMetrics.titleSize * DocReceiptMetrics.titleTracking)
                        .foregroundStyle(Color.white.opacity(DocCardInk.title))
                        .accessibilityAddTraits(.isHeader)
                }
                Text(Localized.string("island.receipt.title"))
                    .font(Fonts.geist(DocReceiptMetrics.subSize))
                    .foregroundStyle(Color.white.opacity(DocCardInk.secondary))
            }
            Spacer(minLength: Space.none)
            if let onContinue {
                DocChip(scale: .action, action: onContinue) { Text(Localized.string("island.result.continue")) }
            }
        }
        .padding(.trailing, onDismiss == nil || onContinue != nil ? Space.none : DocCardMetrics.toolReserve)
    }

    private var identity: some View {
        Image(systemName: "checklist")
            .font(Fonts.geist(DocReceiptMetrics.tileMark))
            .foregroundStyle(DocCardInk.receipt.color)
            .frame(width: DocReceiptMetrics.tile, height: DocReceiptMetrics.tile)
            .background(RoundedRectangle(cornerRadius: DocReceiptMetrics.tileRadius, style: .continuous)
                .fill(Color.white.opacity(DocCardInk.tileFill)))
            .overlay(alignment: .bottomTrailing) { DocCheckBadge().offset(x: DocReceiptMetrics.checkOffset,
                                                                         y: DocReceiptMetrics.checkOffset) }
            .accessibilityHidden(true)
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: DocReceiptMetrics.rowSpacing) {
            ForEach(Array(receipt.entries.enumerated()), id: \.offset) { index, entry in
                row(entry)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Color.white.opacity(DocCardInk.rowLine)).frame(height: Stroke.hairline) }
                    }
                    .modifier(DocFadeIn(index: index))
            }
        }
        .padding(.leading, DocReceiptMetrics.ledgerIndent)
    }

    private func row(_ entry: ReceiptLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DocReceiptMetrics.rowGap) {
            Text(entry.text)
                .font(Fonts.geist(DocReceiptMetrics.valueSize))
                .foregroundStyle(Color.white.opacity(DocCardInk.value))
                .docLineBox(size: DocReceiptMetrics.valueSize, leading: DocReceiptMetrics.valueLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(IslandReceipt.pillLabel(entry, language: Localized.language()))
                .font(Fonts.geist(DocReceiptMetrics.pillSize).weight(.semibold))
                .foregroundStyle(entry.verified ? DocCardInk.pillDone.color : Color.white.opacity(DocCardInk.label))
                .padding(.horizontal, DocReceiptMetrics.pillPadX)
                .padding(.vertical, DocReceiptMetrics.pillPadY)
                .background(Capsule().fill(entry.verified
                    ? DocCardInk.pillDone.color.opacity(DocCardInk.pillFill)
                    : Color.white.opacity(DocCardInk.pillNeutralFill)))
        }
        .padding(.vertical, DocReceiptMetrics.rowPadY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.text) \(IslandReceipt.checkLabel(entry, language: Localized.language()))") // token-exempt: built from localized parts
    }
}

/// The small check on the tile's corner: it draws itself in once, a ring of
/// the card's own fill keeping it clear of the tile under it.
private struct DocCheckBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        DocCheckStroke()
            .trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
            .stroke(DocCardInk.checkMark.color,
                    style: StrokeStyle(lineWidth: Stroke.medium, lineCap: .round, lineJoin: .round))
            .frame(width: DocReceiptMetrics.checkMark, height: DocReceiptMetrics.checkMark)
            .frame(width: DocReceiptMetrics.check, height: DocReceiptMetrics.check)
            .background(Circle().fill(DocCardInk.checkFill.color))
            .overlay(Circle().strokeBorder(DocCardInk.surface.color, lineWidth: DocReceiptMetrics.checkRing))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(MotionCurve.animation(MotionCurve.standard, DocReceiptMetrics.checkDraw)) { drawn = true }
            }
    }
}

private struct DocCheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.85))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.2))
        return path
    }
}
