import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Wave 16g (spec 16g): Settings as a sheet with a sidebar and a search, the
// vocabulary as a list, and a Memory page that reads and forgets entries.

@Test @MainActor func settingsPagesTests() async throws {
    await testTheSidebarHasSevenPages()
    testEveryOptionHasAPage()
    testSearchIgnoresCaseAndAccents()
    testSearchRanksTitlesFirst()
    await testSearchFindsEveryOptionInBothLanguages()
    testVocabularyAddsAndRemovesOneWord()
    try testMemoryListsNotesAndSessionsNewestFirst()
    try testForgettingMovesOnlyThatEntry()
    try testForgettingRefusesAnythingOutsideMemory()
    testAMemoryReadsAsWhatHappened()
    try testASymlinkInMemoryIsNeverRead()
    try testALinkedMemoryFolderIsNeverRead()
    testTwoUntitledDropdownsOnOnePageAreDifferentMenus()
}

@MainActor func testTheSidebarHasSevenPages() async {
    // S2 of ajustes-hoja-incredible moved the map to Incredible's; SettingsMapTests pins names and order.
    expectEq(SettingsTab.allCases.count, 7, "ajustes: las siete páginas")
    expect(SettingsSheetMetrics.maxWidth > SettingsOverlayMetrics.maxSide, "ajustes: la hoja es mas ancha que el historial")
}

@MainActor func testEveryOptionHasAPage() {
    let pages = Dictionary(grouping: SettingsInventory.options, by: \.tab)
    for page in [SettingsTab.general, .voice, .vocabulary, .system, .you, .privacy] {
        expect(!(pages[page] ?? []).isEmpty, "ajustes: \(page) tiene opciones")
    }
    expect(pages[.memory] == nil, "ajustes: memoria es un panel, no opciones")
    let panelPages = Set(SettingsInventory.panels.map(\.tab))
    expect(panelPages.isSuperset(of: [.memory, .system, .privacy, .you]), "ajustes: cada panel dice su página")
    expectEq(SettingsInventory.options.first { $0.titleKey == "settings.vocabulary" }?.tab, .vocabulary,
             "ajustes: el vocabulario tiene su página")
}

func testSearchIgnoresCaseAndAccents() {
    let entries = [
        SettingsSearch.Entry(id: "a", page: "general", title: "Idioma", subtitle: "En qué te habla"),
        SettingsSearch.Entry(id: "b", page: "you", title: "Tamaño del texto", subtitle: "Más grande o más chico"),
    ]
    expectEq(SettingsSearch.match("tamano", in: entries).map(\.id), ["b"], "buscar: sin acentos")
    expectEq(SettingsSearch.match("IDIOMA", in: entries).map(\.id), ["a"], "buscar: sin mayúsculas")
    expectEq(SettingsSearch.match("texto grande", in: entries).map(\.id), ["b"],
             "buscar: varias palabras, en título o subtítulo")
    expect(SettingsSearch.match("   ", in: entries).isEmpty, "buscar: vacío no lista todo")
    expect(SettingsSearch.match("zzz", in: entries).isEmpty, "buscar: sin resultados")
}

func testSearchRanksTitlesFirst() {
    let entries = [
        SettingsSearch.Entry(id: "sub", page: "x", title: "Sonidos", subtitle: "Un tono al empezar a hablar"),
        SettingsSearch.Entry(id: "title", page: "x", title: "Hablar", subtitle: "Mantén fn"),
    ]
    expectEq(SettingsSearch.match("hablar", in: entries).map(\.id), ["title", "sub"],
             "buscar: el título pesa más que el subtítulo")
}

@MainActor func testSearchFindsEveryOptionInBothLanguages() async {
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            let entries = SettingsInventory.searchEntries
            for option in SettingsInventory.options {
                let title = Localized.string(option.titleKey)
                let found = SettingsSearch.match(title, in: entries)
                expect(found.contains { $0.id == option.titleKey && $0.page == option.tab.rawValue },
                       "\(language): «\(title)» se encuentra y salta a \(option.tab)")
            }
        }
    }
}

@MainActor func testVocabularyAddsAndRemovesOneWord() {
    expectEq(Vocabulary.parse(Vocabulary.adding("Zócalo", to: "Atom, Pigmento")),
             ["Atom", "Pigmento", "Zócalo"], "vocabulario: añadir va al final")
    expectEq(Vocabulary.adding("atom", to: "Atom"), Vocabulary.adding("", to: "Atom"),
             "vocabulario: una repetida no entra")
    expectEq(Vocabulary.parse(Vocabulary.adding(String(repeating: "x", count: 41), to: "Atom")), ["Atom"],
             "vocabulario: una frase no entra")
    let full = (1...Vocabulary.maxWords).map { "p\($0)" }.joined(separator: ",")
    expectEq(Vocabulary.parse(Vocabulary.adding("otra", to: full)).count, Vocabulary.maxWords,
             "vocabulario: con tope")
    expectEq(Vocabulary.parse(Vocabulary.removing("pigmento", from: "Atom, Pigmento, Zócalo")),
             ["Atom", "Zócalo"], "vocabulario: quitar sin importar mayúsculas")
}

private func memoryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("memory-browse-\(UUID().uuidString)", isDirectory: true)
    for sub in ["notes", "sessions"] {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    try "Karen\n".write(to: root.appendingPathComponent("core.md"), atomically: true, encoding: .utf8)
    try "prefiere respuestas cortas".write(
        to: root.appendingPathComponent("notes/2026-09-01-100000.md"), atomically: true, encoding: .utf8)
    try "## ayer\n- pidió un cuento".write(
        to: root.appendingPathComponent("sessions/2026-09-20-090000.md"), atomically: true, encoding: .utf8)
    try "## hoy\n- ordenó Descargas".write(
        to: root.appendingPathComponent("sessions/2026-09-24-090000.md"), atomically: true, encoding: .utf8)
    return root
}

func testMemoryListsNotesAndSessionsNewestFirst() throws {
    let root = try memoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let entries = FileMemoryStore(root: root).entries()
    expectEq(entries.map(\.id),
             ["sessions/2026-09-24-090000.md", "sessions/2026-09-20-090000.md", "notes/2026-09-01-100000.md"],
             "memoria: lo más nuevo arriba, sin el core")
    expectEq(entries.first?.kind, .session, "memoria: dice qué es cada una")
    expectEq(entries.last?.text, "prefiere respuestas cortas", "memoria: el texto tal cual")
    expectEq(entries.first?.day, "2026-09-24", "memoria: el día sale del nombre")
}

func testForgettingMovesOnlyThatEntry() throws {
    let root = try memoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileMemoryStore(root: root)
    try store.forget("notes/2026-09-01-100000.md")
    expectEq(store.entries().map(\.id), ["sessions/2026-09-24-090000.md", "sessions/2026-09-20-090000.md"],
             "memoria: olvidar quita solo esa")
    expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("core.md").path),
           "memoria: el core no se toca")
}

func testForgettingRefusesAnythingOutsideMemory() throws {
    let root = try memoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileMemoryStore(root: root)
    for id in ["core.md", "../core.md", "notes/../core.md", "notes/../../etc/hosts", "/etc/hosts",
               "notes/missing.md", "notes/", "other/x.md"] {
        var refused = false
        do { try store.forget(id) } catch { refused = true }
        expect(refused, "memoria: «\(id)» no se olvida")
    }
    expectEq(store.entries().count, 3, "memoria: nada se movió")
}

@MainActor func testAMemoryReadsAsWhatHappened() {
    let session = MemoryEntry(id: "sessions/a.md", kind: .session, day: "2026-09-24",
                              text: "## 2026-09-24\n- ordenó Descargas\n- pidió un cuento")
    expectEq(MemoryCopy.headline(session), "ordenó Descargas", "memoria: lo que pasó, no el encabezado")
    let heading = MemoryEntry(id: "notes/b.md", kind: .note, day: "", text: "# Solo un título")
    expectEq(MemoryCopy.headline(heading), "Solo un título", "memoria: sin más, el encabezado sirve")
}

/// Security review 16g: a link dropped in notes/ would carry any file the
/// user can read into the Settings page and into the prompt.
func testASymlinkInMemoryIsNeverRead() throws {
    let root = try memoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let secret = root.deletingLastPathComponent().appendingPathComponent("secret-\(UUID().uuidString).txt")
    try "SENTINEL-SECRET".write(to: secret, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: secret) }
    for folder in ["notes", "sessions"] {
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("\(folder)/2026-09-30-000000.md"), withDestinationURL: secret)
    }
    let store = FileMemoryStore(root: root)
    expect(!store.entries().contains { $0.text.contains("SENTINEL") }, "memoria: un enlace no se lista")
    let pack = store.load()
    expect(!(pack.notes + pack.recentSessions).contains { $0.contains("SENTINEL") },
           "memoria: un enlace no viaja al prompt")
}

/// Security re-review 16g: the same leak one level up, with the folder
/// itself replaced by a link to somewhere else.
func testALinkedMemoryFolderIsNeverRead() throws {
    let root = try memoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let elsewhere = root.deletingLastPathComponent().appendingPathComponent("elsewhere-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: elsewhere) }
    try "SENTINEL-FOLDER".write(
        to: elsewhere.appendingPathComponent("2026-09-30-000000.md"), atomically: true, encoding: .utf8)
    for folder in ["notes", "sessions"] {
        try FileManager.default.removeItem(at: root.appendingPathComponent(folder))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(folder), withDestinationURL: elsewhere)
    }
    let store = FileMemoryStore(root: root)
    expect(store.entries().isEmpty, "memoria: una carpeta enlazada no se lista")
    let pack = store.load()
    expect((pack.notes + pack.recentSessions).isEmpty, "memoria: una carpeta enlazada no viaja al prompt")
}

/// Code review 16g: rows carry the title, so the pickers inside them are
/// untitled; keyed by title, two of them opened under the same anchor.
@MainActor func testTwoUntitledDropdownsOnOnePageAreDifferentMenus() {
    let dictation = SettingsItem<Int>(title: "", value: "", options: [], id: "settings.app.talk.dictationKey") { _ in }
    let language = SettingsItem<Int>(title: "", value: "", options: [], id: "settings.app.language") { _ in }
    expect(dictation.menu != language.menu, "ajustes: cada desplegable abre bajo su fila")
    let titled = SettingsItem<Int>(title: "Voz", value: "", options: []) { _ in }
    expect(titled.menu == .settingsPick("Voz"), "ajustes: sin id, el título sigue siendo la llave")
}
