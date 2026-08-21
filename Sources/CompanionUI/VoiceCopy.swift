import CompanionCore

public enum VoiceCopy {
    public static let fallbackClassic =
        "La voz en vivo no está disponible. Sigo por el micrófono clásico."

    public static let functionRefusal =
        "Los encargos estarán disponibles en una próxima versión."

    public static func failure(_ reason: TurnFailure) -> String {
        switch reason {
        case .micDenied:
            return "Sin permiso de micrófono. Revisa Ajustes del sistema."
        case .micUnavailable:
            return "El micrófono no está disponible."
        case .micSilent:
            return "El micrófono no entregó audio."
        case .notHeard:
            return "No te escuché."
        case .speechEngine:
            return "Me quedé sin voz. Revisa el TTS."
        case .noProviders:
            return "No hay un proveedor de voz disponible."
        case .sessionDropped:
            return "La sesión de voz se cayó."
        case .networkUnavailable:
            return "No hay conexión a internet. Verifica tu red."
        }
    }
}
