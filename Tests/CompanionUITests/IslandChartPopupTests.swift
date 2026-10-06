import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import SwiftUI
import Testing

// A chart that arrives on the channel and one that arrives in a companion:
// fence are the same picture in the answer popup. The light card is the
// window's, so a light slab here means the popup took the wrong path
// (local reference).

private func salesChart() -> ChartBlock {
    ChartBlock(
        title: "Ventas", kind: .bar, unit: "QMs",
        labels: ["Ene", "Feb", "Mar"],
        series: [.init(name: "Q", values: [3, 5, 4])])
}

private func attachedPopup(_ block: ChartBlock) -> some View {
    AnswerPopupView(
        blocks: [],
        card: Card(payload: .chart(block), source: .tool),
        screenWidth: 1800, maxHeight: 700, onClose: {})
}

private func fencePopup(_ block: ChartBlock) -> some View {
    AnswerPopupView(
        blocks: [.card(.chart(block))],
        card: nil,
        screenWidth: 1800, maxHeight: 700, onClose: {})
}

@Test @MainActor func attachedChartInThePopupUsesTheIslandLook() throws {
    let block = salesChart()
    let attached = try #require(hostedRep(attachedPopup(block)))
    let fence = try #require(hostedRep(fencePopup(block)))
    let attachedInk = inkShares(attached)
    let fenceInk = inkShares(fence)
    expect(attachedInk.white < 0.15,
           "la gráfica del canal en el popup no es la tarjeta clara")
    expect(attachedInk.dark > 0.45,
           "la gráfica del canal usa la superficie oscura de la isla")
    expect(abs(attachedInk.white - fenceInk.white) < 0.05,
           "canal y fence se ven igual en el popup")
    expect(abs(attachedInk.dark - fenceInk.dark) < 0.05,
           "canal y fence comparten la tinta de la isla")
}

@Test @MainActor func fenceChartInThePopupStaysTheIslandLook() throws {
    let block = salesChart()
    let fence = try #require(hostedRep(
        AnswerBlockView(block: .card(.chart(block))).frame(width: 420)))
    let island = try #require(hostedRep(
        IslandChartVisual(block: block).frame(width: 420)))
    expectEq(fence.pixelsWide, island.pixelsWide, "el fence conserva el ancho de la isla")
    expectEq(fence.pixelsHigh, island.pixelsHigh, "el fence conserva el alto de la isla")
    expect(pixelGap(fence, island) < 0.02,
           "el fence sigue siendo la gráfica de la isla, no la tarjeta clara")
}

private struct InkShares {
    var white: Double
    var dark: Double
}

/// The island surface is near-black and the window card is opaque white.
/// Shares of those two, not a stored image, so a palette shift still fails
/// the wrong path and a chart mark does not have to match pixel for pixel.
private func inkShares(_ rep: NSBitmapImageRep) -> InkShares {
    let step = 4
    var opaque = 0
    var white = 0
    var dark = 0
    var y = 0
    while y < rep.pixelsHigh {
        var x = 0
        while x < rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
               color.alphaComponent > 0.5 {
                opaque += 1
                let lum = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                if lum > 0.85 { white += 1 }
                if lum < 0.2 { dark += 1 }
            }
            x += step
        }
        y += step
    }
    guard opaque > 0 else { return InkShares(white: 1, dark: 0) }
    return InkShares(
        white: Double(white) / Double(opaque),
        dark: Double(dark) / Double(opaque))
}

/// How much of the two pictures disagrees. Zero is the same view.
private func pixelGap(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, a.pixelsWide > 0 else { return 1 }
    let step = 2
    var seen = 0
    var differ = 0
    var y = 0
    while y < a.pixelsHigh {
        var x = 0
        while x < a.pixelsWide {
            let left = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            let right = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            seen += 1
            if let left, let right {
                if abs(left.redComponent - right.redComponent) > 0.04
                    || abs(left.greenComponent - right.greenComponent) > 0.04
                    || abs(left.blueComponent - right.blueComponent) > 0.04
                    || abs(left.alphaComponent - right.alphaComponent) > 0.04 {
                    differ += 1
                }
            } else if left != nil || right != nil {
                differ += 1
            }
            x += step
        }
        y += step
    }
    guard seen > 0 else { return 1 }
    return Double(differ) / Double(seen)
}

@MainActor private func hostedRep(_ view: some View) -> NSBitmapImageRep? {
    let hosting = NSHostingView(rootView: view
        .environment(\.colorScheme, .light)
        .environment(\.islandChartSweeps, false))
    let fitted = hosting.fittingSize
    hosting.frame = NSRect(x: 0, y: 0, width: max(fitted.width, 1), height: max(fitted.height, 1))
    let window = NSWindow(
        contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    defer { window.close() }
    hosting.appearance = NSAppearance(named: .aqua)
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
          rep.pixelsWide > 0, rep.pixelsHigh > 0
    else { return nil }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    return rep
}
