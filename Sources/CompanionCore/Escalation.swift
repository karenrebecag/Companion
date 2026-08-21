import Foundation

/// Compact handoff from the conversational layer to a specialist.
/// A malformed or truncated `delegate` call must not escalate — the speaker
/// keeps talking whatever text it already has.
public struct Handoff: Sendable, Equatable {
    public var goal: String
    public var context: String

    public init(goal: String, context: String) {
        self.goal = goal
        self.context = context
    }

    public static func parse(toolName: String, arguments: String) -> Handoff? {
        guard toolName == "delegate" else { return nil }
        guard let data = arguments.data(using: .utf8) else { return nil }
        let obj: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else { return nil }
            obj = parsed
        } catch {
            return nil
        }
        guard let goal = (obj["goal"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !goal.isEmpty
        else { return nil }
        let context = (obj["context"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Handoff(goal: goal, context: context)
    }
}

public enum Escalation: Sendable {
    /// Injected once per specialist session, never per job — repeating it
    /// burns tokens and drowns the transcript.
    public static let executorRole = "Companion (asistente de voz) te delega "
        + "encargos. Tú tienes las herramientas; ella solo habla con el "
        + "usuario. Haz el trabajo (archivos, comandos, plan) y responde "
        + "para pantalla, empezando con un resumen de una línea — la voz "
        + "narra solo ese arranque. El cliente RENDERIZA MARKDOWN: usa "
        + "encabezados con #, listas con - o 1., tablas con pipes cuando "
        + "compares datos, y fences con lenguaje para código o comandos. "
        + "Datos repetidos con las mismas columnas van en tabla, no en "
        + "prosa con guiones. Además el cliente pinta TARJETAS NATIVAS desde "
        + "fences companion: para lugares físicos con coordenadas emite "
        + "```companion:locations con JSON "
        + "{\"title\",\"locations\":[{\"id\",\"name\",\"eyebrow\",\"address\","
        + "\"lat\",\"lng\",\"url\"}]} (lat/lng numéricos obligatorios); para "
        + "comparar imágenes emite ```companion:gallery con "
        + "{\"title\",\"images\":[{\"path\" local o \"url\" https,"
        + "\"caption\"}]}. Si no aplica, markdown normal. Si usaste la web, "
        + "cierra con una sección Sources: en lista, cada fuente como "
        + "[título](url) — una línea de qué aporta."

    /// A paragraph read aloud is unbearable; this goes on the first voice
    /// turn only so later turns are not padded with the same instruction.
    public static let voicePreamble =
        "Responde en maximo 2 frases, en espanol, sin markdown. "

    public static func jobPrompt(
        _ h: Handoff, workdir: String, desktop: String,
        attachments: [String] = []
    ) -> String {
        var out = "Encargo: \(h.goal)\n"
        if !h.context.isEmpty { out += "Contexto: \(h.context)\n" }
        out += "Carpeta de trabajo: \(workdir)\n"
        out += "Escritorio: \(desktop)"
        if !attachments.isEmpty {
            out += "\nAdjuntos del turno (rutas locales, ábrelos tú):"
            for path in attachments { out += "\n- \(path)" }
        }
        return out
    }

    public static func executorPrompt(
        _ h: Handoff, original: String, workdir: String, desktop: String
    ) -> String {
        var out = "Companion te pasa trabajo. Tú tienes las herramientas; "
        out += "ella solo habló con el usuario.\n"
        out += "Objetivo: \(h.goal)\n"
        if !h.context.isEmpty { out += "Contexto: \(h.context)\n" }
        out += "Carpeta de trabajo: \(workdir)\n"
        out += "Escritorio: \(desktop)\n"
        out += "Petición original: «\(original)»\n"
        out += "Haz el trabajo (archivos, comandos, plan). Respuesta completa "
        out += "para pantalla. Empieza con un resumen de una línea; la voz "
        out += "lee solo ese arranque."
        return out
    }

    public static func voiceTurnPrompt(_ text: String, firstTurn: Bool) -> String {
        firstTurn ? voicePreamble + text : text
    }
}
