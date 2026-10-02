import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import SwiftUI
import Testing

// Brief isla-maquetacion-incredible, F1: the chip took whatever width it was
// offered up to its cap, so one short name in a wide row became a 230 bar.
// It hugs its text and only a long one stops at the cap, with an ellipsis.

@MainActor private func chipWidth(_ text: String, offered: CGFloat) -> CGFloat {
    let controller = NSHostingController(rootView: ReferentChip(text: text))
    return controller.sizeThatFits(in: NSSize(width: offered, height: 100)).width
}

@MainActor private func chipHeight(_ text: String, offered: CGFloat) -> CGFloat {
    let controller = NSHostingController(rootView: ReferentChip(text: text))
    return controller.sizeThatFits(in: NSSize(width: offered, height: 1_000)).height
}

@MainActor private func reelWidth(_ touched: [String], offered: CGFloat) -> CGFloat {
    let reel = HStack(spacing: Space.x1) { ForEach(touched, id: \.self) { ReferentChip(text: $0) } }
    return NSHostingController(rootView: reel).sizeThatFits(in: NSSize(width: offered, height: 100)).width
}

@Test @MainActor func aShortChipHugsItsText() {
    let short = chipWidth("Notes", offered: 460)
    let intrinsic = chipWidth("Notes", offered: .greatestFiniteMagnitude)
    expectEq(short, intrinsic, "Notes en una fila de 460: su ancho propio, no 230 (\(short))")
    expect(short < ReferentChipMetrics.maxWidth, "Notes: por debajo del tope")
    expectEq(short, chipWidth("Notes", offered: 300), "el ancho no depende de lo ofrecido")
}

@Test @MainActor func aLongChipStopsAtTheCapOnOneLine() {
    let long = String(repeating: "a", count: 400)
    expectEq(chipWidth(long, offered: 460), ReferentChipMetrics.maxWidth, "400 caracteres: el tope")
    expect(chipWidth(long, offered: 120) <= 120, "con menos sitio, cabe en lo ofrecido")
    // Same height as a short chip: one line, cut with an ellipsis, never wrapped.
    expectEq(chipHeight(long, offered: 460), chipHeight("Notes", offered: 460), "400 caracteres: una sola línea")
}

// The status line and the reel judge a blank target the same way.
@Test @MainActor func theStatusLineDropsBlankTargetsToo() {
    let parts = ReferentLine.parts(["Notes", "  ", "\n"], language: .es)
    expectEq(parts.referents, ["Notes"], "línea de estado: sin chips en blanco")
    expectEq(ReferentLine.parts(["  "], language: .en).referents, [], "solo blancos: ningún chip")
}

@Test @MainActor func twoChipsShareARowAtTheirOwnWidths() {
    let notes = chipWidth("Notes", offered: 460)
    let safari = chipWidth("Safari", offered: 460)
    let row = reelWidth(["Notes", "Safari"], offered: 460)
    expectEq(row, notes + Space.x1 + safari, "dos chips: cada uno su ancho, no media fila")
}
