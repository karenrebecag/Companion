import SwiftUI

public struct OrbView: View {
    private let config: OrbConfiguration

    public init(configuration: OrbConfiguration = OrbConfiguration()) {
        self.config = configuration
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                if config.showBackground {
                    LinearGradient(
                        colors: config.backgroundColors,
                        startPoint: .bottom,
                        endPoint: .top)
                }
                baseDepthGlows(size: size)
                if config.showWavyBlobs {
                    wavyBlob
                    wavyBlobTwo
                }
                if config.showGlowEffects {
                    coreGlowEffects(size: size)
                }
                if config.showParticles {
                    particleView
                        .frame(maxWidth: size, maxHeight: size)
                }
            }
            .overlay { realisticInnerGlows }
            .mask { Circle() }
            .aspectRatio(1, contentMode: .fit)
            .modifier(
                RealisticShadowModifier(
                    colors: config.showShadow ? config.backgroundColors : [.clear],
                    radius: size * 0.08)
            )
        }
    }

    private var particleView: some View {
        ZStack {
            ParticlesView(
                color: config.particleColor,
                speedRange: 10...20,
                sizeRange: 0.5...1,
                particleCount: 10,
                opacityRange: 0...0.3
            )
            .blur(radius: 1)
            ParticlesView(
                color: config.particleColor,
                speedRange: 20...30,
                sizeRange: 0.2...1,
                particleCount: 10,
                opacityRange: 0.3...0.8
            )
        }
        .blendMode(.plusLighter)
    }

    private var wavyBlob: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            RotatingGlowView(
                color: .white.opacity(0.75),
                rotationSpeed: config.speed * 1.5,
                direction: .clockwise)
                .mask {
                    WavyBlobView(
                        color: .white,
                        loopDuration: loopDuration(1.75))
                        .frame(maxWidth: size * 1.875)
                        .offset(x: 0, y: size * 0.31)
                }
                .blur(radius: 1)
                .blendMode(.plusLighter)
        }
    }

    private var wavyBlobTwo: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            RotatingGlowView(
                color: .white,
                rotationSpeed: config.speed * 0.75,
                direction: .counterClockwise)
                .mask {
                    WavyBlobView(
                        color: .white,
                        loopDuration: loopDuration(2.25))
                        .frame(maxWidth: size * 1.25)
                        .rotationEffect(.degrees(90))
                        .offset(x: 0, y: size * -0.31)
                }
                .opacity(0.5)
                .blur(radius: 1)
                .blendMode(.plusLighter)
        }
    }

    private func loopDuration(_ factor: Double) -> Double {
        guard config.speed > 0 else { return 0 }
        return 60 / config.speed * factor
    }

    private func coreGlowEffects(size: CGFloat) -> some View {
        ZStack {
            RotatingGlowView(
                color: config.glowColor,
                rotationSpeed: config.speed * 3,
                direction: .clockwise)
                .blur(radius: size * 0.08)
                .opacity(config.coreGlowIntensity)
            RotatingGlowView(
                color: config.glowColor,
                rotationSpeed: config.speed * 2.3,
                direction: .clockwise)
                .blur(radius: size * 0.06)
                .opacity(config.coreGlowIntensity)
                .blendMode(.plusLighter)
        }
        .padding(size * 0.08)
    }

    private func baseDepthGlows(size: CGFloat) -> some View {
        ZStack {
            RotatingGlowView(
                color: config.glowColor,
                rotationSpeed: config.speed * 0.75,
                direction: .counterClockwise)
                .padding(size * 0.03)
                .blur(radius: size * 0.06)
                .rotationEffect(.degrees(180))
                .blendMode(.destinationOver)
            RotatingGlowView(
                color: config.glowColor.opacity(0.5),
                rotationSpeed: config.speed * 0.25,
                direction: .clockwise)
                .frame(maxWidth: size * 0.94)
                .rotationEffect(.degrees(180))
                .padding(Space.x2)
                .blur(radius: size * 0.032)
        }
    }

    private var realisticInnerGlows: some View {
        let outline = LinearGradient(
            colors: [.white, .clear],
            startPoint: .bottom,
            endPoint: .top)
        return ZStack {
            Circle()
                .stroke(outline, lineWidth: 8)
                .blur(radius: 32)
                .blendMode(.plusLighter)
            Circle()
                .stroke(outline, lineWidth: 4)
                .blur(radius: 12)
                .blendMode(.plusLighter)
            Circle()
                .stroke(outline, lineWidth: 1)
                .blur(radius: 4)
                .blendMode(.plusLighter)
        }
        .padding(Space.x1 / 4)
    }
}
