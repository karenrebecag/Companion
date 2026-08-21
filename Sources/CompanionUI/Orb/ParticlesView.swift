import AppKit
import SpriteKit
import SwiftUI

/// SpriteKit emitter, same as metasidd/Orb. SKScene stays off the view actor.
final class ParticleScene: SKScene, @unchecked Sendable {
    let color: NSColor
    let speedRange: ClosedRange<Double>
    let sizeRange: ClosedRange<CGFloat>
    let particleCount: Int
    let opacityRange: ClosedRange<Double>

    init(
        size: CGSize,
        color: NSColor,
        speedRange: ClosedRange<Double>,
        sizeRange: ClosedRange<CGFloat>,
        particleCount: Int,
        opacityRange: ClosedRange<Double>
    ) {
        self.color = color
        self.speedRange = speedRange
        self.sizeRange = sizeRange
        self.particleCount = particleCount
        self.opacityRange = opacityRange
        super.init(size: size)
        backgroundColor = .clear
        setupParticleEmitter()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupParticleEmitter() {
        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.particleTexture
        emitter.particleColorSequence = nil
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleSpeed = CGFloat(speedRange.lowerBound)
        emitter.particleSpeedRange = CGFloat(
            speedRange.upperBound - speedRange.lowerBound)
        emitter.particleScale = sizeRange.lowerBound
        emitter.particleScaleRange = sizeRange.upperBound - sizeRange.lowerBound
        emitter.particleAlpha = 0
        emitter.particleAlphaSpeed = CGFloat(opacityRange.upperBound) / 0.5
        emitter.particleAlphaRange = CGFloat(
            opacityRange.upperBound - opacityRange.lowerBound)
        emitter.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [
                0,
                Double.random(in: opacityRange),
                Double.random(in: opacityRange),
                Double.random(in: opacityRange),
            ],
            times: [0, 0.2, 0.8, 1.0])
        emitter.particleScaleSequence = SKKeyframeSequence(
            keyframeValues: [
                sizeRange.lowerBound * 0.7,
                sizeRange.upperBound * 0.9,
                sizeRange.upperBound,
                sizeRange.lowerBound * 0.8,
            ],
            times: [0, 0.4, 0.7, 1.0])
        emitter.particleBlendMode = .add
        emitter.position = CGPoint(x: size.width / 2, y: size.height / 2)
        emitter.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        emitter.particleBirthRate = CGFloat(particleCount) / 2
        emitter.numParticlesToEmit = 0
        emitter.particleLifetime = 2
        emitter.particleLifetimeRange = 1
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 6
        emitter.xAcceleration = 0
        emitter.yAcceleration = 20
        addChild(emitter)
    }

    private static let particleTexture: SKTexture = {
        let size = CGSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return SKTexture(image: image)
    }()
}

struct ParticlesView: View {
    let color: Color
    let speedRange: ClosedRange<Double>
    let sizeRange: ClosedRange<CGFloat>
    let particleCount: Int
    let opacityRange: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            SpriteView(
                scene: scene(in: geometry.size),
                options: [.allowsTransparency])
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func scene(in size: CGSize) -> SKScene {
        let scene = ParticleScene(
            size: CGSize(width: 300, height: 300),
            color: NSColor(color),
            speedRange: speedRange,
            sizeRange: sizeRange,
            particleCount: particleCount,
            opacityRange: opacityRange)
        scene.scaleMode = .aspectFit
        return scene
    }
}
