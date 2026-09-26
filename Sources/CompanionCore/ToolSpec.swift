import Foundation

public struct ToolProperty: Sendable, Equatable {
    public var name: String
    public var type: String
    public var description: String

    public init(name: String, type: String, description: String) {
        self.name = name
        self.type = type
        self.description = description
    }
}

public struct ToolSpec: Sendable, Equatable {
    public var name: String
    public var description: String
    public var properties: [ToolProperty]
    public var required: [String]

    public init(
        name: String,
        description: String,
        properties: [ToolProperty],
        required: [String]
    ) {
        self.name = name
        self.description = description
        self.properties = properties
        self.required = required
    }

    /// Names are wire contract and never translate; descriptions are read by
    /// the model and must match the language it answers in, or it reasons in
    /// one language and speaks another.
    public static func delegate(_ language: AppLanguage = .en) -> ToolSpec {
        switch language {
        case .en:
            return ToolSpec(
                name: "delegate",
                description: "Hand the turn to the specialist, which does "
                    + "have a shell, the files, this Mac's tools and "
                    + "internet access. Use it for ANYTHING touching disk, "
                    + "code, folders, commands, technical work, web searches "
                    + "or reading pages. Never for typing into an app.",
                properties: [
                    ToolProperty(name: "goal", type: "string",
                                 description: "what is needed, one line"),
                    ToolProperty(name: "context", type: "string",
                                 description: "what the specialist should know"),
                ],
                required: ["goal"])
        case .es:
            return ToolSpec(
                name: "delegate",
                description: "Pasa el turno al especialista, que sí tiene una "
                    + "shell, los archivos, las herramientas de esta Mac y "
                    + "acceso a internet. Úsala para TODO lo que toque disco, "
                    + "código, carpetas, comandos, trabajo técnico, búsquedas "
                    + "en la web o lectura de páginas. Nunca para escribir en "
                    + "un campo o app.",
                properties: [
                    ToolProperty(name: "goal", type: "string",
                                 description: "qué se necesita, una línea"),
                    ToolProperty(name: "context", type: "string",
                                 description: "lo que el especialista debe saber"),
                ],
                required: ["goal"])
        }
    }

    /// The brake, by voice. Without it the only way to stop a job you never
    /// asked for was the button — and someone talking to their Mac is not
    /// looking at it. Denying a permission was never a stop: it refused one
    /// command and the job carried on.
    public static func stopJob(_ language: AppLanguage = .en) -> ToolSpec {
        switch language {
        case .en:
            return ToolSpec(
                name: "stop_job",
                description: "Stop the job the specialist is running now. "
                    + "ONLY when the user explicitly asks to stop or cancel — "
                    + "\"stop\", \"cancel\", \"leave it\". Asking for something "
                    + "ELSE is not a request to stop: a new task is queued "
                    + "behind this one, and calling this would throw away work "
                    + "they still want. What was already done is kept.",
                properties: [],
                required: [])
        case .es:
            return ToolSpec(
                name: "stop_job",
                description: "Para el encargo que el especialista está "
                    + "haciendo ahora. SOLO cuando la usuaria pida parar o "
                    + "cancelar de forma explícita — \"para\", \"cancela\", "
                    + "\"déjalo\". Pedir OTRA cosa no es pedir que pares: una "
                    + "tarea nueva se encola detrás de esta, y llamarte aquí "
                    + "tiraría trabajo que todavía quiere. Lo ya hecho se "
                    + "conserva.",
                properties: [],
                required: [])
        }
    }

    public static func resolveApproval(
        _ language: AppLanguage = .en
    ) -> ToolSpec {
        switch language {
        case .en:
            return ToolSpec(
                name: "resolve_approval",
                description: "Answer the specialist's pending permission "
                    + "request, which is waiting on screen. Use it when the "
                    + "user says whether they allow it; never invent an "
                    + "answer they did not give.",
                properties: [
                    ToolProperty(name: "approved", type: "boolean",
                                 description: "true if the user allowed it"),
                ],
                required: ["approved"])
        case .es:
            return ToolSpec(
                name: "resolve_approval",
                description: "Responde la solicitud de permiso pendiente del "
                    + "especialista, que está esperando en pantalla. Úsala "
                    + "cuando el usuario diga si lo autoriza; nunca inventes "
                    + "una respuesta que no dio.",
                properties: [
                    ToolProperty(name: "approved", type: "boolean",
                                 description: "true si el usuario lo autorizó"),
                ],
                required: ["approved"])
        }
    }

    /// Realtime is flat (`name` at the top); chat completions nest under `function`.
    public func encodeRealtime() -> String {
        encodeJSON(realtimeObject())
    }

    /// `strict: true` is OpenAI's own answer to malformed arguments (Wave
    /// 10c 3A.4, layer 1). Its contract: `additionalProperties: false`,
    /// every property in `required`, and the optional ones nullable. Only
    /// for providers that take the field; the rest get the plain shape.
    public func encodeChat(strict: Bool = false) -> String {
        var function = functionBody(strict: strict)
        if strict { function["strict"] = true }
        return encodeJSON([
            "type": "function",
            "function": function,
        ])
    }

    func realtimeObject() -> [String: Any] {
        var obj = functionBody(strict: false)
        obj["type"] = "function"
        return obj
    }

    private func functionBody(strict: Bool) -> [String: Any] {
        var props: [String: Any] = [:]
        for property in properties {
            let optional = !required.contains(property.name)
            let type: Any = strict && optional ? [property.type, "null"] : property.type
            props[property.name] = [
                "type": type,
                "description": property.description,
            ]
        }
        var parameters: [String: Any] = [
            "type": "object",
            "properties": props,
            "required": strict ? properties.map(\.name) : required,
        ]
        if strict { parameters["additionalProperties"] = false }
        return [
            "name": name,
            "description": description,
            "parameters": parameters,
        ]
    }
}

func encodeJSON(_ obj: [String: Any]) -> String {
    do {
        let data = try JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        return "{}"
    }
}

func jsonObject(from text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    do {
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    } catch {
        return nil
    }
}

/// `as? Bool` is true for JSON `1` because NSNumber bridges. Permissions
/// must require a real JSON boolean.
func jsonBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID()
    else { return nil }
    return number.boolValue
}
