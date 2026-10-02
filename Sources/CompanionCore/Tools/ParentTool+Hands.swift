import Foundation

// Wave 15g. The hands' half of `ParentTool`: their schemas, their copy and
// the one rule that sends them to the sheet. Apart from ParentTools.swift so
// the always-offered tools and the Accessibility-only ones read separately.

extension ParentTool {
    func handsSpec(_ language: AppLanguage) -> ToolSpec {
        let keys = NamedKey.allCases.map(\.rawValue).joined(separator: ", ")
        switch (self, language) {
        case (.typeText, .en):
            return ToolSpec(
                name: rawValue,
                description: "Type text into the text field that has focus in "
                    + "the app in front. Never presses Return: call press_key "
                    + "for that.",
                properties: [ToolProperty(
                    name: "text", type: "string", description: "the exact text to type")],
                required: ["text"])
        case (.typeText, .es):
            return ToolSpec(
                name: rawValue,
                description: "Escribe texto en el campo que tiene el foco en la "
                    + "app que está delante. Nunca pulsa Return: para eso, "
                    + "press_key.",
                properties: [ToolProperty(
                    name: "text", type: "string", description: "el texto exacto a escribir")],
                required: ["text"])
        case (.pressKey, .en):
            return ToolSpec(
                name: rawValue,
                description: "Press one key in the app in front, with no "
                    + "modifiers. Only: \(keys).",
                properties: [ToolProperty(
                    name: "key", type: "string", description: "one of: \(keys)")],
                required: ["key"])
        case (.pressKey, .es):
            return ToolSpec(
                name: rawValue,
                description: "Pulsa una tecla en la app que está delante, sin "
                    + "modificadores. Solo: \(keys).",
                properties: [ToolProperty(
                    name: "key", type: "string", description: "una de: \(keys)")],
                required: ["key"])
        case (.focusWindow, .en):
            return ToolSpec(
                name: rawValue,
                description: "Raise the window of the app in front whose title "
                    + "contains the given words.",
                properties: [ToolProperty(
                    name: "title", type: "string",
                    description: "part of the window title, e.g. Jev-voice")],
                required: ["title"])
        case (.focusWindow, .es):
            return ToolSpec(
                name: rawValue,
                description: "Trae al frente la ventana de la app que está "
                    + "delante cuyo título contiene esas palabras.",
                properties: [ToolProperty(
                    name: "title", type: "string",
                    description: "parte del título de la ventana, p. ej. Jev-voice")],
                required: ["title"])
        case (.readFocused, .en):
            return ToolSpec(
                name: rawValue,
                description: "Read the text of the focused field in the app in "
                    + "front (at most \(FocusedText.limit) characters). Use it to "
                    + "check what was typed.",
                properties: [], required: [])
        case (.readFocused, .es):
            return ToolSpec(
                name: rawValue,
                description: "Lee el texto del campo enfocado en la app que está "
                    + "delante (como mucho \(FocusedText.limit) caracteres). "
                    + "Úsala para comprobar lo escrito.",
                properties: [], required: [])
        case (.openApp, _), (.openURL, _), (.openFile, _), (.listApps, _), (.readSkill, _),
             (.look, _), (.click, _), (.scroll, _), (.menu, _), (.see, _):
            return spec(language)
        }
    }
}

/// Wave 15g §3, tightened by the 2026-09-25 review: what the hands type or
/// send is tied to the user's own words. In a command app (a shell or a
/// coding agent) typed text becomes a command, so only a single line the
/// user said runs without the sheet, and Return always asks. Elsewhere an
/// address nobody said asks, and Return asks unless the user asked to send.
/// Pure: the runner says which app is the target.
package enum HandsVerdict: Equatable, Sendable {
    case act
    case ask
    case refuse(String)
}

package enum HandsGate {
    package static func verdict(_ call: ToolCallRef, commandApp: Bool, said: String) -> HandsVerdict {
        guard let arguments = ToolArguments.parse(call.arguments) else { return .act }
        switch ParentTool(rawValue: call.name) {
        case .pressKey:
            guard isReturn(arguments["key"] as? String) else { return .act }
            if commandApp { return .ask }
            return HandsWords.asksToSend(said) ? .act : .ask
        case .typeText:
            let text = arguments["text"] as? String ?? ""
            if commandApp {
                if HandsWords.hasControl(text, format: true) { return .refuse("control_characters") }
                let single = !text.contains(where: \.isNewline)
                return single && HandsWords.said(text, in: said) ? .act : .ask
            }
            return typeVerdict(text: text, said: said)
        default:
            return .act
        }
    }

    /// Outside a command app, typed text that reads as an address or flag
    /// asks unless the user said it. Shared with the browser's `type` so the
    /// rule has one home.
    package static func typeVerdict(text: String, said: String) -> HandsVerdict {
        let clean = stripped(text)
        return HandsWords.looksLikeAddress(clean) && !HandsWords.said(clean, in: said)
            ? .ask : .act
    }

    /// Wave 16a: a click acts, unless its button deletes, pays or sends and
    /// the user did not ask for that with a word of the same family.
    /// Security review 16: an unlabeled control (an icon) always asks — the
    /// model cannot know it is not the trash can — and a neutral "Sí"/"OK"
    /// is judged by the dialog it sits in.
    package static func clickVerdict(label: String, context: String, said: String) -> HandsVerdict {
        guard !isUnlabeled(label) else { return .ask }
        guard let family = family(label: label, context: context) else { return .act }
        return HandsWords.asks(family: family, in: said) ? .act : .ask
    }

    /// The runner's own check for a click, without the user's words: a
    /// destructive or unlabeled button spends a ticket only the gate issues.
    package static func clickNeedsTicket(label: String, context: String) -> Bool {
        isUnlabeled(label) || family(label: label, context: context) != nil
    }

    /// A menu item is a button the model names by path: the item at the end
    /// is what runs, so it is judged by the same families as a click's label.
    /// Submenu titles on the way ("Trash > Open") do not act by themselves.
    /// `resolved` is the title the adapter would really press: a partial
    /// name ("Empty") matches "Empty Trash…", so the typed name alone can
    /// never clear an item.
    package static func menuNeedsTicket(path: [String], resolved: String? = nil) -> Bool {
        !menuFamilies(path: path, resolved: resolved).isEmpty
    }

    package static func menuVerdict(path: [String], resolved: String? = nil, said: String) -> HandsVerdict {
        let families = menuFamilies(path: path, resolved: resolved)
        return families.allSatisfy { HandsWords.asks($0, in: said) } ? .act : .ask
    }

    /// The click families plus quit/close, which only the menu bar has.
    private static func menuFamilies(path: [String], resolved: String?) -> Set<Set<String>> {
        let labels = [path.last, resolved].compactMap { $0 }
        let shared = labels.compactMap { family(label: $0, context: "") }.map { HandsWords.destructiveFamilies[$0] }
        let quits = labels.contains(where: HandsWords.isMenuQuit) ? [HandsWords.menuQuitFamily] : []
        return Set(shared + quits)
    }

    /// "Archivo > Exportar" as its parts; empty when the argument is absent.
    package static func menuPath(_ arguments: [String: Any]) -> [String] {
        (arguments["path"] as? String ?? "")
            .split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The sheet for a destructive menu item names the path and the app,
    /// with the item that would really be pressed, not the model's partial.
    package static func menuRequest(
        _ call: ToolCallRef, path: [String], resolved: String? = nil, app: String
    ) -> ApprovalRequest {
        let shown = (path.dropLast() + [resolved ?? path.last].compactMap { $0 }).joined(separator: " > ")
        return ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: "menu \(shown) in \(app)",
            inputJSON: encode(["path": shown, "app": app]))
    }

    private static func isUnlabeled(_ label: String) -> Bool {
        HandsWords.words(label).isEmpty
    }

    private static func family(label: String, context: String) -> Int? {
        if let own = HandsWords.destructiveFamily(of: label) { return own }
        guard !HandsWords.isCancel(label) else { return nil }
        return HandsWords.destructiveFamily(of: context)
    }

    /// The runner's own check, without the user's words: in a command app
    /// typing and Return spend a ticket that only the gate can issue, so a
    /// path that skipped the gate fails closed.
    package static func needsTicket(_ call: ToolCallRef, commandApp: Bool) -> Bool {
        guard commandApp, let arguments = ToolArguments.parse(call.arguments) else { return false }
        switch ParentTool(rawValue: call.name) {
        case .pressKey: return isReturn(arguments["key"] as? String)
        case .typeText: return true
        default: return false
        }
    }

    /// Outside a command app a stray escape or control byte is noise, not
    /// intent; line breaks and tabs are text.
    package static func stripped(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !HandsWords.isControl($0, format: false)
        }))
    }

    private static func isReturn(_ raw: String?) -> Bool {
        guard let raw else { return false }
        do {
            return try NamedKey.parse(raw) == .return
        } catch {
            // Refused by the schema when it runs; nothing to ask about.
            return false
        }
    }

    /// The sheet shows what the user has to judge: the whole text that
    /// would be typed, or the key with the app that receives it and — in a
    /// command app — the line Return would run (`line`, read by the runner).
    package static func request(
        _ call: ToolCallRef, app: String, commandApp: Bool, line: String? = nil
    ) -> ApprovalRequest {
        let arguments = ToolArguments.parse(call.arguments) ?? [:]
        var input: [String: Any] = ["app": app, "terminal": commandApp]
        if let line { input["line"] = line }
        let summary: String
        if let key = arguments["key"] as? String {
            let name = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            input["key"] = name
            summary = "press \(name) in \(app)"
        } else {
            let text = arguments["text"] as? String ?? ""
            input["text"] = text
            summary = "type \(text.count) chars in \(app)"
        }
        return ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: summary, inputJSON: encode(input))
    }

    /// The sheet for a destructive click names the button and the app.
    package static func clickRequest(_ call: ToolCallRef, label: String, app: String) -> ApprovalRequest {
        ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: "click \(label) in \(app)",
            inputJSON: encode(["label": label, "app": app]))
    }

    private static func encode(_ object: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            // Only strings and a bool go in; unreachable, and an empty
            // object shows the tool name on the sheet rather than nothing.
            return "{}"
        }
    }
}

extension ParentToolCopy {
    static func handsStatus(
        _ tool: ParentTool, _ outcome: ParentToolOutcome, _ language: AppLanguage
    ) -> String {
        switch (tool, language) {
        // Injecting is not proof the field holds the text (a write with no
        // read after it once reported "written correctly" over 0 bytes).
        case (.typeText, .en): return outcome.verified ? "Typed the text." : "Tried to type the text."
        case (.typeText, .es): return outcome.verified ? "Escribí el texto." : "Intenté escribir el texto."
        case (.pressKey, .en): return "Pressed \(outcome.target)."
        case (.pressKey, .es): return "Pulsé \(outcome.target)."
        // Never the title: this line is saved in the thread.
        case (.focusWindow, .en): return "Brought the window to the front."
        case (.focusWindow, .es): return "Traje la ventana al frente."
        case (.readFocused, .en): return "Read the focused field."
        case (.readFocused, .es): return "Leí el campo enfocado."
        case (.look, _), (.click, _), (.scroll, _), (.menu, _), (.see, _):
            return sightStatus(tool, language)
        default: return "\(tool.rawValue)"
        }
    }

    static func handsFailed(
        _ tool: ParentTool, _ outcome: ParentToolOutcome, _ language: AppLanguage
    ) -> String {
        if outcome.output.hasPrefix("denied_by_user") {
            switch language {
            case .en: return "Did not do it: you said no."
            case .es: return "No lo hice: dijiste que no."
            }
        }
        if tool.isSight || tool == .see { return sightFailed(tool, outcome, language) }
        switch (tool, language) {
        case (.typeText, .en): return "Could not type: \(outcome.output)"
        case (.typeText, .es): return "No pude escribir: \(outcome.output)"
        case (.pressKey, .en): return "Could not press the key: \(outcome.output)"
        case (.pressKey, .es): return "No pude pulsar la tecla: \(outcome.output)"
        case (.focusWindow, .en): return "Could not raise the window: \(outcome.output)"
        case (.focusWindow, .es): return "No pude traer la ventana: \(outcome.output)"
        case (_, .en): return "Could not read the field: \(outcome.output)"
        case (_, .es): return "No pude leer el campo: \(outcome.output)"
        }
    }
}
