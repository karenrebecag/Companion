import Foundation

extension ToolSpec {
    /// Wire name is fixed in both languages; the description tells the model
    /// the current factor because the argument is absolute, not a delta.
    package static func setSpeechSpeed(
        _ language: AppLanguage = .en, current: ConversationSpeed
    ) -> ToolSpec {
        let now = SpeechSpeedCopy.label(current.factor)
        switch language {
        case .en:
            return ToolSpec(
                name: "set_speech_speed",
                description: "Change how fast you speak for the rest of this "
                    + "conversation. Call it ONLY when the user asks you to "
                    + "speak faster, slower or back to normal. The factor is "
                    + "absolute against normal speed (1 = normal, 1.3 = 30% "
                    + "faster, 0.8 = slower); the current factor is \(now). "
                    + "Say nothing before calling it.",
                properties: [
                    ToolProperty(name: "factor", type: "number",
                                 description: "speed relative to normal, 1 = normal"),
                ],
                required: ["factor"])
        case .es:
            return ToolSpec(
                name: "set_speech_speed",
                description: "Cambia qué tan rápido hablas durante el resto de "
                    + "esta conversación. Llámala SOLO cuando la usuaria pida "
                    + "que hables más rápido, más lento o normal. El factor es "
                    + "absoluto respecto de la velocidad normal (1 = normal, "
                    + "1.3 = 30% más rápido, 0.8 = más lento); el factor actual "
                    + "es \(now). No digas nada antes de llamarla.",
                properties: [
                    ToolProperty(name: "factor", type: "number",
                                 description: "velocidad relativa a la normal, 1 = normal"),
                ],
                required: ["factor"])
        }
    }
}
