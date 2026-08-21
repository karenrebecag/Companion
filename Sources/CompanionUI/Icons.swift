import SwiftUI

public enum CompanionIcon: Sendable, CaseIterable, Equatable {
    case check, clock, cross, folder
}

/// SVG 24×24 coordinates, not a grid step — shrinking must not fatten the stroke.
public struct CompanionIconShape: Shape {
    public static let viewBox: CGFloat = 24
    // 1 pt identity; Shape.path is nonisolated, Stroke lives on MainActor.
    public static let lineWidth: CGFloat = 1
    public static let miterLimit: CGFloat = 10

    public var icon: CompanionIcon

    public init(icon: CompanionIcon) {
        self.icon = icon
    }

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / Self.viewBox
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var p = Path()
        switch icon {
        case .check:
            p.move(to: pt(4, 11.5))
            p.addLine(to: pt(10, 17.5))
            p.addLine(to: pt(21, 6.5))
        case .cross:
            p.move(to: pt(19, 5))
            p.addLine(to: pt(5, 19))
            p.move(to: pt(5, 5))
            p.addLine(to: pt(19, 19))
        case .clock:
            p.move(to: pt(11.5, 6))
            p.addLine(to: pt(11.5, 12.5))
            p.addLine(to: pt(16.5, 15))
            p.addEllipse(in: CGRect(
                x: rect.minX + 2 * s, y: rect.minY + 2 * s,
                width: 20 * s, height: 20 * s))
        case .folder:
            p.move(to: pt(2, 9))
            p.addLine(to: pt(2, 20))
            p.addLine(to: pt(22, 20))
            p.addLine(to: pt(22, 7))
            p.addLine(to: pt(13.5, 7))
            p.addLine(to: pt(11, 9))
            p.closeSubpath()
            p.move(to: pt(2, 9))
            p.addLine(to: pt(2, 4))
            p.addLine(to: pt(22, 4))
            p.addLine(to: pt(22, 7))
            for x in [4.5, 7.0, 9.5] {
                p.move(to: pt(x, 6))
                p.addLine(to: pt(x, 7))
            }
        }
        return p
    }
}

public struct IconGlyph: View {
    public static let defaultSize: CGFloat = 16

    let icon: CompanionIcon
    var size: CGFloat

    public init(icon: CompanionIcon, size: CGFloat = defaultSize) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        CompanionIconShape(icon: icon)
            .stroke(style: StrokeStyle(
                lineWidth: CompanionIconShape.lineWidth,
                lineCap: .butt,
                lineJoin: .miter,
                miterLimit: CompanionIconShape.miterLimit))
            .frame(width: size, height: size)
    }
}
