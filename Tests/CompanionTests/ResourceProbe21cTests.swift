import AppKit
import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// 21c S2: the packaging probe (COMPANION_RESOURCE_PROBE=1) and the QA gaps
// carried from S1. The smoke itself (scripts/package-smoke.sh) runs on the
// packaged .app; these pin the logic it relies on.

@Test @MainActor func resourceProbe21cTests() throws {
    testProbeRequestNeedsExactlyOne()
    testReportAllPassedPrintsTheMarkerAndExitsZero()
    testReportWithAFailureListsItAndExitsNonZeroBelowSignalRange()
    testReportWithNoChecksIsNotASuccess()
    testRunWritesEveryLineAndReturnsTheCode()
    try testBrowserExtensionCheck()
    testUIProbePassesOnTheBuildBundle()
    testUIProbeWithoutBundleFailsEveryClassWithoutTrap()
    try testServicesProbePassesOnTheBuildBundle()
    try testServicesProbeFailsWithoutBrowserExtension()
    testServicesProbeWithoutBundleFailsWithoutTrap()
    try testEmptyBundleDegradesAtEverySite()
    testFontsRegisterFromTheResolvedBundleResolvesAPostScriptName()
    try testLocalizedFallsBackToEnglishWhenOnlyEnExists()
    try testDanglingBuildSymlinkResolvesToNil()
    testOnlyALowercaseAppExtensionCountsAsAnApp()
    testFontsReadOnlyTheResolvedBundle()
}

// MARK: - Core report

private func check(_ name: String, _ passed: Bool) -> ResourceProbe.Check {
    ResourceProbe.Check(name: name, detail: "d", passed: passed)
}

@MainActor func testProbeRequestNeedsExactlyOne() {
    expect(ResourceProbe.isRequested(environment: ["COMPANION_RESOURCE_PROBE": "1"]),
           "21c probe: la variable en 1 lo activa")
    expect(!ResourceProbe.isRequested(environment: [:]), "21c probe: sin variable, arranque normal")
    expect(!ResourceProbe.isRequested(environment: ["COMPANION_RESOURCE_PROBE": "0"]),
           "21c probe: 0 no lo activa")
    expect(!ResourceProbe.isRequested(environment: ["COMPANION_RESOURCE_PROBE": ""]),
           "21c probe: vacia no lo activa")
}

@MainActor func testReportAllPassedPrintsTheMarkerAndExitsZero() {
    let report = ResourceProbe.report([check("a", true), check("b", true)])
    expectEq(report.exitCode, 0, "21c probe: todo verde sale con 0")
    expectEq(report.lines.last, ResourceProbe.marker, "21c probe: el marcador es la ultima linea")
    expectEq(report.lines.filter { $0 == ResourceProbe.marker }.count, 1, "21c probe: un solo marcador")
    expectEq(Array(report.lines.dropLast()), ["probe ok a=d", "probe ok b=d"],
             "21c probe: cada chequeo en su linea, nombre=detalle")
}

@MainActor func testReportWithAFailureListsItAndExitsNonZeroBelowSignalRange() {
    let report = ResourceProbe.report([check("a", true), check("font", false)])
    expect(!report.lines.contains(ResourceProbe.marker), "21c probe: con un fallo no hay marcador")
    expect(report.lines.contains("probe FAIL font=d"), "21c probe: el fallo se lista por nombre")
    expect(report.exitCode != 0, "21c probe: con un fallo el codigo no es 0")
    expect(report.exitCode > 0 && report.exitCode < 128,
           "21c probe: el codigo no se confunde con una salida por senal")
}

@MainActor func testReportWithNoChecksIsNotASuccess() {
    let report = ResourceProbe.report([])
    expect(report.exitCode != 0, "21c probe: cero chequeos nunca es verde")
    expect(!report.lines.contains(ResourceProbe.marker), "21c probe: cero chequeos, sin marcador")
}

@MainActor func testRunWritesEveryLineAndReturnsTheCode() {
    var written: [String] = []
    let code = ResourceProbe.run([check("a", false)]) { written.append($0) }
    expectEq(written, ResourceProbe.report([check("a", false)]).lines, "21c probe: run escribe el reporte")
    expectEq(code, ResourceProbe.failureExitCode, "21c probe: run devuelve el codigo del reporte")
}

@MainActor func testBrowserExtensionCheck() throws {
    let root = try probeTempRoot("ext")
    defer { removeProbeTemp(root) }
    let missing = ResourceProbe.browserExtension(resourceURL: root)
    expect(!missing.passed, "21c D9: sin carpeta BrowserExtension el probe falla")
    expectEq(missing.name, "browserExtension", "21c D9: el fallo nombra la extension")
    expect(!ResourceProbe.browserExtension(resourceURL: nil).passed, "21c D9: sin resourceURL falla")

    let folder = root.appendingPathComponent("BrowserExtension")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    expect(!ResourceProbe.browserExtension(resourceURL: root).passed,
           "21c D9: una carpeta vacia (sin manifest.json) no es la extension")
    try Data("{}".utf8).write(to: folder.appendingPathComponent("manifest.json"))
    let present = ResourceProbe.browserExtension(resourceURL: root)
    expect(present.passed, "21c D9: carpeta con manifest.json pasa")
    expectEq(present.detail, folder.path, "21c D9: el detalle es la ruta, para que el smoke la ubique")
}

// MARK: - Module probes

@MainActor func testUIProbePassesOnTheBuildBundle() {
    let checks = UIResourceProbe.checks()
    expectEq(checks.map(\.name), ["bundle.ui", "lproj.en", "lproj.es", "font", "mascot"],
             "21c probe UI: cubre bundle, en, es, fuente y mascota, en ese orden")
    expectEq(checks.filter { !$0.passed }.map(\.name), [],
             "21c probe UI: con el bundle de .build todo pasa")
    expectEq(checks.first?.detail, UIResourceBundle.bundle?.bundleURL.path,
             "21c probe UI: imprime el bundleURL resuelto")
}

@MainActor func testUIProbeWithoutBundleFailsEveryClassWithoutTrap() {
    let checks = UIResourceProbe.checks(bundle: nil)
    expectEq(checks.filter(\.passed).map(\.name), [], "21c probe UI: sin bundle, nada pasa (y no hay trap)")
}

@MainActor func testServicesProbePassesOnTheBuildBundle() throws {
    let resources = try fakeResourcesWithExtension()
    defer { removeProbeTemp(resources) }
    let checks = ServicesResourceProbe.checks(mainResourceURL: resources)
    expectEq(checks.map(\.name), ["bundle.services", "skills", "mermaid", "browserExtension"],
             "21c probe Services: bundle, skills, mermaid y extension")
    expectEq(checks.filter { !$0.passed }.map(\.name), [], "21c probe Services: con el bundle de .build todo pasa")
    let skills = checks.first { $0.name == "skills" }
    expectEq(skills?.detail, "\(sourceSkillCount())",
             "21c probe Services: cuenta las skills igual que Skills/*/SKILL.md del arbol")
}

@MainActor func testServicesProbeFailsWithoutBrowserExtension() throws {
    let resources = try probeTempRoot("no-ext")
    defer { removeProbeTemp(resources) }
    let failed = ServicesResourceProbe.checks(mainResourceURL: resources).filter { !$0.passed }.map(\.name)
    expectEq(failed, ["browserExtension"], "21c D9: sin BrowserExtension el probe falla, el resto pasa")
}

@MainActor func testServicesProbeWithoutBundleFailsWithoutTrap() {
    let failed = ServicesResourceProbe.checks(bundle: nil, mainResourceURL: nil).filter { !$0.passed }.map(\.name)
    expectEq(failed, ["bundle.services", "skills", "mermaid", "browserExtension"],
             "21c probe Services: sin bundle todo falla, sin trap")
}

// MARK: - Carried from S1 QA

/// MEDIUM: the bundle directory exists but holds nothing.
@MainActor func testEmptyBundleDegradesAtEverySite() throws {
    let root = try probeTempRoot("empty")
    defer { removeProbeTemp(root) }
    let dir = root.appendingPathComponent("Empty.bundle")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let empty = Bundle(url: dir)
    expect(empty != nil, "21c QA: un .bundle vacio existe como Bundle")
    expectEq(Localized.string("chat.job.done", language: .es, in: empty), "chat.job.done",
             "21c QA: bundle vacio = clave cruda")
    expect(ClaudeLogo.load(from: empty) == nil, "21c QA: bundle vacio = sin mascota")
    do {
        _ = try BundledSkills.load(from: empty)
        expect(false, "21c QA: bundle vacio debio lanzar")
    } catch let error as SkillStoreError {
        expectEq(error, .bundleMissing, "21c QA: bundle vacio = bundleMissing")
    }
    expect(WebKitDiagramRenderer.vendoredScript(from: empty) == nil, "21c QA: bundle vacio = sin mermaid")
}

/// MEDIUM: the production default registers fonts a view can then name.
@MainActor func testFontsRegisterFromTheResolvedBundleResolvesAPostScriptName() {
    Fonts.register(bundle: UIResourceBundle.bundle)
    expect(NSFont(name: UIResourceProbe.fontPostScriptName, size: 12) != nil,
           "21c QA: Fonts.register con el bundle resuelto deja \(UIResourceProbe.fontPostScriptName) disponible")
    let fonts = UIResourceBundle.bundle?.resourceURL?.appendingPathComponent("Fonts")
    expect(fonts.map { UIResourceProbe.registeredFontURL(UIResourceProbe.fontPostScriptName, under: $0) != nil } == true,
           "21c QA: la fuente registrada viene del bundle, no del sistema")
}

/// LOW: es missing entirely, en present.
@MainActor func testLocalizedFallsBackToEnglishWhenOnlyEnExists() throws {
    let root = try probeTempRoot("en-only")
    defer { removeProbeTemp(root) }
    let bundleDir = root.appendingPathComponent("EnOnly.bundle")
    let en = bundleDir.appendingPathComponent("en.lproj")
    try FileManager.default.createDirectory(at: en, withIntermediateDirectories: true)
    try Data(#""probe.key" = "English value";"#.utf8).write(to: en.appendingPathComponent("Localizable.strings"))
    expectEq(Localized.string("probe.key", language: .es, in: Bundle(url: bundleDir)), "English value",
             "21c QA: sin es.lproj, cae al ingles antes que a la clave cruda")
}

/// LOW: `.build/debug` is a symlink into a triple folder; after a clean it dangles.
@MainActor func testDanglingBuildSymlinkResolvesToNil() throws {
    let root = try probeTempRoot("dangling")
    defer { removeProbeTemp(root) }
    let dotBuild = root.appendingPathComponent(".build")
    try FileManager.default.createDirectory(at: dotBuild, withIntermediateDirectories: true)
    let debug = dotBuild.appendingPathComponent("debug")
    try FileManager.default.createSymbolicLink(
        at: debug, withDestinationURL: dotBuild.appendingPathComponent("arm64-apple-macosx/debug"))
    let fakeApp = root.appendingPathComponent("Companion.app")
    let exe = fakeApp.appendingPathComponent("Contents/MacOS/Companion")
    expect(UIResourceBundle.resolve(mainBundleURL: fakeApp, executableURL: exe, buildDirectory: debug) == nil,
           "21c QA: .build/debug colgando = nil en UI, nunca Bundle.module")
    expect(ServicesResourceBundle.resolve(mainBundleURL: fakeApp, executableURL: exe, buildDirectory: debug) == nil,
           "21c QA: .build/debug colgando = nil en Services, nunca Bundle.module")
}

/// LOW, decision pinned: only `.app` (what bundle.sh writes) counts as an app.
@MainActor func testOnlyALowercaseAppExtensionCountsAsAnApp() {
    let name = "Companion_CompanionUI.bundle"
    let upper = URL(fileURLWithPath: "/fake/Companion.APP")
    let found = ResourceBundleLocator.locate(
        bundleName: name, mainBundleURL: upper, executableURL: nil, buildDirectory: nil,
        isDirectory: { $0.path == "/fake/Companion.APP/Contents/Resources/\(name)" })
    expectEq(found, nil, "21c QA: .APP no se trata como .app (bundle.sh siempre escribe .app)")
}

// MARK: - Fonts in one place

@MainActor func testFontsReadOnlyTheResolvedBundle() {
    expectEq(Fonts.bundledDirectories(bundle: nil), [],
             "21c fuentes: sin bundle no hay carpeta propia, ni copia en Contents/Resources/Fonts")
    let bundle = UIResourceBundle.bundle
    expectEq(Fonts.bundledDirectories(bundle: bundle),
             [bundle?.resourceURL?.appendingPathComponent("Fonts")].compactMap { $0 },
             "21c fuentes: una sola carpeta, la del bundle")
}

// MARK: - Helpers

private func probeTempRoot(_ tag: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("probe21c-\(tag)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func removeProbeTemp(_ url: URL) {
    do { try FileManager.default.removeItem(at: url) } catch {}
}

private func fakeResourcesWithExtension() throws -> URL {
    let root = try probeTempRoot("res")
    let folder = root.appendingPathComponent("BrowserExtension")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("manifest.json"))
    return root
}

private func sourceSkillCount() -> Int {
    let skills = URL(fileURLWithPath: repoPath("Sources/CompanionServices/Skills"))
    let folders: [URL]
    do {
        folders = try FileManager.default.contentsOfDirectory(at: skills, includingPropertiesForKeys: nil)
    } catch {
        return -1
    }
    return folders.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }.count
}
