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
                + "(files, commands, a plan). The user is SPEAKING, not "
                + "reading a chat: never end with only a clarifying question. "
                + "When details are missing, pick sensible defaults, complete "
                + "the task, and note the choice in one line — an empty file "
                + "that exists beats a perfect file that was never created. "
                + "Answer for a screen, "
                + "starting with a one-line summary — it is the first "
                + "thing the user reads. The client RENDERS MARKDOWN: use # headings, "
                + "- or 1. lists, pipe tables when you compare data, and "
                + "fences with a language for code or commands. Repeated data "
                + "with the same columns goes in a table, not in prose with "
                + "dashes. \(CardVocabulary.text(.en)) If you "
                + "used the web, close with a Sources: section as a list, each "
                + "source as [title](url) — one line on what it adds."
        case .es:
            return "Companion (asistente de voz) te delega "
                + "encargos. Tú tienes las herramientas; ella solo habla con el "
                + "usuario. Haz el trabajo (archivos, comandos, plan). El "
                + "usuario está HABLANDO, no leyendo un chat: nunca termines "
                + "solo con una pregunta aclaratoria. Si faltan detalles, elige "
                + "un default razonable, completa la tarea y anota la decisión "
                + "en una línea — un archivo vacío que existe vale más que uno "
                + "perfecto que nunca se creó. Responde "
                + "para pantalla, empezando con un resumen de una línea — es lo "
                + "primero que lee el usuario. El cliente RENDERIZA MARKDOWN: usa "
                + "encabezados con #, listas con - o 1., tablas con pipes cuando "
                + "compares datos, y fences con lenguaje para código o comandos. "
                + "Datos repetidos con las mismas columnas van en tabla, no en "
                + "prosa con guiones. \(CardVocabulary.text(.es)) Si usaste la web, "
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

    /// System item for the voice model when a job lands well. It acknowledges;
    /// it does not read the result back. The specialist's text is already the
    /// thread message — with its code, its paths and its cards — and a spoken
    /// paraphrase of it was a second message for one result, lossy on exactly
    /// the content that cannot be spoken.
    ///
    /// The guarantee that Wave 8 bought survives: which of the two endings
    /// happened still comes from the specialist, never from the model, and it
    /// is told not to add what it was not given.
    /// Said when a request arrives while a job is already running.
    ///
    /// It QUEUES. Neither reference cancels running work to make room: they
    /// offer three separate gestures — interrupt (stop, keep what is done),
    /// steer (inject into the live turn, keep progress), and queue (store it,
    /// run it after). Asking for a second thing is none of the first two.
    ///
    /// The first version of this said "tell me to stop if you want me to drop
    /// it and do this instead". It was written for the user and the MODEL read
    /// it as an instruction: asked for cinemas while searching parks, it
    /// called `stop_job` and killed both. Copy that reaches a model is not
    /// copy, it is a prompt — so this one states a fact and forbids the move.
    public static func queuedNotice(
        _ goal: String, _ language: AppLanguage = .en
    ) -> String {
        switch language {
        case .en: return "Queued: «\(goal)». It starts when the current one ends."
        case .es: return "En cola: «\(goal)». Empieza al terminar el de ahora."
        }
    }

    /// Instruction to the voice. The prohibition is explicit because the
    /// permissive version cost a cancelled job.
    public static func queuedAnnouncement(
        _ goal: String, _ language: AppLanguage = .en
    ) -> String {
        switch language {
        case .en:
            return "«\(goal)» is queued behind the job running now. Say only "
                + "that you will do it next. Do NOT stop or cancel anything."
        case .es:
            return "«\(goal)» quedó en cola detrás del encargo de ahora. Di "
                + "solo que lo harás enseguida. NO pares ni canceles nada."
        }
    }

    /// What the app understood, shown before the work starts.
    ///
    /// The root of the 2026-08-24 session: speech recognition returned
    /// gibberish, the chat model invented a plausible task from it — checking
    /// the disk — and a job touching the filesystem began on something the
    /// user never said. She only found out from the report.
    ///
    /// Verbatim, never paraphrased: rewording it would be the same trap in a
    /// second layer. What is shown has to be what will be done.
    public static func heardNotice(
        _ goal: String, _ language: AppLanguage = .en
    ) -> String {
        switch language {
        case .en: return "Heard: «\(goal)». Say stop if that is not it."
        case .es: return "Entendí: «\(goal)». Dime para si no es eso."
        }
    }

    /// Typing already showed you your own words; repeating them would be the
    /// filler this thread has too much of already.
    public static func needsHeardNotice(bornFromVoice: Bool) -> Bool {
        bornFromVoice
    }

    public static func jobDoneAnnouncement(
        _ goal: String, _ language: AppLanguage = .en
    ) -> String {
        switch language {
        case .en:
            // The reply on screen is the truth — a success OR a "could not".
            // The old copy commanded "say it is done" unconditionally, so a
            // polite refusal (which the CLI returns with is_error:false) got
            // announced as a finished job. Acknowledge what the reply SAYS.
            return "The specialist answered «\(goal)»; the reply is on "
                + "screen. Acknowledge in one line what it says — do not add "
                + "details you were not given, do not read the result back, "
                + "and do not say it worked unless the reply says so."
        case .es:
            return "El especialista respondió «\(goal)»; la respuesta está "
                + "en pantalla. Acusa en una línea lo que dice — no añadas "
                + "detalles que no te dieron, no releas el resultado, y no "
                + "digas que salió bien salvo que la respuesta lo diga."
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
