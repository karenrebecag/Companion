import CompanionCore
import Foundation
import Testing

// DM1a. N0 offers only what it can run, and never a string the user did not say.

@Test func dm1AppCandidatesRankTheNamedApp() {
    let apps = [
        "Safari", "Chrome", "Notes", "Slack", "Finder", "Mail", "Calendar",
        "Music", "Terminal", "Cursor", "Xcode", "System Settings", "Messages",
    ]
    let pairs = [
        ("abre safari, puedes?", "Safari"),
        ("ábreme el Safari", "Safari"),
        ("abre el chrome", "Chrome"),
        ("open notes app", "Notes"),
        ("switch to slack", "Slack"),
        ("open mail", "Mail"),
        ("launch calendar app", "Calendar"),
        ("open system settings", "System Settings"),
        ("launch cursor", "Cursor"),
    ]
    for (said, want) in pairs {
        let found = CandidateSets.appCandidates(said, apps: apps).map(\.id)
        expect(found.contains(want), "\(said) ofrece \(found)")
    }
    expect(CandidateSets.appCandidates("abre las fotos", apps: ["Photos", "Safari"]).isEmpty,
           "fotos no es Photos")
    let normalized = CandidateSets.appCandidates("abre Safari", apps: ["Safari.app", "Nope/Safari"])
    expectEq(normalized.map(\.id), ["Safari"], "el .app se normaliza y la barra no es una app")
}

@Test func dm1AppCandidatesCapAtFive() {
    let names = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
    let found = CandidateSets.appCandidates(
        "open alpha bravo charlie delta echo foxtrot", apps: names)
    expectEq(found.count, 5, "tope 5")
    expect(!found.contains { $0.id == "Foxtrot" }, "el sexto, por nombre, se cae")
}

@Test func dm1TextSpansAreCutsNotInventions() {
    let recoverable = [
        ("find restaurants near me", "restaurants near me"),
        ("where are hotels downtown", "hotels downtown"),
        ("busca cafes en el centro", "cafes en el centro"),
        ("halla museos cercanos", "museos cercanos"),
        ("find grocery stores", "grocery stores"),
        ("busca parques en la ciudad", "parques en la ciudad"),
        ("cines cerca de Reforma", "cines cerca de Reforma"),
        ("type hello world", "hello world"),
        ("escribe hola mundo", "hola mundo"),
        ("type buy milk and send", "buy milk"),
        ("escribe compra leche y envia", "compra leche"),
        ("type see you tomorrow", "see you tomorrow"),
        ("type thank you", "thank you"),
        ("escribe gracias", "gracias"),
        ("escribe lo llamado lista de compras", "lista de compras"),
    ]
    for (said, want) in recoverable {
        let spans = CandidateSets.textSpans(said).map(\.detail)
        expect(spans.contains(want), "\(said) no ofrece \(want) sino \(spans)")
        for span in spans {
            expect(CandidateSets.fold(said).contains(CandidateSets.fold(span)),
                   "span fuera de la frase: \(span)")
        }
    }
    let invented = CandidateSets.textSpans("escribe hasta manana").map(\.detail)
    expect(!invented.contains("gracias, nos vemos mañana"), "no inventa el texto")
}

@Test func dm1SitesFilesAndSkillsStayInsideWhatWasNamed() {
    let github = CandidateSets.siteCandidates("abre github en español", sites: CandidateSets.allowlist)
    expectEq(github.map(\.id), ["github"], "solo el host dicho")
    expectEq(github.first?.detail, "https://www.github.com", "url del allowlist")
    expect(CandidateSets.siteCandidates("what time is dinner", sites: CandidateSets.allowlist).isEmpty,
           "dinner no es un sitio")

    let files = [
        FileCandidate(path: "~/Documents/notas.txt"),
        FileCandidate(path: "~/Documents/presupuesto.pdf"),
    ]
    expectEq(
        CandidateSets.fileCandidates("abre el archivo de notas", files: files).map(\.id),
        ["~/Documents/notas.txt"], "notas matchea el nombre")
    expect(
        CandidateSets.fileCandidates("open my budget document", files: files).isEmpty,
        "budget no es presupuesto, y hay mas de un archivo")
    expectEq(
        CandidateSets.fileCandidates(
            "open my budget document", files: [FileCandidate(path: "~/Documents/presupuesto.pdf")]
        ).map(\.id),
        ["~/Documents/presupuesto.pdf"], "un solo archivo y la frase pide un documento")

    let skills = ["ai", "integration", "cloud", "search", "calendar", "code"]
    expect(
        CandidateSets.skillCandidates("abre la habilidad de busqueda", skills: skills).isEmpty,
        "busqueda no es search")
    expectEq(
        CandidateSets.skillCandidates("abre la habilidad de busqueda", skills: ["search"]).map(\.id),
        ["search"], "catalogo de una y la frase pide una habilidad")
    expectEq(
        CandidateSets.skillCandidates("lee la habilidad de integracion", skills: skills).map(\.id),
        ["integration"], "integracion alcanza integration")

    expect(CandidateSets.stronglyDirected("abre Safari", apps: ["Safari"], sites: []), "safari es una orden")
    expect(CandidateSets.stronglyDirected("abre google", apps: [], sites: CandidateSets.allowlist),
           "google es una orden")
    expect(!CandidateSets.stronglyDirected(
        "what time is dinner", apps: ["Safari"], sites: CandidateSets.allowlist),
           "la cena no nombra nada ejecutable")
}

@Test func dm1StronglyDirectedCatchesClosedSetCuesTooEvenOnNone() {
    let saidDirected = [
        "sube el volumen", "turn up the volume", "silencia todo", "mute the sound",
        "vacia la papelera", "empty the trash", "dale pausa", "pause the music",
        "reproduce la cancion", "play the song", "haz scroll", "desplaza hacia abajo",
        "toma una captura", "take a screenshot",
    ]
    for said in saidDirected {
        expect(CandidateSets.stronglyDirected(said, apps: [], sites: []),
               "\(said) nombra un conjunto cerrado, un none aqui es dudoso")
    }
    expect(!CandidateSets.stronglyDirected("what time is dinner", apps: [], sites: []),
           "la cena sigue sin nombrar nada ejecutable")
    expect(!CandidateSets.stronglyDirected("display the results", apps: [], sites: []),
           "display no es play por estar adentro de otra palabra")
}

@Test func dm1ClosedSetsMatchTheParentVocabulary() {
    expectEq(CandidateSets.volumeOps.map(\.id).sorted(), ["down", "max", "mute", "unmute", "up"], "volumen")
    expectEq(CandidateSets.scrollDirections.map(\.id).sorted(), ["bottom", "down", "top", "up"], "direccion")
    expectEq(CandidateSets.scrollAmounts.map(\.id).sorted(), ["line", "lots", "page"], "cantidad")
    expectEq(CandidateSets.mediaOps.map(\.id).sorted(), ["next", "pause", "play", "previous"], "media")
    expectEq(
        CandidateSets.systemOps.map(\.id).sorted(),
        ["empty_trash", "lock", "screenshot", "show_desktop", "sleep_display", "toggle_dark_mode"],
        "sistema")
    expect(CandidateSets.shortcuts.contains { $0.id == "quit_app" }, "quit es irreversible")
    expect(CandidateSets.shortcuts.contains { $0.id == "send_message" }, "enviar es irreversible")
    expectEq(CandidateSets.shortcuts.count, 21, "el conjunto cerrado del dataset")
}
