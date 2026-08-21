import CompanionCore
import Foundation

public enum ChatCopy {
    public static let emptyKey = "Pega tu clave de OpenAI para empezar."

    public static func error(_ error: Error) -> String {
        if let chat = error as? ChatError {
            return chatCopy(chat)
        }
        if let secret = error as? SecretStoreError {
            return secretCopy(secret)
        }
        if error is PersistenceError {
            return "No pude guardar la conversación. Revisa el espacio en disco."
        }
        return "Algo salió mal. Inténtalo de nuevo."
    }

    public static func handoff(_ h: Handoff) -> String {
        "Encargo: \(h.goal) — el especialista llega en una próxima versión."
    }

    private static func chatCopy(_ error: ChatError) -> String {
        switch error {
        case .unauthorized, .invalidKey:
            return "Esta clave no es válida. Revísala en platform.openai.com."
        case .forbidden:
            return "Esta clave no tiene permiso. Revisa su acceso en platform.openai.com."
        case .rateLimited:
            return "Demasiadas peticiones. Espera un momento e inténtalo de nuevo."
        case .timeout, .unreachable:
            return "No pude conectar. Revisa la red e inténtalo de nuevo."
        case .httpStatus(let code):
            return "El servidor respondió \(code). Inténtalo de nuevo."
        case .noProvider:
            return "No hay un proveedor de chat disponible."
        case .empty:
            return "El modelo no contestó. Inténtalo de nuevo."
        }
    }

    private static func secretCopy(_ error: SecretStoreError) -> String {
        switch error {
        case .denied:
            return "No pude guardar la clave en el llavero. Autoriza el acceso e inténtalo de nuevo."
        case .emptyValue:
            return emptyKey
        case .notAvailable, .unexpected:
            return "No pude guardar la clave. Inténtalo de nuevo."
        }
    }

    public static func step(_ tool: String, _ summary: String) -> String {
        summary.isEmpty ? tool : "\(tool): \(summary)"
    }

    public static func stepDone(_ tool: String, ok: Bool) -> String {
        ok ? "\(tool) — listo" : "\(tool) — falló"
    }

    public static let approvalPending =
        "El especialista pide permiso para continuar."

    public static func approvalAnswer(_ approved: Bool) -> String {
        approved ? "Permiso concedido." : "Permiso denegado."
    }

    public static let jobDone = "Encargo listo"
    public static let jobFailed = "Encargo falló"

    public static func attached(_ name: String) -> String {
        "Adjuntado: \(name)"
    }

    public static func attachFailed(_ error: AttachmentError) -> String {
        switch error {
        case .tooLarge:
            return "El archivo es demasiado grande (máximo 20 MB)."
        case .unreadable:
            return "No pude leer ese archivo."
        case .io:
            return "No pude guardar el adjunto."
        }
    }

    /// Readable summary of a tool request: raw JSON is not a decision aid.
    public static func approvalDetail(
        tool: String, inputJSON: String
    ) -> String {
        guard let data = inputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return tool }
        let interesting = ["command", "path", "url", "query", "content"]
        for key in interesting {
            if let value = object[key] as? String, !value.isEmpty {
                return value.count > 200 ? String(value.prefix(200)) + "…" : value
            }
        }
        return tool
    }
}
