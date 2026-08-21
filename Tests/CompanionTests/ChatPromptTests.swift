import CompanionCore
import Testing

@Test @MainActor func chatPromptTests() {
    testPromptEmptyOwner()
    testPromptNamedOwner()
    testPromptPersonalityAlways()
    testPromptIdentity()
    testPromptDelegateEnabled()
    testPromptDelegateDisabled()
    testPromptOwnerEdges()
}

@MainActor func testPromptEmptyOwner() {
    let p = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false)
    expect(p.hasPrefix("Eres Companion, asistente de voz en esta Mac."),
           "prompt: sin dueña arranca en esta Mac")
    expect(!p.contains("en la Mac de"),
           "prompt: sin dueña no inventa un nombre")
}

@MainActor func testPromptNamedOwner() {
    let p = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false)
    expect(p.contains("en la Mac de Karen"),
           "prompt: con dueña nombra la Mac")
    expect(!p.contains("en esta Mac"),
           "prompt: con dueña no usa el fallback genérico")
    expect(p.hasPrefix("Eres Companion, asistente de voz en la Mac de Karen."),
           "prompt: el saludo con nombre encabeza")
}

@MainActor func testPromptPersonalityAlways() {
    let empty = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false)
    let named = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true)
    for (p, label) in [(empty, "vacío"), (named, "Karen")] {
        expect(p.contains("Español, cálido, directo, 2 a 4 frases."),
               "prompt: personalidad siempre aplica (\(label))")
        expect(p.contains("Charla, no un informe."),
               "prompt: el cierre de tono siempre aplica (\(label))")
    }
}

@MainActor func testPromptIdentity() {
    let p = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false)
    expect(p.contains("No eres Hermes"),
           "prompt: no es Hermes")
    expect(p.contains("no eres un TUI"),
           "prompt: no es un TUI")
    expect(p.contains("no estás en una terminal"),
           "prompt: no está en una terminal")
    expect(p.contains("No inventes backends ni rutas internas."),
           "prompt: no inventa backends")
    expect(p.contains("Si no sabes algo, dilo."),
           "prompt: si no sabe, lo dice")
}

@MainActor func testPromptDelegateEnabled() {
    let p = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true)
    expect(p.contains("delegate"),
           "prompt: con delegación nombra la tool delegate")
    expect(p.contains("especialista"),
           "prompt: con delegación nombra al especialista")
    expect(p.contains("archivos"),
           "prompt: el especialista tiene archivos")
    expect(p.contains("terminal"),
           "prompt: el especialista tiene terminal")
    expect(p.contains("internet") || p.contains("INTERNET"),
           "prompt: el especialista tiene internet")
    expect(p.contains("Español, cálido, directo, 2 a 4 frases."),
           "prompt: delegar no se come la personalidad")
}

@MainActor func testPromptDelegateDisabled() {
    let p = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false)
    expect(!p.contains("delegate"),
           "prompt: sin delegación no menciona delegate")
    expect(!p.contains("especialista"),
           "prompt: sin delegación no menciona especialista")
    expect(!p.contains("delega"),
           "prompt: sin delegación no pide delegar")
}

@MainActor func testPromptOwnerEdges() {
    let spaces = ChatPrompt.system(ownerFirstName: "   \n", delegateEnabled: false)
    expect(spaces.hasPrefix("Eres Companion, asistente de voz en esta Mac."),
           "prompt: nombre solo espacios es dueña vacía")
    expect(!spaces.contains("en la Mac de"),
           "prompt: espacios no se interpolan como nombre")

    let padded = ChatPrompt.system(ownerFirstName: "  Karen  ", delegateEnabled: false)
    expect(padded.contains("en la Mac de Karen"),
           "prompt: recorta el nombre antes de interpolar")
    expect(!padded.contains("en la Mac de  Karen"),
           "prompt: no deja espacios alrededor del nombre")

    let unicode = ChatPrompt.system(ownerFirstName: "María", delegateEnabled: false)
    expect(unicode.contains("en la Mac de María"),
           "prompt: unicode en el nombre viaja")

    let special = ChatPrompt.system(
        ownerFirstName: "Ana; DROP", delegateEnabled: false)
    expect(special.contains("en la Mac de Ana; DROP"),
           "prompt: el nombre no se sanitiza — es un dato, no SQL")

    let a = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false)
    let b = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false)
    expectEq(a, b, "prompt: la misma entrada produce el mismo texto")
}
