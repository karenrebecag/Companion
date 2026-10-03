import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 11a. El store siembra las skills del sistema desde el bundle, escanea
// las tres carpetas y sirve cuerpos por nombre. Nada de esto toca la carpeta
// real de la usuaria: cada test vive en su propio directorio temporal.
@Test @MainActor func skillStoreTests() {
    testSeedWritesOnceAndFollowsTheBundle()
    testScanSkipsInvalidAndPrefersSystem()
    testBundledSkillsShipTwelve()
}

private func sandbox() -> SkillsLocation {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-store-\(UUID().uuidString)")
    return SkillsLocation(root: base.appendingPathComponent("Companion"))
}

private func skill(_ name: String, _ description: String = "Does it. Use when asked.") -> String {
    "---\nname: \(name)\ndescription: \(description)\n---\n# \(name)\n"
}

@MainActor func testSeedWritesOnceAndFollowsTheBundle() {
    let loc = sandbox()
    defer { try? FileManager.default.removeItem(at: loc.root) }
    let bundled = [BundledSkill(name: "a", content: skill("a")), BundledSkill(name: "b", content: skill("b"))]
    let store = SkillStore(location: loc, bundled: bundled)
    expectEq(store.seed().sorted(), ["a", "b"], "seed: la primera vez escribe todas")
    expect(FileManager.default.fileExists(atPath: loc.systemSkills.appendingPathComponent("a/SKILL.md").path),
           "seed: default/<name>/SKILL.md")
    expectEq(store.seed(), [], "seed: la segunda vez no toca nada")
    let edited = loc.systemSkills.appendingPathComponent("a/SKILL.md")
    try! skill("a", "Edited by hand.").write(to: edited, atomically: true, encoding: .utf8)
    expectEq(store.seed(), ["a"], "seed: lo editado a mano vuelve al bundle — default es del sistema")
    let changed = SkillStore(location: loc, bundled: [
        BundledSkill(name: "a", content: skill("a")),
        BundledSkill(name: "b", content: skill("b", "New wording.")),
    ])
    expectEq(changed.seed(), ["b"], "seed: un bundle nuevo reescribe solo la que cambió")
    expect(try! String(contentsOf: loc.systemSkills.appendingPathComponent("b/SKILL.md"), encoding: .utf8)
        .contains("New wording."), "seed: el contenido nuevo está en disco")
    expect(store.body(named: "a")?.contains("# a") == true, "body: por nombre")
    expect(store.body(named: "zzz") == nil, "body: desconocida → nil")
    expect(store.body(named: "../a") == nil, "body: una ruta no es un nombre")
}

@MainActor func testScanSkipsInvalidAndPrefersSystem() {
    let loc = sandbox()
    defer { try? FileManager.default.removeItem(at: loc.root) }
    let store = SkillStore(location: loc, bundled: [BundledSkill(name: "shared", content: skill("shared"))])
    _ = store.seed()
    func write(_ url: URL, _ text: String) {
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! text.write(to: url, atomically: true, encoding: .utf8)
    }
    write(loc.customSkills.appendingPathComponent("weekly/SKILL.md"), skill("weekly", "Weekly report. Use on Fridays."))
    write(loc.customSkills.appendingPathComponent("broken/SKILL.md"), skill("not-broken"))
    write(loc.customSkills.appendingPathComponent("shared/SKILL.md"), skill("shared", "Custom copy."))
    write(loc.customSkills.appendingPathComponent("loose/README.md"), "no skill here")
    write(loc.knowledge.appendingPathComponent("dentist/KNOWLEDGE.md"),
          "---\nname: dentist\ndescription: The user's dentist.\n---\nDra. López")
    // Security review 2026-09-06: un archivo enorme se releería entero en
    // cada turno. Se salta por tamaño antes de leerlo.
    let huge = skill("huge", "Too big to be a skill.") + String(repeating: "x", count: SkillCatalog.Caps.fileBytes + 1)
    write(loc.customSkills.appendingPathComponent("huge/SKILL.md"), huge)
    let cards = store.scan()
    let names = cards.map(\.name)
    expect(!names.contains("huge") && store.body(named: "huge") == nil, "scan: sobre el tope de bytes no entra")
    expect(names.contains("weekly"), "scan: custom válida entra")
    expect(!names.contains("not-broken") && !names.contains("broken"), "scan: la inválida se salta")
    expect(!names.contains("loose"), "scan: sin SKILL.md no es skill")
    expectEq(cards.filter { $0.name == "shared" }.count, 1, "scan: la colisión no duplica")
    expect(cards.first { $0.name == "shared" }?.origin == .system, "scan: en colisión gana default")
    let dentist = cards.first { $0.name == "dentist" }
    expect(dentist?.kind == .knowledge && dentist?.path.hasSuffix("knowledge/dentist/KNOWLEDGE.md") == true,
           "scan: knowledge con su ruta")
    expect(store.body(named: "dentist")?.contains("Dra. López") == true, "body: knowledge también")
    let rendered = store.rendered(language: .en)
    expect(rendered.contains("<active_skills>") && rendered.contains("<active_knowledge>"),
           "rendered: el bloque listo para el prompt")
    let empty = SkillStore(location: sandbox(), bundled: [])
    expectEq(empty.scan(), [], "scan: carpetas ausentes = catálogo vacío, sin error")
    expectEq(empty.rendered(language: .es), "", "rendered: vacío, sin bloque")
}

/// Las doce del sistema (§3.4): texto nuestro, formato Agent Skills, tercera
/// persona, cortas. Este test es la conformidad del bundle: si una se rompe
/// al editarla, se sabe aquí y no en el prompt.
@MainActor func testBundledSkillsShipTwelve() {
    let bundled: [BundledSkill]
    do { bundled = try BundledSkills.load() } catch {
        expect(false, "bundle: no carga (\(error))"); return
    }
    let expected: Set<String> = [
        "writing-content", "knowledge-builder", "skill-builder", "about-companion",
        "meeting-transcripts", "scheduling", "browser-use", "excel-live", "premium-documents",
        "files-and-shell", "web-research", "handing-off-work",
    ]
    expectEq(Set(bundled.map(\.name)), expected, "bundle: las doce, ni una más")
    for item in bundled {
        do {
            let fm = try SkillFrontmatter.parse(item.content, folder: item.name)
            expect(!fm.description.hasPrefix("I ") && !fm.description.hasPrefix("You "),
                   "bundle \(item.name): descripción en tercera persona")
            expect(fm.description.contains("Use when") || fm.description.contains("Use for")
                   || fm.description.contains("Use it"), "bundle \(item.name): dice cuándo usarla")
            expect(fm.description.unicodeScalars.count <= SkillCatalog.Caps.description,
                   "bundle \(item.name): la descripción cabe entera en el catálogo")
            expect(fm.body.split(separator: "\n").count < 500, "bundle \(item.name): < 500 líneas")
            expect(!fm.body.contains("\\scripts") && !fm.body.contains("\\references"),
                   "bundle \(item.name): rutas con barra normal")
            expect(!fm.body.lowercased().contains("incredible"), "bundle \(item.name): texto nuestro")
            expect(fm.body.contains("## "), "bundle \(item.name): tiene secciones")
        } catch {
            expect(false, "bundle \(item.name): \(error.why)")
        }
    }
    for honest in ["scheduling", "browser-use", "excel-live", "premium-documents"] {
        let body = bundled.first { $0.name == honest }?.content ?? ""
        expect(body.contains("## What Companion cannot do yet"),
               "bundle \(honest): dice lo que aún no puede — que el modelo no invente")
    }
    // The model reads the code from the skill and the runner answers with the
    // constant: if the two drift, the model is told about a code it never sees.
    let excel = bundled.first { $0.name == "excel-live" }?.content ?? ""
    expect(excel.contains("`\(BridgeCode.permissionRequired)`"), "excel-live: nombra el código que la hoja devuelve")
    expect(excel.contains("Privacy & Security > Automation"), "excel-live: y el panel")
    expect(!excel.contains("needs_permission"), "excel-live: sin el código viejo")
}
