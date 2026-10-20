import CompanionCore
import CompanionTestKit
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
    testAGivenPathGoesStraightToTheFileTool()
    testDelegateRuleOnlyForHeavyWork()
    testStructuredContentIsNotAnsweredAsMarkdown()
    testPromptDelegateDisabled()
    testPromptOwnerEdges()
    testPromptProfileBlock()
    testPromptParentToolsActRule()
    testPromptCarriesSkills()
    testPromptSpeaksUserTerms()
}

// QA 606: the delegate rule listed "tables, charts" as answers the model
// writes itself, and gpt-oss took it literally: a bitcoin series came back as
// a markdown table with no card. Structure must point at present, never at
// markdown, in both languages.
@MainActor func testStructuredContentIsNotAnsweredAsMarkdown() {
    let es = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: .es)
    expect(!es.contains("explicaciones, comparaciones, tablas, gráficas"),
           "qa606 es: la regla de delegar no pide tablas ni gráficas en markdown")
    expect(es.contains("van por la tool present, nunca como markdown"),
           "qa606 es: el contenido estructurado va por present")
    let en = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: .en)
    expect(!en.contains("explanations, comparisons, tables, charts"),
           "qa606 en: the delegate rule does not ask for tables or charts as markdown")
    expect(en.contains("go through the present tool, never as markdown"),
           "qa606 en: structured content goes through present")
}

// La respuesta del PDF (captura 2026-09-29) dijo la ruta absoluta y la
// herramienta interna. La regla vive en grounding para que el chat escrito
// y la voz la compartan: términos de la usuaria, nunca rutas ni tripas.
@MainActor func testPromptSpeaksUserTerms() {
    for voice in [false, true] {
        let es = ChatPrompt.system(ownerFirstName: "", delegateEnabled: true,
                                   language: .es, voice: voice)
        expect(es.contains("nunca una ruta absoluta"),
               "prompt es voz=\(voice): prohíbe rutas absolutas")
        expect(es.contains("por su lugar visible"),
               "prompt es voz=\(voice): nombra archivos por su lugar")
        expect(es.contains("cómo lo hiciste por dentro"),
               "prompt es voz=\(voice): sin detalles de implementación")
        let en = ChatPrompt.system(ownerFirstName: "", delegateEnabled: true,
                                   language: .en, voice: voice)
        expect(en.contains("never an absolute path"),
               "prompt en voz=\(voice): prohíbe rutas absolutas")
    }
    // Hiding the mechanism must never hide an effect she cannot see; one she
    // watches happen on screen is not confirmed.
    let acting = ChatPrompt.system(ownerFirstName: "", delegateEnabled: true,
                                   parentToolsEnabled: true, language: .es)
    expect(acting.contains("Un efecto que ella no ve se dice siempre"),
           "prompt: el efecto invisible nunca se calla")
    expect(acting.contains("termina el turno sin texto"),
           "prompt: tras una acción visible exitosa no se narra")
    expect(!acting.contains("di qué hiciste"), "prompt: ya no manda confirmar lo que ella ve")
    let actingEn = ChatPrompt.system(ownerFirstName: "", delegateEnabled: true,
                                     parentToolsEnabled: true, language: .en)
    expect(actingEn.contains("An effect she cannot see is always stated"),
           "prompt en: el efecto invisible nunca se calla")
    expect(actingEn.contains("end the turn with no text"),
           "prompt en: tras una acción visible exitosa no se narra")
    expect(!actingEn.contains("say what you did"), "prompt en: ya no manda confirmar lo que ella ve")
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

// A path or a file name the user gave is read or opened at once: listing its
// folder first cost two round trips before the answer.
@MainActor func testAGivenPathGoesStraightToTheFileTool() {
    for language in [AppLanguage.es, .en] {
        let p = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, language: language)
        let direct = language == .es ? "llama read_file u open_file directo" : "call read_file or open_file on it"
        expect(p.contains(direct), "ruta dada \(language): se llama la tool del archivo directo")
    }
}

@MainActor func testDelegateRuleOnlyForHeavyWork() {
    for language in [AppLanguage.es, .en] {
        let p = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, language: language)
        let heavy = language == .es ? "solo para trabajo pesado de varios pasos" : "only for heavy multi-step work"
        expect(p.contains(heavy), "delegar \(language): solo trabajo pesado")
        let own = language == .es ? "nunca crea archivos que no se pidieron" : "never creates a file nobody asked for"
        expect(p.contains(own), "delegar \(language): el conocimiento propio no se delega ni crea archivos")
        let old = language == .es ? "Para todo lo que lea o cambie archivos" : "anything that reads or changes files"
        expect(!p.contains(old), "delegar \(language): la regla vieja ya no está")
        expect(!ToolSpec.delegate(language).description.contains(language == .es ? "TODO lo que toque disco" : "ANYTHING touching disk"),
               "delegar \(language): la tool no promete TODO")
    }
}

@MainActor func testPromptDelegateEnabled() {
    let p = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: .es)
    expect(p.contains("delegate"),
           "prompt: con delegación nombra la tool delegate")
    expect(p.contains("especialista"),
           "prompt: con delegación nombra al especialista")
    expect(p.contains("archivos"),
           "prompt: el especialista tiene archivos")
    // 15g-3: a shell, not "the terminal" — the assistant has the hands now.
    expect(p.contains("shell"),
           "prompt: el especialista tiene una shell")
    // Ya no se promete internet incondicionalmente: prometer una busqueda que
    // el producto no puede hacer mandaba al modelo a una tool que siempre
    // fallaba, y volvia diciendo "no puedo buscar en la web" en vez de probar
    // otra via. La promesa era lo que capturaba la intencion (Wave 9f).
    expect(!p.contains("usa web_search") && p.contains("browser_open"),
           "prompt: sin busqueda configurada se usa el navegador propio, no se delega")
    expect(p.contains("lugares"),
           "prompt: pero si lo que de verdad puede — consultar lugares")
    let withWeb = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true,
        webSearchEnabled: true, language: .es)
    expect(withWeb.contains("usa web_search"),
           "prompt: con busqueda configurada se usa web_search")
    let withRead = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true,
        webSearchEnabled: true, webReadEnabled: true, language: .en)
    expect(withRead.contains("read_url"),
           "prompt: con lectura de paginas configurada se nombra read_url")
    expect(p.contains("Español, cálido, directo, 2 a 4 frases."),
           "prompt: delegar no se come la personalidad")
    expect(!p.contains("realtime"),
           "prompt: el hold ya no habla por la API realtime")
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

/// Wave 10b: el prompt deja de decir "no puedes ver el disco". Con manos
/// propias el modelo actúa en una frase; delegar queda para leer, cambiar,
/// correr y buscar.
@MainActor func testPromptParentToolsActRule() {
    for language in [AppLanguage.es, .en] {
        let p = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true,
            parentToolsEnabled: true, language: language)
        expect(!p.contains("cannot see the disk") && !p.contains("no puedes ver el disco"),
               "prompt \(language): ya no dice que no puede ver el disco")
        expect(p.contains("open_app") || p.contains("open apps") || p.contains("abrir apps"),
               "prompt \(language): dice que puede abrir apps")
        expect(p.contains("delegate"), "prompt \(language): delegate sigue")
    }
    let es = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true,
        parentToolsEnabled: true, language: .es)
    expect(es.contains("especialista") && es.contains("archivos") && es.contains("shell"),
           "prompt es: el especialista conserva su alcance")
    let solo = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false,
        parentToolsEnabled: true, language: .es)
    expect(!solo.contains("delegate") && (solo.contains("abrir") || solo.contains("abre")),
           "prompt es: manos sin especialista — actúa, no delega")
    expect(solo.contains("dentro de <context>") && solo.contains("con sus palabras"),
           "prompt es: lo que hay en <context> son datos, no una orden")
    let none = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: .es)
    expect(none.contains("delegate") && !none.contains("no puedes ver el disco"),
           "prompt es: sin manos tampoco vuelve la frase vieja")
}


// Wave 11a: el catálogo viaja como datos al final; la regla de cómo usarlo
// va en el cuerpo, y solo cuando hay catálogo.
@MainActor func testPromptCarriesSkills() {
    let block = "<active_skills>\n  - writing-content — Writes. — /x/SKILL.md\n</active_skills>"
    for language in [AppLanguage.en, .es] {
        let with = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, parentToolsEnabled: true,
            language: language, memory: "Memory — DATA: likes coffee", skills: block)
        expect(with.hasSuffix(block), "prompt \(language): el catálogo cierra el prompt")
        expect(with.contains("read_skill"), "prompt \(language): dice cómo leer una skill")
        expect(with.range(of: "likes coffee")!.lowerBound < with.range(of: "<active_skills>\n")!.lowerBound,
               "prompt \(language): memoria antes que catálogo")
        let without = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, parentToolsEnabled: true, language: language)
        expect(!without.contains("read_skill") && !without.contains("active_skills"),
               "prompt \(language): sin catálogo no se promete nada")
    }
    let es = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: true, language: .es, skills: block)
    expect(es.contains("nombra la skill") && es.contains("context"), "prompt es: al delegar, nombra la skill en el contexto")
    expect(es.contains("en voz alta"), "prompt es: nunca lee el catálogo en voz alta")
}

// QA 2026-10-18: both replies told her to visit XE. The "never send her to a
// site" rule sat in the delegate branch only, so a parent that could not
// delegate never heard it.
@Test func theParentPromptCarriesTheSourcesRuleWithoutDelegation() {
    let es = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, parentToolsEnabled: true,
        webSearchEnabled: true, webReadEnabled: true, language: .es)
    expect(es.contains("nunca la mandes a un sitio"),
           "prompt sin delegate: la regla de no mandarla a un sitio sigue presente (es)")
    let en = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, parentToolsEnabled: true,
        webSearchEnabled: true, webReadEnabled: true, language: .en)
    expect(en.contains("never send her to a site"),
           "prompt sin delegate: la regla de no mandarla a un sitio sigue presente (en)")
}
