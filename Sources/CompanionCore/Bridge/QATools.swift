import Foundation

/// Puente QA (PR-2): the two tools that let an outside agent drive a turn of
/// the conversation. They are in the bridge allowlist but only served while
/// the QA scope is on (`QARunner` reads it per call), so a closed scope answers
/// `unknown_tool` and a hello taken with it off never lists them.
package enum QATool: String, CaseIterable, Sendable {
    case ask = "companion_ask"
    case waitTurn = "companion_wait_turn"

    package static let maxTextBytes = ToolProperty.maxTextBytes
    package static let maxWaitSeconds = 100
    package static let defaultWaitSeconds = 60

    /// The name is wire contract and never translates; the description is read
    /// by the agent and follows the language of the answer.
    package func spec(_ language: AppLanguage) -> ToolSpec {
        ToolSpec(
            name: rawValue,
            description: Self.description(self, language) + " " + BridgeCopy.toolDataSuffix(language),
            properties: properties(language),
            required: self == .ask ? ["text"] : ["turn_id"])
    }

    private func properties(_ language: AppLanguage) -> [ToolProperty] {
        let es = language == .es
        let wait = ToolProperty(
            name: "wait_seconds", type: "integer",
            description: es
                ? "cuántos segundos esperar, 0 a \(Self.maxWaitSeconds) (\(Self.defaultWaitSeconds) por defecto)"
                : "how many seconds to wait, 0 to \(Self.maxWaitSeconds) (default \(Self.defaultWaitSeconds))")
        switch self {
        case .ask:
            return [
                ToolProperty(
                    name: "text", type: "string",
                    description: es ? "lo que se escribe en la conversación" : "what is typed into the conversation",
                    minLength: 1, maxBytes: Self.maxTextBytes),
                ToolProperty(
                    name: "conversation", type: "string",
                    description: es
                        ? "current sigue la conversación abierta; new empieza una en limpio (por defecto current)"
                        : "current continues the open conversation; new starts a clean one (default current)",
                    allowed: ["current", "new"]),
                ToolProperty(
                    name: "as_user_words", type: "boolean",
                    description: es
                        ? "true (por defecto): el texto cuenta como palabras de la usuaria; false: sin palabras, como si nadie hubiera dicho nada"
                        : "true (default): the text counts as the user's own words; false: no words, as if nobody had said anything"),
                wait,
            ]
        case .waitTurn:
            return [
                ToolProperty(
                    name: "turn_id", type: "string",
                    description: es ? "el turn_id que devolvió companion_ask" : "the turn_id companion_ask returned",
                    minLength: 1, maxBytes: 64),
                wait,
            ]
        }
    }

    private static func description(_ tool: QATool, _ language: AppLanguage) -> String {
        switch (tool, language) {
        case (.ask, .en):
            return "QA mode only. Types a message into Companion's conversation as a turn, waits for it to end and "
                + "returns what happened: phases, tool calls, the reply. Nothing opens an approval sheet; a critical "
                + "action asks the user for Touch ID. status awaiting_owner means a Touch ID dialog is on screen: "
                + "tell the user to touch the sensor, then call companion_wait_turn."
        case (.ask, .es):
            return "Solo con el modo QA. Escribe un mensaje en la conversación de Companion como un turno, espera a "
                + "que termine y devuelve lo ocurrido: fases, tools llamadas, la respuesta. Nada abre una hoja de "
                + "aprobación; una acción crítica pide Touch ID a la usuaria. status awaiting_owner significa que "
                + "hay un diálogo de Touch ID en pantalla: dile que ponga el dedo y llama a companion_wait_turn."
        case (.waitTurn, .en):
            return "QA mode only. Waits for a turn started by companion_ask and returns the same result. Read-only; "
                + "a finished turn answers at once."
        case (.waitTurn, .es):
            return "Solo con el modo QA. Espera un turno iniciado por companion_ask y devuelve el mismo resultado. "
                + "Solo lectura; un turno terminado responde al instante."
        }
    }
}

/// How `ask` began. A turn already running is not queued: the queue of the
/// chat belongs to the user.
package enum QAAskStart: Sendable, Equatable {
    case started(turnId: String, conversationId: String)
    case busy(turnId: String)
    /// The chat cannot take a turn (still onboarding).
    case unavailable
}

/// The port the QA tools drive. Main-actor in UI (`SelfInspectionSource`); the
/// bridge only awaits it.
package protocol QADriving: Sendable {
    func ask(text: String, newConversation: Bool, asUserWords: Bool) async -> QAAskStart
    /// The live record of the running turn or the finished one in the ring;
    /// nil for an id this process never ran.
    func turn(_ id: String) async -> TurnRecord?
}

extension ContractError {
    /// The answer to a critical action QA mode did not allow. Code first, as
    /// every contract error: the agent recovers by it.
    package static func ownerCheck(code: String) -> ContractError {
        let message: String
        switch code {
        case BridgeCode.ownerRefused:
            message = "the user declined the Touch ID or password prompt: do not try again without asking them"
        case BridgeCode.ownerBusy:
            message = "another Touch ID prompt is already on screen: ask the user to answer it, then retry"
        default:
            message = "Touch ID and the password are unavailable, so QA mode turned itself off"
        }
        return ContractError(code: code, message: message)
    }
}
