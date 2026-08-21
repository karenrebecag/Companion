import CompanionCore
import Testing

@Test @MainActor func configTests() {
    testTalkRoute()
    testProviderDefaults()
    testConfigDefaults()
    testVoiceSettingsClamp()
    testChatSettingsAndRouteEdges()
}

@MainActor func testTalkRoute() {
    let names = ProviderDescriptor.route(preferred: nil).map { $0.name }
    expectEq(names, ["OpenAI", "Groq", "Ollama"],
             "ruta: default OpenAI → Groq → Ollama")

    let groqFirst = ProviderDescriptor.route(preferred: "Groq").map { $0.name }
    expectEq(groqFirst, ["Groq", "OpenAI", "Ollama"],
             "ruta: el preferido encabeza, el resto conserva orden")

    let unknown = ProviderDescriptor.route(preferred: "Gemini").map { $0.name }
    expectEq(unknown, ["OpenAI", "Groq", "Ollama"],
             "ruta: preferido desconocido no rompe — ruta default")

    for p in ProviderDescriptor.catalog {
        expectEq(p.endpoint?.absoluteString ?? "",
                 p.baseURL.absoluteString + "/chat/completions",
                 "endpoint: \(p.name) deriva de la base /v1")
    }
    expect(ProviderDescriptor.ollama.secretKey == nil,
           "ruta: el proveedor local no exige llave")
}

@MainActor func testProviderDefaults() {
    let openAI = ProviderDescriptor.openAI
    expectEq(openAI.id, "openai", "openai: id")
    expectEq(openAI.name, "OpenAI", "openai: name")
    expectEq(openAI.model, "gpt-4o", "openai: gpt-4o")
    expectEq(openAI.baseURL.absoluteString, "https://api.openai.com/v1",
             "openai: base /v1 sin slash final")
    expectEq(openAI.secretKey, .openAI, "openai: OPENAI_API_KEY")
    expectEq(openAI.endpoint?.absoluteString ?? "",
             "https://api.openai.com/v1/chat/completions",
             "openai: endpoint chat/completions")

    let groq = ProviderDescriptor.groq
    expectEq(groq.id, "groq", "groq: id")
    expectEq(groq.name, "Groq", "groq: name")
    expectEq(groq.model, "llama-3.3-70b-versatile", "groq: llama 3.3 70b")
    expectEq(groq.baseURL.absoluteString, "https://api.groq.com/openai/v1",
             "groq: base openai-compatible")
    expectEq(groq.secretKey, .groq, "groq: GROQ_API_KEY")

    let ollama = ProviderDescriptor.ollama
    expectEq(ollama.id, "ollama", "ollama: id")
    expectEq(ollama.name, "Ollama", "ollama: name")
    expectEq(ollama.model, "qwen3.6:27b", "ollama: qwen 3.6 27b")
    expectEq(ollama.baseURL.absoluteString, "http://localhost:11434/v1",
             "ollama: localhost /v1")
    expect(ollama.secretKey == nil, "ollama: sin llave")

    expectEq(ProviderDescriptor.catalog, [openAI, groq, ollama],
             "catalog: OpenAI → Groq → Ollama")
    expectEq(SecretKey.openAI.rawValue, "OPENAI_API_KEY", "secret: OpenAI")
    expectEq(SecretKey.groq.rawValue, "GROQ_API_KEY", "secret: Groq")
    expectEq(SecretKey.openRouter.rawValue, "OPENROUTER_API_KEY",
             "secret: OpenRouter existe aunque no esté en el catálogo")
    expect(!ProviderDescriptor.catalog.contains { $0.secretKey == .openRouter },
           "catalog: OpenRouter no es proveedor de charla")
}

@MainActor func testConfigDefaults() {
    let c = Config.default
    expectEq(c.executors, [ExecutorCatalog.native],
             "config: native siempre en default")
    expectEq(c.voice.voice, VoiceID.marin, "config: voz default marin")
    expectEq(c.chat.historyWindow, 20, "config: ventana de historial 20")
    expect(c.chat.preferredProviderName == nil,
           "config: sin proveedor preferido")
    expectEq(c.chat.inactivityTimeout, 15, "config: inactividad 15 s")
    expectEq(c.chat.turnTimeout, 60, "config: tope de turno 60 s")
    expect(c.workdir == nil, "config: workdir vacío hasta que lo inyecten")
    expectEq(c.ownerFirstName, "", "config: dueña no se lee del entorno")
    expectEq(c.voice.speed, 1.0, "config: speed 1.0")
    expectEq(c.voice.volume, 1.0, "config: volume 1.0")
    expectEq(c.voice.tone, "", "config: tone vacío")
    expectEq(c.voice.echoCancellation, true,
             "config: AEC encendida por default — sin ella el servidor no oye "
             + "a la usuaria mientras el agente habla, y no hay barge-in")
    if case .serverVAD(let ms) = c.voice.turnDetection {
        expectEq(ms, 700, "config: server VAD 700 ms")
    } else {
        expect(false, "config: turn detection default server VAD")
    }
    expectEq(VoiceSettings.speedRange, 0.25 ... 1.5, "config: speedRange API")
    expectEq(VoiceSettings.silenceRange, 200 ... 1500,
             "config: silenceRange útil")
    expect(VoiceID.allCases.contains(.marin)
            && VoiceID.allCases.contains(.cedar)
            && VoiceID.allCases.count == 10,
           "config: las 10 voces de Realtime")
    expectEq(Eagerness.allCases.map(\.rawValue), ["low", "auto", "high"],
             "config: eagerness de semantic_vad")
}

@MainActor func testVoiceSettingsClamp() {
    let slow = VoiceSettings(
        voice: .alloy, speed: 0.1, volume: -4,
        turnDetection: .serverVAD(silenceMs: 50),
        tone: "cálida", echoCancellation: true)
    expectEq(slow.speed, 0.25, "voice: speed piso 0.25")
    expectEq(slow.volume, 0, "voice: volume piso 0")
    if case .serverVAD(let ms) = slow.turnDetection {
        expectEq(ms, 200, "voice: silencio piso 200")
    } else {
        expect(false, "voice: debía seguir en server VAD")
    }
    expectEq(slow.voice, .alloy, "voice: timbre no se clampa")
    expectEq(slow.tone, "cálida", "voice: tono unicode sobrevive")
    expect(slow.echoCancellation, "voice: eco opt-in se conserva")

    let fast = VoiceSettings(
        speed: 9, volume: 4,
        turnDetection: .serverVAD(silenceMs: 5000))
    expectEq(fast.speed, 1.5, "voice: speed techo 1.5")
    expectEq(fast.volume, 1, "voice: volume techo 1")
    if case .serverVAD(let ms) = fast.turnDetection {
        expectEq(ms, 1500, "voice: silencio techo 1500")
    } else {
        expect(false, "voice: debía seguir en server VAD")
    }

    var mutated = VoiceSettings.default
    mutated.speed = 99
    mutated.volume = -1
    mutated.turnDetection = .serverVAD(silenceMs: 1)
    expectEq(mutated.speed, 1.5, "voice: clamp también en set")
    expectEq(mutated.volume, 0, "voice: volume clamp en set")
    if case .serverVAD(let ms) = mutated.turnDetection {
        expectEq(ms, 200, "voice: silencio clamp en set")
    } else {
        expect(false, "voice: set debía conservar server VAD")
    }

    var semantic = VoiceSettings.default
    semantic.turnDetection = .semanticVAD(eagerness: .high)
    if case .semanticVAD(let e) = semantic.turnDetection {
        expectEq(e, .high, "voice: semantic_vad no se reescribe")
    } else {
        expect(false, "voice: debía quedar semantic VAD")
    }
}

@MainActor func testChatSettingsAndRouteEdges() {
    expectEq(ProviderDescriptor.route(preferred: "").map(\.name),
             ["OpenAI", "Groq", "Ollama"],
             "ruta: preferido vacío es ruta default")
    expect(ProviderDescriptor.route(preferred: "OpenAI", catalog: []).isEmpty,
           "ruta: catálogo vacío no inventa proveedores")

    let custom = [ProviderDescriptor.ollama, ProviderDescriptor.groq]
    expectEq(ProviderDescriptor.route(preferred: nil, catalog: custom).map(\.name),
             ["Ollama", "Groq"],
             "ruta: catálogo custom conserva orden")
    expectEq(ProviderDescriptor.route(preferred: "Groq", catalog: custom).map(\.name),
             ["Groq", "Ollama"],
             "ruta: preferido custom encabeza, el resto conserva orden")
    expectEq(ProviderDescriptor.route(preferred: "openai", catalog: custom).map(\.name),
             ["Ollama", "Groq"],
             "ruta: se compara por name, no por id")

    let chat = ChatSettings(
        preferredProviderName: "Groq",
        historyWindow: 0,
        inactivityTimeout: 0,
        turnTimeout: 0)
    expectEq(chat.preferredProviderName, "Groq", "chat: preferido se guarda")
    expectEq(chat.historyWindow, 0, "chat: ventana 0 es válida (sin historial)")
    expectEq(
        ProviderDescriptor.route(preferred: chat.preferredProviderName).map(\.name),
        ["Groq", "OpenAI", "Ollama"],
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
