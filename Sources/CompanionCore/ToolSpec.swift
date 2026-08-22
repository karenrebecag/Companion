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
                    + "have the files, the terminal, this Mac's tools and "
                    + "internet access. Use it for ANYTHING touching disk, "
                    + "code, folders, commands, technical work, web searches "
                    + "or reading pages.",
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
                description: "Pasa el turno al especialista, que sí tiene los "
                    + "archivos, la terminal, las herramientas de esta Mac y "
                    + "acceso a internet. Úsala para TODO lo que toque disco, "
                    + "código, carpetas, comandos, trabajo técnico, búsquedas "
                    + "en la web o lectura de páginas.",
                properties: [
                    ToolProperty(name: "goal", type: "string",
                                 description: "qué se necesita, una línea"),
                    ToolProperty(name: "context", type: "string",
                                 description: "lo que el especialista debe saber"),
                ],
                required: ["goal"])
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
                    + "request. Use it ONLY after the system announces a "
                    + "request and the user replies.",
                properties: [
                    ToolProperty(name: "approved", type: "boolean",
                                 description: "true if the user allowed it"),
                ],
                required: ["approved"])
        case .es:
            return ToolSpec(
                name: "resolve_approval",
                description: "Responde la solicitud de permiso pendiente del "
                    + "especialista. Úsala SOLO después de que el sistema "
                    + "anuncie que pide permiso y el usuario conteste.",
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

    public func encodeChat() -> String {
        encodeJSON([
            "type": "function",
            "function": functionBody(),
        ])
    }

    func realtimeObject() -> [String: Any] {
        var obj = functionBody()
        obj["type"] = "function"
        return obj
    }

    private func functionBody() -> [String: Any] {
        var props: [String: Any] = [:]
        for property in properties {
            props[property.name] = [
                "type": property.type,
                "description": property.description,
            ]
        }
        return [
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": props,
                "required": required,
            ],
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
