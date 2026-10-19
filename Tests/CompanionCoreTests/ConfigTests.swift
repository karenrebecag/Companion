import CompanionCore
import CompanionTestKit
import Testing

@Test @MainActor func configTests() {
    testTalkRoute()
    testProviderDefaults()
    testChatSettingsAndRouteEdges()
}

@MainActor func testTalkRoute() {
    let names = ProviderDescriptor.route(order: []).map { $0.name }
    expectEq(names, ["Cerebras", "OpenRouter", "Ollama"],
             "ruta: default Cerebras → OpenRouter → Ollama")

    let ollamaFirst = ProviderDescriptor.route(order: ["ollama"]).map { $0.name }
    expectEq(ollamaFirst, ["Ollama", "Cerebras", "OpenRouter"],
             "ruta: el preferido encabeza, el resto conserva orden")

    let unknown = ProviderDescriptor.route(order: ["gemini"]).map { $0.name }
    expectEq(unknown, ["Cerebras", "OpenRouter", "Ollama"],
             "ruta: preferido desconocido no rompe — ruta default")

    // 15e-2: a pre-15e preference may still name Groq; it is ignored now.
    let retired = ProviderDescriptor.route(order: ["groq"]).map { $0.id }
    expectEq(retired, ["cerebras", "openrouter", "ollama"],
             "ruta: un orden guardado con Groq ya no lo resucita")

    for p in ProviderDescriptor.catalog {
        expectEq(p.endpoint?.absoluteString ?? "",
                 p.baseURL.absoluteString + "/chat/completions",
                 "endpoint: \(p.name) deriva de la base /v1")
    }
    expect(ProviderDescriptor.ollama.secretKey == nil,
           "ruta: el proveedor local no exige llave")
}

@MainActor func testProviderDefaults() {

    let openRouter = ProviderDescriptor.openRouter
    let ollama = ProviderDescriptor.ollama
    expectEq(ollama.id, "ollama", "ollama: id")
    expectEq(ollama.name, "Ollama", "ollama: name")
    expectEq(ollama.model, "qwen3.6:27b", "ollama: qwen 3.6 27b")
    expectEq(ollama.baseURL.absoluteString, "http://localhost:11434/v1",
             "ollama: localhost /v1")
    expect(ollama.secretKey == nil, "ollama: sin llave")

    expectEq(ProviderDescriptor.catalog, [ProviderDescriptor.cerebras, openRouter, ollama],
             "catalog: Cerebras → OpenRouter → Ollama, sin OpenAI ni Groq (15e-2)")
    expect(!ProviderDescriptor.catalog.contains { $0.secretKey == .groq },
           "catalog: ninguna fila usa la clave de Groq")
    expectEq(SecretKey.openAI.rawValue, "OPENAI_API_KEY", "secret: OpenAI")
    expectEq(SecretKey.openRouter.rawValue, "OPENROUTER_API_KEY",
             "secret: OpenRouter")
    // Dejo de ser el caso: la enum tenía el caso y le faltaba descriptor, que
    // es justo lo que hacía inalcanzable esa fila (Wave 9b-3).
    expect(ProviderDescriptor.catalog.contains { $0.secretKey == .openRouter },
           "catalog: OpenRouter ya es una fila de verdad")
}

@MainActor func testChatSettingsAndRouteEdges() {
    expectEq(ProviderDescriptor.route(order: [""]).map(\.name),
             ["Cerebras", "OpenRouter", "Ollama"],
             "ruta: preferido vacío es ruta default")
    expect(ProviderDescriptor.route(order: ["openai"], catalog: []).isEmpty,
           "ruta: catálogo vacío no inventa proveedores")

    let custom = [ProviderDescriptor.ollama, ProviderDescriptor.openRouter]
    expectEq(ProviderDescriptor.route(order: [], catalog: custom).map(\.name),
             ["Ollama", "OpenRouter"],
             "ruta: catálogo custom conserva orden")
    expectEq(ProviderDescriptor.route(order: ["openrouter"], catalog: custom).map(\.name),
             ["OpenRouter", "Ollama"],
             "ruta: preferido custom encabeza, el resto conserva orden")
    expectEq(ProviderDescriptor.route(order: ["openai"], catalog: custom).map(\.name),
             ["Ollama", "OpenRouter"],
             "ruta: se compara por name, no por id")

    let chat = ChatSettings(
        providerOrder: ["openrouter"],
        historyWindow: 0,
        inactivityTimeout: 0,
        turnTimeout: 0)
    expectEq(chat.providerOrder, ["openrouter"], "chat: el orden se guarda")
    expectEq(chat.historyWindow, 0, "chat: ventana 0 es válida (sin historial)")
    expectEq(
        ProviderDescriptor.route(order: chat.providerOrder).map(\.name),
        ["OpenRouter", "Cerebras", "Ollama"],
        "chat: el preferido de settings rota la ruta")

    var cfg = Config.default
    cfg.workdir = "/tmp/work"
    cfg.ownerFirstName = "Karen"
    cfg.executors = ExecutorCatalog.list(detected: [
        ExecutorDescriptor(
            id: ExecutorID(rawValue: "claude"),
            shortName: "claude",
            title: "Claude Code",
            kind: .detectedCLI)
    ])
    expectEq(cfg.workdir, "/tmp/work", "config: workdir es snapshot")
    expectEq(cfg.ownerFirstName, "Karen", "config: nombre es snapshot")
    expectEq(cfg.executors.count, 2, "config: ejecutores detectados se guardan")
    expect(cfg != Config.default, "config: Equatable ve el cambio")
}
