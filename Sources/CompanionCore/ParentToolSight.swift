import Foundation

// Wave 16a. The sight's half of `ParentTool`: schemas and copy for look,
// click, scroll and menu, apart from the typing hands of 15g.

extension ParentTool {
    func sightSpec(_ language: AppLanguage) -> ToolSpec {
        let en = language == .en
        switch self {
        case .look:
            return ToolSpec(
                name: rawValue,
                description: en
                    ? "See the window in front: its buttons, links, fields and text, each "
                        + "control numbered. Call it before click; ids change with every look."
                    : "Mira la ventana que está delante: sus botones, enlaces, campos y "
                        + "texto, cada control con un número. Úsala antes de click; los "
                        + "números cambian con cada look.",
                properties: [], required: [])
        case .click:
            return ToolSpec(
                name: rawValue,
                description: en
                    ? "Press the control with this id from your latest look."
                    : "Pulsa el control con este número de tu último look.",
                properties: [ToolProperty(
                    name: "id", type: "integer",
                    description: en ? "the number shown by look" : "el número que dio look")],
                required: ["id"])
        case .scroll:
            return ToolSpec(
                name: rawValue,
                description: en
                    ? "Scroll the window in front one page up or down, or the list that "
                        + "contains the control with this id. Then look again."
                    : "Desplaza una página arriba o abajo la ventana de delante, o la lista "
                        + "que contiene el control con ese número. Después, vuelve a mirar.",
                properties: [
                    ToolProperty(name: "direction", type: "string", description: "up | down"),
                    ToolProperty(
                        name: "id", type: "integer",
                        description: en ? "optional: a control inside the list"
                            : "opcional: un control dentro de la lista"),
                ],
                required: ["direction"])
        case .see:
            return ToolSpec(
                name: rawValue,
                description: en
                    ? "Read the window in front from a screenshot: its text verbatim, "
                        + "navigation labels, and images or charts briefly. Slower than look; "
                        + "use look to read or press controls."
                    : "Lee la ventana de delante a partir de una captura: su texto literal, "
                        + "las etiquetas de navegación y, en breve, imágenes o gráficas. Más "
                        + "lenta que look; para leer o pulsar controles, look.",
                properties: [ToolProperty(
                    name: "question", type: "string",
                    description: en ? "optional: what to look for in the window"
                        : "opcional: qué buscar en la ventana")],
                required: [])
        default:
            return ToolSpec(
                name: ParentTool.menu.rawValue,
                description: en
                    ? "Choose a menu-bar item of the app in front, e.g. \"File > Export as PDF…\"."
                    : "Elige un elemento de la barra de menús de la app de delante, p. ej. "
                        + "\"Archivo > Exportar como PDF…\".",
                properties: [ToolProperty(
                    name: "path", type: "string",
                    description: en ? "menu names separated by >" : "nombres de menú separados por >")],
                required: ["path"])
        }
    }
}

extension ParentToolCopy {
    static func sightStatus(_ tool: ParentTool, _ language: AppLanguage) -> String {
        switch (tool, language) {
        case (.look, .en): return "Looked at the window."
        case (.look, .es): return "Miré la ventana."
        case (.click, .en): return "Clicked."
        case (.click, .es): return "Pulsé."
        case (.scroll, .en): return "Scrolled."
        case (.scroll, .es): return "Desplacé la ventana."
        case (.see, .en): return "Looked at the screen."
        case (.see, .es): return "Miré la pantalla."
        case (_, .en): return "Chose the menu item."
        case (_, .es): return "Elegí la opción del menú."
        }
    }

    static func sightFailed(
        _ tool: ParentTool, _ outcome: ParentToolOutcome, _ language: AppLanguage
    ) -> String {
        if outcome.output.hasPrefix("denied_by_user") {
            return language == .en ? "Did not do it: you said no." : "No lo hice: dijiste que no."
        }
        let code = outcome.output.split(separator: ":").first.map(String.init) ?? outcome.output
        switch (tool, language) {
        case (.look, .en): return "Could not see the window (\(code))."
        case (.look, .es): return "No pude ver la ventana (\(code))."
        case (.click, .en): return "Could not click (\(code))."
        case (.click, .es): return "No pude pulsar (\(code))."
        case (.scroll, .en): return "Could not scroll (\(code))."
        case (.scroll, .es): return "No pude desplazar (\(code))."
        case (.see, .en): return "Could not see the screen (\(code))."
        case (.see, .es): return "No pude ver la pantalla (\(code))."
        case (_, .en): return "Could not choose the menu item (\(code))."
        case (_, .es): return "No pude elegir la opción del menú (\(code))."
        }
    }
}
