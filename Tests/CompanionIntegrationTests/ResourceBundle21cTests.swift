import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// 21c S5 / D5(c): the SwiftPM accessor (native backend, 6.3.3) looks at the
// .app ROOT and at this checkout's .build, then fatalErrors; bundle.sh puts
// the bundles in Contents/Resources. A packaged app on another Mac trapped at
// launch. See docs/research/recursos-empaquetados-bundle-module.md §2, §8.

@Test @MainActor func resourceBundle21cTests() throws {
    testLocatorPrefersAppResources()
    testLocatorFallsBackBesideTheExecutable()
    testLocatorFindsTheBundleBesideTheLoadedTestBundle()
    testLocatorIgnoresACodeBundleThatIsNotAnXctest()
    testLocatorWithoutACodeBundleKeepsTheExistingOrder()
    testLocatorIgnoresContentsResourcesOutsideAnApp()
    testLocatorWithNothingPresentIsNil()
    try testResolversOnFakeAppLayout()
    try testResolversOnFakeExecutableLayout()
    try testResolversWithNothingPresentAreNilWithoutTrap()
    testResolversReachTheBundleBesideTheXctestUnderSwiftTest()
    try testNoProductionCodeEvaluatesModule()
    testFontsWithoutBundleKeepOnlyTheOtherDirectories()
    try testFontFilesAreDedupedByName()
    try testUserFontsWithABundledNameStillRegister()
    testLocalizedWithoutBundleShowsTheRawKey()
    testMascotWithoutBundleHasNoImage()
    testSkillsWithoutBundleThrowBundleMissing()
    testMermaidWithoutBundleIsUnavailable()
}

// MARK: - Pure order

private let uiName = "Companion_CompanionUI.bundle"
private let app = URL(fileURLWithPath: "/fake/Companion.app")
private let appExe = URL(fileURLWithPath: "/fake/Companion.app/Contents/MacOS/Companion")
private let xctest = URL(fileURLWithPath: "/fake/scratch/arm64-apple-macosx/debug/CompanionPackageTests.xctest")

private func locate(
    main: URL = app, exe: URL? = appExe, code: URL? = xctest, present: Set<String>
) -> ResourceBundleLocation? {
    ResourceBundleLocator.locate(
        bundleName: uiName, mainBundleURL: main, executableURL: exe,
        codeBundleURL: code, isDirectory: { present.contains($0.standardizedFileURL.path) })
}

@MainActor func testLocatorPrefersAppResources() {
    let inResources = "/fake/Companion.app/Contents/Resources/\(uiName)"
    let everywhere: Set<String> = [
        inResources, "/fake/Companion.app/Contents/MacOS/\(uiName)", "/fake/scratch/arm64-apple-macosx/debug/\(uiName)",
    ]
    expectEq(locate(present: everywhere), .directory(URL(fileURLWithPath: inResources)),
             "21c: una .app se resuelve en Contents/Resources antes que junto al binario o al .xctest")
}

@MainActor func testLocatorFallsBackBesideTheExecutable() {
    let beside = "/fake/Companion.app/Contents/MacOS/\(uiName)"
    expectEq(locate(present: [beside, "/fake/scratch/arm64-apple-macosx/debug/\(uiName)"]),
             .directory(URL(fileURLWithPath: beside)),
             "21c: sin Contents/Resources, el bundle junto al ejecutable")
}

@MainActor func testLocatorFindsTheBundleBesideTheLoadedTestBundle() {
    let sibling = "/fake/scratch/arm64-apple-macosx/debug/\(uiName)"
    expectEq(
        locate(main: URL(fileURLWithPath: "/fake/toolchain/usr/libexec/swift/pm"),
               exe: URL(fileURLWithPath: "/fake/toolchain/usr/libexec/swift/pm/swiftpm-testing-helper"),
               present: [sibling]),
        .directory(URL(fileURLWithPath: sibling)),
        "scratch path: bajo swift test el bundle es hermano del .xctest que cargo el codigo")
}

@MainActor func testLocatorIgnoresACodeBundleThatIsNotAnXctest() {
    let aside = "/fake/\(uiName)"
    expectEq(locate(code: URL(fileURLWithPath: "/fake/Companion.app"), present: [aside]), nil,
             "scratch path: el paso del .xctest no se aplica a una .app (su padre es ajeno)")
}

@MainActor func testLocatorWithoutACodeBundleKeepsTheExistingOrder() {
    expectEq(locate(code: nil, present: ["/fake/scratch/arm64-apple-macosx/debug/\(uiName)"]), nil,
             "scratch path: sin bundle de codigo conocido no hay paso del .xctest")
    expectEq(locate(present: []), nil, "scratch path: .xctest sin bundle hermano = nil")
}

@MainActor func testLocatorIgnoresContentsResourcesOutsideAnApp() {
    let runner = URL(fileURLWithPath: "/fake/bin")
    let notAnApp = "/fake/bin/Contents/Resources/\(uiName)"
    expectEq(locate(main: runner, exe: URL(fileURLWithPath: "/fake/bin/runner"), present: [notAnApp]), nil,
             "21c: Contents/Resources solo cuenta si Bundle.main es una .app")
}

@MainActor func testLocatorWithNothingPresentIsNil() {
    expectEq(locate(present: []), nil, "21c: nada presente = nil, no trap")
    expectEq(locate(exe: nil, present: []), nil, "21c: sin ejecutable conocido tampoco inventa uno")
}

// MARK: - Resolvers on real temp layouts

private func tempRoot(_ tag: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("res21c-\(tag)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeDir(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

private func samePath(_ bundle: Bundle?, _ url: URL) -> Bool {
    bundle?.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        == url.resolvingSymlinksInPath().standardizedFileURL.path
}

@MainActor func testResolversOnFakeAppLayout() throws {
    let root = try tempRoot("app")
    defer { removeQuietly(root) }
    let fakeApp = root.appendingPathComponent("Companion.app")
    let resources = fakeApp.appendingPathComponent("Contents/Resources")
    let ui = resources.appendingPathComponent(UIResourceBundle.name)
    let services = resources.appendingPathComponent(ServicesResourceBundle.name)
    try makeDir(ui)
    try makeDir(services)
    try makeDir(fakeApp.appendingPathComponent("Contents/MacOS"))
    let exe = fakeApp.appendingPathComponent("Contents/MacOS/Companion")

    expect(samePath(UIResourceBundle.resolve(mainBundleURL: fakeApp, executableURL: exe, codeBundleURL: nil), ui),
           "21c: UI resuelve el bundle de Contents/Resources de la .app")
    expect(samePath(ServicesResourceBundle.resolve(
        mainBundleURL: fakeApp, executableURL: exe, codeBundleURL: nil), services),
           "21c: Services resuelve el bundle de Contents/Resources de la .app")
}

@MainActor func testResolversOnFakeExecutableLayout() throws {
    let root = try tempRoot("exe")
    defer { removeQuietly(root) }
    let bin = root.appendingPathComponent("bin")
    let ui = bin.appendingPathComponent(UIResourceBundle.name)
    let services = bin.appendingPathComponent(ServicesResourceBundle.name)
    try makeDir(ui)
    try makeDir(services)
    let exe = bin.appendingPathComponent("companion")

    expect(samePath(UIResourceBundle.resolve(mainBundleURL: bin, executableURL: exe, codeBundleURL: nil), ui),
           "21c: UI resuelve el bundle junto al ejecutable")
    expect(samePath(ServicesResourceBundle.resolve(
        mainBundleURL: bin, executableURL: exe, codeBundleURL: nil), services),
           "21c: Services resuelve el bundle junto al ejecutable")
}

@MainActor func testResolversWithNothingPresentAreNilWithoutTrap() throws {
    let root = try tempRoot("none")
    defer { removeQuietly(root) }
    let fakeApp = root.appendingPathComponent("Companion.app")
    try makeDir(fakeApp.appendingPathComponent("Contents/MacOS"))
    let exe = fakeApp.appendingPathComponent("Contents/MacOS/Companion")

    expect(UIResourceBundle.resolve(mainBundleURL: fakeApp, executableURL: exe, codeBundleURL: nil) == nil,
           "21c: UI sin bundle en ningun lado = nil (nunca Bundle.module a ciegas)")
    expect(ServicesResourceBundle.resolve(mainBundleURL: fakeApp, executableURL: exe, codeBundleURL: nil) == nil,
           "21c: Services sin bundle en ningun lado = nil (nunca Bundle.module a ciegas)")
}

/// Under `swift test` Bundle.main is the runner, so only the step beside the
/// .xctest can find them, wherever `--scratch-path` put the build.
@MainActor func testResolversReachTheBundleBesideTheXctestUnderSwiftTest() {
    expect(UIResourceBundle.bundle?.path(forResource: "en", ofType: "lproj") != nil,
           "21c: bajo swift test el resolver de UI llega al bundle hermano del .xctest")
    expect(ServicesResourceBundle.bundle?.url(forResource: "Skills", withExtension: nil) != nil,
           "21c: bajo swift test el resolver de Services llega al bundle hermano del .xctest")
}

/// The accessor traps and nothing guards it any more, so nothing may evaluate it.
@MainActor func testNoProductionCodeEvaluatesModule() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")
    let pattern = try NSRegularExpression(pattern: #"\.module([^A-Za-z0-9_]|$)"#)
    var offenders: [String] = []
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let relative = String(file.standardizedFileURL.path.dropFirst(sources.standardizedFileURL.path.count + 1))
        let text = try String(contentsOf: file, encoding: .utf8)
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let code = String(raw.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            let range = NSRange(code.startIndex..., in: code)
            if pattern.firstMatch(in: code, range: range) != nil { offenders.append("\(relative):\(index + 1)") }
        }
    }
    expectEq(offenders, [], "scratch path: ningun archivo de Sources evalua .module")
}

// MARK: - Call sites degrade on nil

@MainActor func testFontsWithoutBundleKeepOnlyTheOtherDirectories() {
    expectEq(Fonts.bundledDirectories(bundle: nil), [],
             "21c fuentes: sin bundle, ninguna carpeta propia (quedan las del usuario y las del sistema)")
    Fonts.register(bundle: nil)
}

@MainActor func testFontFilesAreDedupedByName() throws {
    let root = try tempRoot("fonts")
    defer { removeQuietly(root) }
    let first = root.appendingPathComponent("bundle/Fonts")
    let second = root.appendingPathComponent("main/Fonts")
    try makeDir(first)
    try makeDir(second)
    for dir in [first, second] {
        try Data().write(to: dir.appendingPathComponent("Inter-Regular.otf"))
        try Data().write(to: dir.appendingPathComponent("README.txt"))
    }
    try Data().write(to: second.appendingPathComponent("Extra.TTF"))

    let files = Fonts.fontFiles(in: [first, second, root.appendingPathComponent("missing")])
    expectEq(files.map(\.lastPathComponent).sorted(), ["Extra.TTF", "Inter-Regular.otf"],
             "21c fuentes: el mismo archivo en dos carpetas se registra una vez")
    expect(files.contains { $0.deletingLastPathComponent().standardizedFileURL == first.standardizedFileURL
        && $0.lastPathComponent == "Inter-Regular.otf" },
           "21c fuentes: gana la primera carpeta (el bundle)")
}

@MainActor func testUserFontsWithABundledNameStillRegister() throws {
    let root = try tempRoot("user-fonts")
    defer { removeQuietly(root) }
    let bundled = root.appendingPathComponent("bundle/Fonts")
    let copy = root.appendingPathComponent("main/Fonts")
    let support = root.appendingPathComponent("support/Fonts")
    let library = root.appendingPathComponent("library/Fonts")
    for dir in [bundled, copy, support, library] {
        try makeDir(dir)
        try Data().write(to: dir.appendingPathComponent("Inter-Regular.otf"))
    }
    let files = Fonts.filesToRegister(bundled: [bundled, copy], user: [support, library])
    expectEq(files.map { $0.deletingLastPathComponent().standardizedFileURL },
             [bundled, support, library].map(\.standardizedFileURL),
             "21c fuentes: la copia de bundle.sh se deduplica, pero una fuente del usuario con el mismo nombre se sigue registrando, como antes")
}

@MainActor func testLocalizedWithoutBundleShowsTheRawKey() {
    expectEq(Localized.string("chat.job.done", language: .es, in: nil), "chat.job.done",
             "21c idioma: sin bundle, la clave cruda, nunca un trap")
}

@MainActor func testMascotWithoutBundleHasNoImage() {
    expect(ClaudeLogo.load(from: nil) == nil, "21c mascota: sin bundle, sin imagen")
}

@MainActor func testSkillsWithoutBundleThrowBundleMissing() {
    do {
        _ = try BundledSkills.load(from: nil)
        expect(false, "21c skills: sin bundle debio lanzar")
    } catch let error as SkillStoreError {
        expectEq(error, .bundleMissing, "21c skills: sin bundle = bundleMissing, lo atrapa el do/catch del arranque")
    } catch {
        expect(false, "21c skills: error inesperado \(error)")
    }
}

@MainActor func testMermaidWithoutBundleIsUnavailable() {
    expect(WebKitDiagramRenderer.vendoredScript(from: nil) == nil,
           "21c diagrama: sin bundle no hay script, el renderer da .unavailable")
}

private func removeQuietly(_ url: URL) {
    do { try FileManager.default.removeItem(at: url) } catch {}
}
