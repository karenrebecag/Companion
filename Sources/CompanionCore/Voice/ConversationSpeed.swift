import Foundation

/// Each voice backend accepts a different speed window; the factor the user
/// asked for is clamped per backend, never globally.
package enum SpeechSpeedProvider: Sendable, Equatable, CaseIterable {
    case realtime
    case openAITTS
    case elevenLabs

    package var range: ClosedRange<Double> {
        switch self {
        case .realtime: 0.25 ... 1.5
        case .openAITTS: 0.25 ... 4.0
        case .elevenLabs: 0.7 ... 1.2
        }
    }
}

/// Per-conversation pace, relative to each mouth's own base (1.0 = normal).
/// Relative on purpose: the realtime base and the TTS bases differ, and a
/// single absolute number would mean a different pace on each.
package struct ConversationSpeed: Sendable, Equatable {
    package static let factorRange: ClosedRange<Double> = 0.25 ... 4.0
    /// Few distinct values keeps the phrase cache from fragmenting.
    package static let step = 0.05
    package static let base = ConversationSpeed(factor: 1.0)

    package let factor: Double

    package init(factor: Double) {
        // A non-finite value would poison every request body; fall back to
        // the base rather than trap or send NaN.
        guard factor.isFinite else { self.factor = 1.0; return }
        let clamped = min(max(factor, Self.factorRange.lowerBound), Self.factorRange.upperBound)
        // Multiply by 1/step instead of dividing so 1.3 stays exactly 1.3.
        self.factor = (clamped * (1 / Self.step)).rounded() / (1 / Self.step)
    }

    package func speed(for provider: SpeechSpeedProvider, base: Double) -> Double {
        let range = provider.range
        return min(max(base * factor, range.lowerBound), range.upperBound)
    }

    package func isLimited(for provider: SpeechSpeedProvider, base: Double) -> Bool {
        !provider.range.contains(base * factor)
    }

    /// Only a real JSON number counts: `as? Double` would accept a JSON
    /// boolean through NSNumber bridging, and a string is a malformed call.
    package static func factor(fromArguments arguments: [String: Any]) -> ConversationSpeed? {
        guard let number = arguments["factor"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value > 0 else { return nil }
        return ConversationSpeed(factor: value)
    }
}

/// What the model and the user hear about a speed change. Core copy, like
/// `BridgeCopy`: the Services layer that applies it cannot reach the UI catalog.
package enum SpeechSpeedCopy {
    /// 1.3 not 1.30, 1 not 1.0: the model reads this back in prose.
    package static func label(_ value: Double) -> String {
        String(format: "%g", value)
    }

    package static func toolOutput(
        applied: Double, limited: Bool, language: AppLanguage = .en
    ) -> String {
        let value = label(applied)
        switch language {
        case .en:
            let head = limited
                ? "Speed limited to \(value)x, the most this voice allows."
                : "Speed set to \(value)x."
            return head + " Say one short phrase at this pace and nothing more."
        case .es:
            let head = limited
                ? "Velocidad limitada a \(value)x, lo máximo que permite esta voz."
                : "Velocidad ajustada a \(value)x."
            return head + " Di una frase corta a este ritmo y nada más."
        }
    }

    /// The speed update only changes playback of audio the model already
    /// wrote, so its wording has to carry the pace too. Nil at base: nothing
    /// to add to the instructions.
    package static func pacingNote(
        _ speed: ConversationSpeed, language: AppLanguage = .en
    ) -> String? {
        guard speed != .base else { return nil }
        let value = label(speed.factor)
        switch language {
        case .en:
            return speed.factor > 1
                ? "The user asked you to speak faster (\(value)x normal): keep sentences short and brisk."
                : "The user asked you to speak slower (\(value)x normal): keep sentences short and unhurried."
        case .es:
            return speed.factor > 1
                ? "La usuaria pidió que hables más rápido (\(value)x lo normal): frases cortas y ágiles."
                : "La usuaria pidió que hables más lento (\(value)x lo normal): frases cortas y sin prisa."
        }
    }

    package static func confirmation(_ language: AppLanguage = .en) -> String {
        switch language {
        case .en: "Done. Like this?"
        case .es: "Listo, ¿así?"
        }
    }
}
