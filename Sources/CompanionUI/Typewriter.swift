import Foundation
import SwiftUI

public struct TypewriterConfig: Equatable, Sendable {
    public var typeSpeed: TimeInterval
    public var deleteSpeed: TimeInterval
    public var pauseTyped: TimeInterval
    public var pauseDeleted: TimeInterval
    public var loop: Bool
    public var human: Bool
    public var cursor: Bool

    public init(
        typeSpeed: TimeInterval = 0.07,
        deleteSpeed: TimeInterval = 0.04,
        pauseTyped: TimeInterval = 1.8,
        pauseDeleted: TimeInterval = 0.5,
        loop: Bool = true,
        human: Bool = true,
        cursor: Bool = true
    ) {
        self.typeSpeed = typeSpeed
        self.deleteSpeed = deleteSpeed
        self.pauseTyped = pauseTyped
        self.pauseDeleted = pauseDeleted
        self.loop = loop
        self.human = human
        self.cursor = cursor
    }

    public static let idle = TypewriterConfig()
}

public enum TypewriterMotion {
    private static let jitterMin = 0.5
    private static let jitterMax = 1.5

    public static func typeStepDuration(
        base: TimeInterval, human: Bool, unit: UInt64
    ) -> TimeInterval {
        guard human else { return base }
        let t = Double(unit % 1000) / 1000
        return base * (jitterMin + t * (jitterMax - jitterMin))
    }

    public static func visible(
        elapsed: TimeInterval,
        phrases: [String],
        config: TypewriterConfig,
        reduceMotion: Bool = false
    ) -> String {
        guard let last = phrases.last else { return "" }
        if reduceMotion { return last }
        if config.loop {
            let total = phrases.enumerated().reduce(0.0) { sum, item in
                sum + cycleDuration(item.element, index: item.offset, config: config)
            }
            guard total > 0 else { return last }
            var t = elapsed.truncatingRemainder(dividingBy: total)
            if t < 0 { t += total }
            for (i, phrase) in phrases.enumerated() {
                let d = cycleDuration(phrase, index: i, config: config)
                if t < d {
                    return visibleInCycle(t, phrase: phrase, index: i, config: config)
                }
                t -= d
            }
            return ""
        }
        var t = max(0, elapsed)
        for (i, phrase) in phrases.enumerated() {
            let typeD = typeDuration(phrase, index: i, config: config)
            if i == phrases.count - 1 {
                if t < typeD {
                    return prefix(phrase, typedCount(t, phrase: phrase, index: i, config: config))
                }
                return phrase
            }
            let d = cycleDuration(phrase, index: i, config: config)
            if t < d {
                return visibleInCycle(t, phrase: phrase, index: i, config: config)
            }
            t -= d
        }
        return last
    }

    public static func cursorLit(elapsed: TimeInterval) -> Bool {
        Int(floor(elapsed)) % 2 == 0
    }

    private static func visibleInCycle(
        _ t: TimeInterval,
        phrase: String,
        index: Int,
        config: TypewriterConfig
    ) -> String {
        let typeD = typeDuration(phrase, index: index, config: config)
        if t < typeD {
            return prefix(
                phrase,
                typedCount(t, phrase: phrase, index: index, config: config))
        }
        var rest = t - typeD
        if rest < config.pauseTyped { return phrase }
        rest -= config.pauseTyped
        let n = phrase.count
        let deleteD = Double(n) * config.deleteSpeed
        if rest < deleteD {
            let gone = config.deleteSpeed > 0
                ? min(n, Int(floor(rest / config.deleteSpeed + 1e-9)))
                : n
            return prefix(phrase, n - gone)
        }
        return ""
    }

    private static func typedCount(
        _ t: TimeInterval,
        phrase: String,
        index: Int,
        config: TypewriterConfig
    ) -> Int {
        var acc: TimeInterval = 0
        var count = 0
        for i in 0..<phrase.count {
            acc += typeStepDuration(
                base: config.typeSpeed,
                human: config.human,
                unit: UInt64(index * 4096 + i))
            if acc > t + 1e-9 { break }
            count += 1
        }
        return count
    }

    private static func typeDuration(
        _ phrase: String, index: Int, config: TypewriterConfig
    ) -> TimeInterval {
        (0..<phrase.count).reduce(0) { sum, i in
            sum + typeStepDuration(
                base: config.typeSpeed,
                human: config.human,
                unit: UInt64(index * 4096 + i))
        }
    }

    private static func cycleDuration(
        _ phrase: String, index: Int, config: TypewriterConfig
    ) -> TimeInterval {
        typeDuration(phrase, index: index, config: config)
            + config.pauseTyped
            + Double(phrase.count) * config.deleteSpeed
            + config.pauseDeleted
    }

    private static func prefix(_ phrase: String, _ n: Int) -> String {
        String(phrase.prefix(max(0, n)))
    }
}

public struct TypewriterView: View {
    let phrases: [String]
    var config: TypewriterConfig = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    public init(phrases: [String], config: TypewriterConfig = .idle) {
        self.phrases = phrases
        self.config = config
    }

    public var body: some View {
        Group {
            if reduceMotion || phrases.isEmpty {
                Text(phrases.last ?? "")
                    .multilineTextAlignment(.center)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(started)
                    let text = TypewriterMotion.visible(
                        elapsed: elapsed,
                        phrases: phrases,
                        config: config)
                    HStack(alignment: .firstTextBaseline, spacing: Space.none) {
                        Text(text)
                        if config.cursor {
                            cursor(lit: TypewriterMotion.cursorLit(elapsed: elapsed))
                        }
                    }
                }
            }
        }
        .frame(minHeight: TypeSize.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phrases.joined(separator: ", "))
    }

    private func cursor(lit: Bool) -> some View {
        Rectangle()
            .fill(Semantic.accent)
            .frame(width: Stroke.medium, height: TypeSize.lg)
            .opacity(lit ? 1 : 0)
            .offset(y: 2)
            .accessibilityHidden(true)
    }
}
