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
}
