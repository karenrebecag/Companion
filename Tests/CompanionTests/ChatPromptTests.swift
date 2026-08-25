import CompanionCore
import Testing

// El inglés es la fuente desde Wave 9; estos casos caracterizan la
// traducción española y la piden explícitamente. La cobertura del inglés
// vive en AppLanguageTests.
@Test @MainActor func chatPromptTests() {
    testPromptEmptyOwner()
    testPromptNamedOwner()
    testPromptPersonalityAlways()
    testPromptIdentity()
    testPromptDelegateEnabled()
    testPromptDelegateDisabled()
    testPromptOwnerEdges()
    testPromptProfileBlock()
}

@MainActor func testPromptEmptyOwner() {
    let p = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false, language: .es)
    expect(p.hasPrefix("Eres Companion, asistente de voz en esta Mac."),
           "prompt: sin dueña arranca en esta Mac")
    expect(!p.contains("en la Mac de"),
           "prompt: sin dueña no inventa un nombre")
}

@MainActor func testPromptNamedOwner() {
    let p = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .es)
    expect(p.contains("en la Mac de Karen"),
           "prompt: con dueña nombra la Mac")
    expect(!p.contains("en esta Mac"),
           "prompt: con dueña no usa el fallback genérico")
    expect(p.hasPrefix("Eres Companion, asistente de voz en la Mac de Karen."),
           "prompt: el saludo con nombre encabeza")
}

@MainActor func testPromptPersonalityAlways() {
    let empty = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false, language: .es)
    let named = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: .es)
    for (p, label) in [(empty, "vacío"), (named, "Karen")] {
        expect(p.contains("Español, cálido, directo, 2 a 4 frases."),
               "prompt: personalidad siempre aplica (\(label))")
        expect(p.contains("Charla, no un informe."),
               "prompt: el cierre de tono siempre aplica (\(label))")
    }
}

@MainActor func testPromptIdentity() {
    let p = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false, language: .es)
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
    let p = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: .es)
    expect(p.contains("delegate"),
           "prompt: con delegación nombra la tool delegate")
    expect(p.contains("especialista"),
           "prompt: con delegación nombra al especialista")
    expect(p.contains("archivos"),
           "prompt: el especialista tiene archivos")
    expect(p.contains("terminal"),
           "prompt: el especialista tiene terminal")
    // Ya no se promete internet incondicionalmente: prometer una busqueda que
    // el producto no puede hacer mandaba al modelo a una tool que siempre
    // fallaba, y volvia diciendo "no puedo buscar en la web" en vez de probar
    // otra via. La promesa era lo que capturaba la intencion (Wave 9f).
    expect(!p.contains("INTERNET"),
           "prompt: sin busqueda configurada no se promete internet")
    expect(p.contains("lugares"),
           "prompt: pero si lo que de verdad puede — consultar lugares")
    let withWeb = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true,
        webSearchEnabled: true, language: .es)
    expect(withWeb.contains("INTERNET"),
           "prompt: con busqueda configurada si se promete")
    expect(p.contains("Español, cálido, directo, 2 a 4 frases."),
           "prompt: delegar no se come la personalidad")
}

@MainActor func testPromptDelegateDisabled() {
    let p = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .es)
    expect(!p.contains("delegate"),
           "prompt: sin delegación no menciona delegate")
    expect(!p.contains("especialista"),
           "prompt: sin delegación no menciona especialista")
    expect(!p.contains("delega"),
           "prompt: sin delegación no pide delegar")
}

@MainActor func testPromptOwnerEdges() {
    let spaces = ChatPrompt.system(ownerFirstName: "   \n", delegateEnabled: false, language: .es)
    expect(spaces.hasPrefix("Eres Companion, asistente de voz en esta Mac."),
           "prompt: nombre solo espacios es dueña vacía")
    expect(!spaces.contains("en la Mac de"),
           "prompt: espacios no se interpolan como nombre")

    let padded = ChatPrompt.system(ownerFirstName: "  Karen  ", delegateEnabled: false, language: .es)
    expect(padded.contains("en la Mac de Karen"),
           "prompt: recorta el nombre antes de interpolar")
    expect(!padded.contains("en la Mac de  Karen"),
           "prompt: no deja espacios alrededor del nombre")

    let unicode = ChatPrompt.system(ownerFirstName: "María", delegateEnabled: false, language: .es)
    expect(unicode.contains("en la Mac de María"),
           "prompt: unicode en el nombre viaja")

    let special = ChatPrompt.system(
        ownerFirstName: "Ana; DROP", delegateEnabled: false, language: .es)
    expect(special.contains("en la Mac de Ana; DROP"),
           "prompt: el nombre no se sanitiza — es un dato, no SQL")

    let a = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .es)
    let b = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .es)
    expectEq(a, b, "prompt: la misma entrada produce el mismo texto")
}

@MainActor func testPromptProfileBlock() {
    let empty = ChatPrompt.profileBlock(about: "  ", instructions: "", language: .es)
    expect(empty == nil, "perfil: vacío no inventa un bloque")

    let about = ChatPrompt.profileBlock(about: "diseña producto", instructions: "", language: .es)
    expectEq(about, "Sobre la usuaria — diseña producto. ",
             "perfil: about viaja como hecho")

    let both = ChatPrompt.profileBlock(
        about: "diseña", instructions: "Sé breve", language: .es)
    expect(both?.contains("Sobre la usuaria — diseña.") == true,
           "perfil: about y instructions conviven")
    expect(both?.contains("Instrucciones personalizadas de la usuaria: Sé breve") == true,
           "perfil: instructions se nombran")

    let wired = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false,
        about: "diseña producto", instructions: "Sé breve", language: .es)
    expect(wired.contains("Sobre la usuaria — diseña producto."),
           "prompt: el perfil entra al system")
    expect(wired.contains("Instrucciones personalizadas de la usuaria: Sé breve"),
           "prompt: las instrucciones entran al system")

    let blank = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, about: "", instructions: "", language: .es)
    expect(!blank.contains("Sobre la usuaria"),
           "prompt: sin perfil no añade el bloque")
}
