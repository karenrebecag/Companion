import SwiftUI

enum RotationDirection {
    case clockwise
    case counterClockwise

    var multiplier: Double {
        switch self {
        case .clockwise: 1
        case .counterClockwise: -1
        }
    }
}

struct RotatingGlowView: View {
    @State private var rotation: Double = 0

    private let color: Color
    private let rotationSpeed: Double
    private let direction: RotationDirection

    init(
        color: Color,
        rotationSpeed: Double = 30,
        direction: RotationDirection
    ) {
        self.color = color
        self.rotationSpeed = rotationSpeed
        self.direction = direction
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            Circle()
                .fill(color)
                .mask {
                    ZStack {
                        Circle()
                            .frame(width: size, height: size)
                            .blur(radius: size * 0.16)
                        Circle()
                            .frame(width: size * 1.31, height: size * 1.31)
                            .offset(y: size * 0.31)
                            .blur(radius: size * 0.16)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    guard rotationSpeed > 0, rotationSpeed.isFinite else { return }
                    withAnimation(
                        .linear(duration: 360 / rotationSpeed)
                        .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360 * direction.multiplier
                    }
                }
        }
    }
}
