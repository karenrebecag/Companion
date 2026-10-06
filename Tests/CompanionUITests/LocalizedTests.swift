import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// El catálogo de la UI. Media app en cada idioma es peor que una monolingüe:
// una clave sin traducir es un fallo de la suite, no un aviso.

@Test @MainActor func localizedTests() async {
    testBothCatalogsCoverTheSameKeys()
    testFormatSpecifiersMatchAcrossCatalogs()
    await testLookupFollowsTheChosenLanguage()
    await testCopyLayerGoesThroughTheCatalog()
    testKeyMissingOnlyInSpanishFallsBackToEnglish()
    testBlankTranslationFallsBackToEnglish()
    testTranslationEqualToItsKeyIsNotMissing()
    testMissingLprojDegradesToEnglishThenKey()
    testFormatSpecifierExtraction()
}

@MainActor func testBothCatalogsCoverTheSameKeys() {
    let english = catalogKeys("en")
    let spanish = catalogKeys("es")
    expect(!english.isEmpty, "catálogo: la fuente inglesa existe y no va vacía")
    expectEq(english.subtracting(spanish), [],
             "catálogo: no hay clave inglesa sin español")
    expectEq(spanish.subtracting(english), [],
             "catálogo: no hay español huérfano de una clave fuente")
}

/// Los códigos del catálogo, en su orden: el picker, la instrucción de voz y
/// las claves `spoken.language.*` salen de esta lista, así que un cambio en
/// ella tiene que ser una decisión y no un efecto secundario.
@Test func spokenLanguageCatalogIsPinned() {
    expectEq(SpokenLanguagePreference.catalog.map(\.code), [
        "en", "es", "fr", "de", "it", "pt", "nl", "sv", "no", "da",
        "fi", "pl", "ru", "uk", "tr", "ar", "he", "ja", "ko", "zh",
        "hi", "id", "th", "vi", "cs", "el", "hu", "ro", "bg", "is",
    ], "idiomas: los códigos del catálogo y su orden")
}

@Test func everySpokenLanguageIsNamedInBothCatalogsAndNothingElseIs() {
    let codes = Set(SpokenLanguagePreference.catalog.map(\.code))
    for language in ["en", "es"] {
        let strings = catalog(language)
        for code in SpokenLanguagePreference.catalog.map(\.code) {
            let name = strings["spoken.language.\(code)"] ?? ""
            expect(!name.isEmpty, "idiomas \(language): spoken.language.\(code) tiene nombre")
        }
        let named = Set(strings.keys.filter { $0.hasPrefix("spoken.language.") }
            .map { String($0.dropFirst("spoken.language.".count)) })
        expectEq(named.subtracting(codes), [],
                 "idiomas \(language): ningún spoken.language.* fuera del catálogo")
    }
}

@MainActor func testLookupFollowsTheChosenLanguage() async {
    let english = await Localized.scoped(to: .en) { Localized.string("chat.job.done") }
    let spanish = await Localized.scoped(to: .es) { Localized.string("chat.job.done") }

    expect(!english.isEmpty && !spanish.isEmpty,
           "lookup: ninguna de las dos queda vacía")
    expect(english != spanish, "lookup: cada idioma dice lo suyo")
    expect(!english.contains("chat.job.done"),
           "lookup: nunca se pinta la clave cruda en pantalla")
}

/// La capa de copy sigue siendo la API; lo que cambia es de dónde saca el
/// texto. Si un Copy devolviera la clave, el catálogo estaría desconectado.
@MainActor func testCopyLayerGoesThroughTheCatalog() async {
    let englishDone = await Localized.scoped(to: .en) { () -> String in
        expect(!ChatCopy.jobDone.contains("."),
               "copy: ChatCopy.jobDone es texto, no una clave")
        expect(!VoiceCopy.failure(.micDenied).contains("voice."),
               "copy: VoiceCopy también pasa por el catálogo")
        return ChatCopy.jobDone
    }
    await Localized.scoped(to: .es) {
        expect(ChatCopy.jobDone != englishDone,
               "copy: cambiar el idioma cambia lo que se pinta")
    }
}

/// Builds a resources bundle from per-language `.strings` bodies; an empty
/// dictionary yields a bundle with no lproj at all.
private func makeFixtureBundle(_ files: [String: String]? = nil) throws -> (root: URL, bundle: Bundle?) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("localized-fixture-\(UUID().uuidString)")
    let dir = root.appendingPathComponent("Fixture.bundle")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let bodies = files ?? [
        "en": #""shared.key" = "Shared EN"; "only.en" = "English value";"#,
        "es": #""shared.key" = "Shared ES";"#,
    ]
    for (language, body) in bodies {
        let lproj = dir.appendingPathComponent("\(language).lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: lproj.appendingPathComponent("Localizable.strings"))
    }
    return (root, Bundle(url: dir))
}

/// Runs `body` against a temp bundle and always cleans it up.
private func withFixture(_ files: [String: String]? = nil, _ body: (Bundle?) -> Void) {
    guard let fixture = try? makeFixtureBundle(files) else {
        expect(false, "fixture: no se pudo armar el bundle temporal")
        return
    }
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    body(fixture.bundle)
}

@MainActor func testKeyMissingOnlyInSpanishFallsBackToEnglish() {
    guard let fixture = try? makeFixtureBundle() else {
        expect(false, "fallback: no se pudo armar el bundle temporal")
        return
    }
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    expectEq(Localized.string("only.en", language: .es, in: fixture.bundle), "English value",
             "fallback: clave ausente solo en es cae al ingles, no a la clave cruda")
    expectEq(Localized.string("shared.key", language: .es, in: fixture.bundle), "Shared ES",
             "fallback: una clave presente en es sigue diciendo espanol")
    expectEq(Localized.string("nowhere", language: .es, in: fixture.bundle), "nowhere",
             "fallback: ausente en ambos idiomas = clave cruda")
}

@MainActor func testBlankTranslationFallsBackToEnglish() {
    withFixture(["en": #""x" = "EN";"#, "es": #""x" = "";"#]) { bundle in
        expectEq(Localized.string("x", language: .es, in: bundle), "EN",
                 "blank: una traduccion vacia cae al ingles")
    }
    withFixture(["en": #""x" = "";"#, "es": #""x" = "";"#]) { bundle in
        expectEq(Localized.string("x", language: .es, in: bundle), "x",
                 "blank: vacio en ambos idiomas = clave cruda, nunca en blanco")
    }
}

@MainActor func testTranslationEqualToItsKeyIsNotMissing() {
    withFixture(["en": #""OK" = "Okay";"#, "es": #""OK" = "OK";"#]) { bundle in
        expectEq(Localized.string("OK", language: .es, in: bundle), "OK",
                 "key==value: una traduccion real igual a la clave se respeta")
        expectEq(Localized.string("OK", language: .en, in: bundle), "Okay",
                 "key==value: el otro idioma sigue diciendo lo suyo")
    }
}

@MainActor func testMissingLprojDegradesToEnglishThenKey() {
    withFixture(["en": #""k" = "English value";"#]) { bundle in
        expectEq(Localized.string("k", language: .es, in: bundle), "English value",
                 "lproj: sin es.lproj cae al ingles")
    }
    withFixture([:]) { bundle in
        expectEq(Localized.string("k", language: .es, in: bundle), "k",
                 "lproj: sin ningun lproj = clave cruda")
    }
    expectEq(Localized.string("k", language: .es, in: nil), "k",
             "lproj: sin bundle = clave cruda")
}

@MainActor func testFormatSpecifierExtraction() {
    expectEq(formatSpecifiers("%%"), [], "fmt: %% no es especificador")
    expectEq(formatSpecifiers("100%% done"), [], "fmt: 100%% done sin especificadores")
    expectEq(formatSpecifiers("%lld"), ["%lld"], "fmt: %lld")
    expectEq(formatSpecifiers("%.1f"), ["%.1f"], "fmt: %.1f")
    expectEq(formatSpecifiers("%1$@ %2$@"), formatSpecifiers("%2$@ %1$@"),
             "fmt: orden posicional distinto compara igual")
    expectEq(formatSpecifiers("%1$@ %2$d"), ["%@", "%d"], "fmt: posicional se normaliza por indice")
    expectEq(formatSpecifiers("%2$@ %1$d"), ["%d", "%@"], "fmt: indice manda sobre la posicion en el texto")
    expectEq(formatSpecifiers("%10$@ %2$d"), ["%d", "%@"], "fmt: orden numerico, no lexicografico")
    expectEq(formatSpecifiers("%@ %@"), formatSpecifiers("%1$@ %2$@"),
             "fmt: plano y posicional con mismos tipos comparan igual")
    expect(formatSpecifiers("%@ and %@") != formatSpecifiers("%@"),
           "fmt: es perdiendo un %@ falla")
}

private func catalog(_ language: String) -> [String: String] {
    guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
          let dict = NSDictionary(contentsOfFile: path + "/Localizable.strings") as? [String: String]
    else { return [:] }
    return dict
}

private func catalogKeys(_ language: String) -> Set<String> {
    Set(catalog(language).keys)
}

/// Specifiers per argument slot: `%%` is a literal, and positional ones are
/// ordered by index so a translation may reorder them.
private func formatSpecifiers(_ value: String) -> [String] {
    let pattern = #"%(?:(\d+)\$)?([-+0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDiuUxXfFeEgGcCsSp])"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let ns = value.replacingOccurrences(of: "%%", with: "") as NSString
    var plainIndex = 0
    let slots: [(Int, String)] = regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
        .map { match in
            let spec = "%" + ns.substring(with: match.range(at: 2))
            if match.range(at: 1).location != NSNotFound,
               let index = Int(ns.substring(with: match.range(at: 1))) {
                return (index, spec)
            }
            plainIndex += 1
            return (plainIndex, spec)
        }
    return slots.sorted { $0.0 < $1.0 }.map(\.1)
}

@MainActor func testFormatSpecifiersMatchAcrossCatalogs() {
    let english = catalog("en")
    let spanish = catalog("es")
    expect(!english.isEmpty && !spanish.isEmpty, "catalogo: ambos catalogos se leyeron")
    let mismatched = english.keys.sorted().filter { key in
        guard let es = spanish[key], let en = english[key] else { return false }
        return formatSpecifiers(en) != formatSpecifiers(es)
    }
    expectEq(mismatched, [], "catalogo: mismos especificadores de formato en en y es")
}
