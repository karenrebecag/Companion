import Foundation

/// Every string the specialist path puts in front of a person or a model,
/// in both languages. Split from Escalation so the logic there stays
/// readable: this file is a table, not behaviour.
///
/// English is the source. The Spanish is the copy this app was written in
/// and is kept verbatim — a retranslation would flatten a voice that took
/// real work to find.
extension Escalation {
    /// Injected once per specialist session, never per job — repeating it
    /// burns tokens and drowns the transcript.
    public static func executorRole(_ language: AppLanguage = .en) -> String {
        switch language {
        case .en:
            return "Companion (a voice assistant) delegates jobs to you. You "
                + "have the tools; she only talks to the user. Do the work "
                + "(files, commands, a plan) and answer for a screen, "
                + "starting with a one-line summary — the voice narrates only "
                + "that opening. The client RENDERS MARKDOWN: use # headings, "
                + "- or 1. lists, pipe tables when you compare data, and "
                + "fences with a language for code or commands. Repeated data "
                + "with the same columns goes in a table, not in prose with "
                + "dashes. The client also paints NATIVE CARDS from companion: "
                + "fences: for physical places with coordinates emit "
                + "```companion:locations with JSON "
                + "{\"title\",\"locations\":[{\"id\",\"name\",\"eyebrow\","
                + "\"address\",\"lat\",\"lng\",\"url\"}]} (lat/lng must be "
                + "numbers); to compare images emit ```companion:gallery with "
                + "{\"title\",\"images\":[{\"path\" local or \"url\" https,"
                + "\"caption\"}]}. If neither applies, plain markdown. If you "
                + "used the web, close with a Sources: section as a list, each "
                + "source as [title](url) — one line on what it adds."
        case .es:
            return "Companion (asistente de voz) te delega "
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
        }
    }

    /// A paragraph read aloud is unbearable; this goes on the first voice
    /// turn only so later turns are not padded with the same instruction.
    public static func voicePreamble(_ language: AppLanguage = .en) -> String {
        switch language {
        case .en: return "Answer in at most 2 sentences, in English, no markdown. "
        case .es: return "Responde en maximo 2 frases, en espanol, sin markdown. "
        }
    }

    // MARK: - Job labels

    static func jobLabels(_ language: AppLanguage) -> JobLabels {
        switch language {
        case .en:
            return JobLabels(
                job: "Job", context: "Context", workdir: "Working folder",
                desktop: "Desktop",
                attachments: "Attachments from this turn (local paths, open "
                    + "them yourself):")
        case .es:
            return JobLabels(
                job: "Encargo", context: "Contexto",
                workdir: "Carpeta de trabajo", desktop: "Escritorio",
                attachments: "Adjuntos del turno (rutas locales, ábrelos tú):")
        }
    }

    struct JobLabels {
        let job: String
        let context: String
        let workdir: String
        let desktop: String
        let attachments: String
    }

    // MARK: - Cierre del encargo hacia la voz

    /// The first useful line of a result, which is what the specialist is
    /// told to open with. Read aloud, so no markdown and no essay.
    public static func resultSummary(_ text: String, limit: Int = 200) -> String {
        let line = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let clean = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        // The ellipsis counts: `limit` is the length of what gets spoken.
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit - 1)) + "…"
    }

    /// System items for the voice model. It cannot read the thread, so the
    /// result travels here: told to narrate something it cannot see, the
    /// model invents a happy ending — it did, on screen, over a file that
    /// was never created.
    public static func jobDoneAnnouncement(
        _ goal: String, summary: String = "", _ language: AppLanguage = .en
    ) -> String {
        let said = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        switch language {
        case .en:
            guard !said.isEmpty else {
                return "Job finished: «\(goal)». The result is on screen; say "
                    + "only that it is done. Do not add details you were not "
                    + "given."
            }
            return "Job finished: «\(goal)». The specialist reports: «\(said)». "
                + "Tell the user exactly that, in one sentence. Do not add "
                + "anything you were not told, and do not claim success if "
                + "the report says otherwise."
        case .es:
            guard !said.isEmpty else {
                return "Encargo terminado: «\(goal)». El resultado está en "
                    + "pantalla; di solo que terminó. No añadas detalles que "
                    + "no te dieron."
            }
            return "Encargo terminado: «\(goal)». El especialista reporta: "
                + "«\(said)». Dile exactamente eso al usuario, en una frase. "
                + "No añadas nada que no te hayan dicho, ni digas que salió "
                + "bien si el reporte dice lo contrario."
        }
    }

    public static func jobFailedAnnouncement(
        _ goal: String, reason: String = "", _ language: AppLanguage = .en
    ) -> String {
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        switch language {
        case .en:
            let base = why.isEmpty
                ? "The job «\(goal)» failed or ran out of time."
                : "The job «\(goal)» failed: «\(why)»."
            return base + " Tell the user that and offer to try again. Never "
                + "say it worked."
        case .es:
            let base = why.isEmpty
                ? "El encargo «\(goal)» falló o se quedó sin tiempo."
                : "El encargo «\(goal)» falló: «\(why)»."
            return base + " Díselo al usuario y ofrece reintentarlo. Nunca "
                + "digas que salió bien."
        }
    }

    /// For the screen: the failure in human words, never the internal error.
    public static func jobFailedStatus(
        _ goal: String, detail: String, _ language: AppLanguage = .en
    ) -> String {
        let base: String
        switch language {
        case .en: base = "The job «\(goal)» could not be completed."
        case .es: base = "El encargo «\(goal)» no se pudo completar."
        }
        let extra = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return extra.isEmpty ? base : base + " " + extra
    }

    /// The stdio cable died with work already done: it is picked up in batch.
    /// Silence here would be a long unexplained pause on screen.
    public static func fallbackNotice(_ language: AppLanguage = .en) -> String {
        switch language {
        case .en:
            return "The channel to the specialist dropped; picking the job up "
                + "the slow way."
        case .es:
            return "Se cortó el canal con el especialista; retomo el encargo "
                + "por la vía lenta."
        }
    }

    // MARK: - Permisos hacia la voz

    /// Read out loud: it says WHAT is being asked, never the raw command (a
    /// path with `rm -rf` dictated through a speaker does not inform, it
    /// frightens). With no summary from the specialist the tool name stands
    /// in, never an empty sentence.
    public static func approvalAnnouncement(
        _ request: ApprovalRequest, _ language: AppLanguage = .en
    ) -> String {
        let what = request.summary.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let subject = what.isEmpty ? request.toolName : what
        switch language {
        case .en:
            return "The specialist is asking permission to \(subject). Ask the "
                + "user whether they allow it and, once they answer, use "
                + "resolve_approval with their reply."
        case .es:
            return "El especialista pide permiso para \(subject). Pregúntale "
                + "al usuario si lo autoriza y, cuando conteste, usa "
                + "resolve_approval con su respuesta."
        }
    }

    /// Tool-call ack: without it the voice sits mute waiting on the server.
    public static func approvalAck(
        approved: Bool, _ language: AppLanguage = .en
    ) -> String {
        switch (language, approved) {
        case (.en, true):
            return "Permission granted; the specialist carries on. Say it in "
                + "one sentence."
        case (.en, false):
            return "Permission denied; the specialist will find another route. "
                + "Say it in one sentence."
        case (.es, true):
            return "Permiso concedido; el especialista continúa. Dilo en una "
                + "frase."
        case (.es, false):
            return "Permiso denegado; el especialista buscará otra ruta. Dilo "
                + "en una frase."
        }
    }

    /// The model can call the tool with nothing pending (or after the user
    /// answered on screen). Never invent an authorisation.
    public static func approvalNothingPending(
        _ language: AppLanguage = .en
    ) -> String {
        switch language {
        case .en:
            return "There is no pending permission request. Do not say you "
                + "authorised anything."
        case .es:
            return "No hay ninguna solicitud de permiso pendiente. No digas "
                + "que autorizaste nada."
        }
    }
}
