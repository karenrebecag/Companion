import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func chatParametersTests() {
    testSamplingModelsKeepTheirTemperature()
    testReasoningModelsRefuseTemperature()
    testTheHeuristicIsNotFooledBySubstrings()
    testDescriptorsCarryATemperature()
    testResolvingTheLocalModelKeepsItsTemperature()
    testAnOverriddenModelDropsTheInheritedTemperature()
}

@MainActor func testSamplingModelsKeepTheirTemperature() {
    for model in ["gpt-4o", "llama-3.3-70b-versatile", "qwen3:14b",
                  "openai/gpt-4o", "claude-sonnet-4-5"] {
        expect(ChatParameters.acceptsTemperature(model),
               "\(model) muestrea: la temperatura le sirve")
    }
}

@MainActor func testReasoningModelsRefuseTemperature() {
    // No la ignoran: devuelven 400 con `unsupported_value`. Con la escalera
    // eso se lee como "no hay proveedor disponible", que manda a Karen a
    // buscar el fallo donde no esta.
    for model in ["o1", "o1-mini", "o3", "o3-mini", "o4-mini",
                  "gpt-5", "gpt-5-mini", "gpt-5.2",
                  "gpt-oss-120b", "openai/gpt-oss-120b"] {
        expect(!ChatParameters.acceptsTemperature(model),
               "\(model) razona: la temperatura la rechaza el proveedor")
    }
}

@MainActor func testTheHeuristicIsNotFooledBySubstrings() {
    // "o3" dentro de otro nombre no convierte al modelo en razonador.
    expect(ChatParameters.acceptsTemperature("mistral-nemo3"),
           "un 3 pegado a otra cosa no es o3")
    expect(ChatParameters.acceptsTemperature("qwen3.6:27b"),
           "ni un qwen con punto tres")
}

@MainActor func testDescriptorsCarryATemperature() {
    expect(ProviderDescriptor.openAI.temperature != nil,
           "el catalogo conserva el valor que ya usaba")
}

@MainActor func testResolvingTheLocalModelKeepsItsTemperature() {
    // El descriptor de Ollama pasa por withModel en CADA arranque, porque su
    // tag se resuelve en runtime. Soltar la temperatura siempre habria dejado
    // todas las peticiones locales sin ella.
    let resolved = ProviderDescriptor.ollama.withModel("qwen3:14b")
    expectEq(resolved.temperature, ProviderDescriptor.ollama.temperature,
             "resolver el tag local no cambia como muestrea")
}

@MainActor func testAnOverriddenModelDropsTheInheritedTemperature() {
    // Cambiar el modelo de una fila del catalogo no puede arrastrar una
    // temperatura elegida para OTRO modelo: es justo el caso que 9b-3 abre.
    let switched = ProviderDescriptor.openAI.withModel("gpt-5")
    expect(switched.temperature == nil,
           "al cambiar de modelo, la temperatura heredada se suelta")
}

@Test @MainActor func temperatureInTheBodyTests() {
    testASamplingModelSendsTemperature()
    testAReasoningModelSendsNoTemperatureAtAll()
    testANilTemperatureIsOmitted()
}

@MainActor private func body(for provider: ProviderDescriptor) -> [String: Any] {
    let transport = ScriptedTransport()
    transport.stub(provider, ScriptedReply(status: 200, lines: []))
    let client = ChatProviderClient(
        secrets: TestSecretStore([.openAI: "sk-test", .openRouter: "sk-test"]),
        probe: TestProbe(available: [provider.id]),
        transport: transport,
        catalog: [provider])
    do {
        _ = try runAsync { () -> Bool in
            for try await _ in client.stream(
                [Turn(role: .user, content: "hola")], tools: []) {}
            return true
        }
    } catch {
        // El stream vacio termina en error; lo que importa es la peticion.
    }
    guard let data = transport.requests.first?.httpBody,
          let json = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any]
    else {
        expect(false, "la peticion debia llevar cuerpo JSON")
        return [:]
    }
    return json
}

@MainActor func testASamplingModelSendsTemperature() {
    let json = body(for: ProviderDescriptor.openAI)
    expect(json["temperature"] != nil, "gpt-4o la sigue recibiendo")
}

@MainActor func testAReasoningModelSendsNoTemperatureAtAll() {
    // No basta con mandar 1: el proveedor rechaza el CAMPO. Se omite.
    let json = body(for: ProviderDescriptor.openAI.withModel("gpt-5"))
    expect(json["temperature"] == nil,
           "con un modelo de razonamiento el campo no viaja")
    expectEq(json["model"] as? String, "gpt-5", "y el modelo si viaja")
}

@MainActor func testANilTemperatureIsOmitted() {
    let custom = ProviderDescriptor(
        id: "custom", name: "Custom",
        baseURL: URL(string: "https://example.com/v1")!,
        model: "gpt-4o", secretKey: .openAI, temperature: nil)
    expect(body(for: custom)["temperature"] == nil,
           "sin temperatura elegida, no se inventa una")
}
