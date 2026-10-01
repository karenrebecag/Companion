import CompanionTestKit
import Foundation
import Testing

// The test-layer gate (scripts/check-test-layers.sh) runs against fixture trees
// built in a temp dir, so the rules are proven without touching the real
// Tests/ layout.

private let layerScript = Conformance.repoRoot().map {
    $0.appendingPathComponent("scripts/check-test-layers.sh").path
} ?? ""

private let systemEnv = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

/// Builds Tests/<dir>/<file> entries under a fresh temp root.
private func fixture(_ files: [String: String]) throws -> URL {
    let root = try scriptTempRoot("layers")
    for (path, body) in files {
        let url = root.appendingPathComponent("Tests/\(path)")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
}

/// The clean manifest with resources or isolation switched on for the named
/// targets. It always starts complete, so a case fails only for what it sets:
/// a partial manifest would trip the missing-layer-target check instead.
private func manifest(
    _ root: URL, targets: [String: (resources: Bool, isolation: Bool)], omit: Set<String> = []
) throws -> URL {
    // A misspelled name would leave the manifest clean and let the case pass
    // for the wrong reason.
    let known = Set(cleanTargets().compactMap { $0["name"] as? String })
    try #require(Set(targets.keys).union(omit).isSubset(of: known), "unknown target in \(targets.keys) \(omit)")
    let entries: [ManifestTarget] = cleanTargets().compactMap { entry in
        guard let name = entry["name"] as? String, !omit.contains(name) else { return nil }
        guard let spec = targets[name] else { return entry }
        var changed = entry
        changed["resources"] = spec.resources ? [["path": "Fonts", "rule": ["copy": [String: String]()]]] : []
        changed["settings"] = spec.isolation
            ? [["kind": ["defaultIsolation": ["_0": "MainActor"]], "tool": "swift"]] : []
        return changed
    }
    let data = try JSONSerialization.data(withJSONObject: ["targets": entries, "products": realProducts()])
    let url = root.appendingPathComponent("manifest.json")
    try data.write(to: url)
    return url
}

/// The `products` shape of the real `swift package dump-package`.
private func realProducts() -> [[String: Any]] {
    [["name": "companion", "settings": [Any](), "targets": ["CompanionApp"], "type": ["executable": NSNull()]]]
}

private func runLayers(
    _ root: URL, manifest: URL? = nil, env: [String: String] = systemEnv
) throws -> (status: Int32, output: String) {
    let args = [layerScript, root.path] + (manifest.map { [$0.path] } ?? [])
    return try runProcess("/bin/bash", args, env: env)
}

/// A failing case must name its rule: a missing script also exits non-zero,
/// and that must not read as a pass.
private func expectLayerResult(
    _ files: [String: String], passes: Bool, _ label: String, rule: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let root = try fixture(files)
    defer { removeScriptTemp(root, sourceLocation: sourceLocation) }
    let result = try runLayers(root)
    expect(result.status == 0 ? passes : !passes, "\(label): \(result.output)", sourceLocation: sourceLocation)
    if let rule {
        expect(result.output.contains("[\(rule)]"), "\(label): output names \(rule): \(result.output)",
               sourceLocation: sourceLocation)
    }
}

@Test func layerGateCleanTreePasses() throws {
    try expectLayerResult([
        "CompanionCoreTests/A.swift": "import CompanionCore\nimport Testing\n",
        "CompanionUITests/B.swift": "@testable import CompanionUI\n",
        "CompanionTestKit/K.swift": "import Foundation\nimport Testing\n",
    ], passes: true, "clean tree")
}

@Test func layerGateRejectsTestableInSupportFolder() throws {
    try expectLayerResult([
        "CompanionCoreTestSupport/S.swift": "@testable import CompanionCore\n",
    ], passes: false, "R1: @testable in a support folder", rule: "R1")
}

@Test func layerGateAllowsTestableInTestsFolder() throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "@testable import CompanionCore\n",
    ], passes: true, "R1: @testable in a *Tests folder")
}

@Test func layerGateRejectsCoreTestsImportingServices() throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "import CompanionServices\n",
    ], passes: false, "R2: CoreTests -> Services", rule: "R2")
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "import CompanionServicesTestSupport\n",
    ], passes: false, "R2: CoreTests -> ServicesTestSupport", rule: "R2")
}

@Test func layerGateRejectsUITestsImportingServices() throws {
    try expectLayerResult([
        "CompanionUITests/T.swift": "import CompanionServices\n",
    ], passes: false, "R2: UITests -> Services", rule: "R2")
}

@Test func layerGateRejectsTestKitImportingCore() throws {
    try expectLayerResult([
        "CompanionTestKit/K.swift": "import CompanionCore\n",
    ], passes: false, "R2: TestKit -> Core", rule: "R2")
}

@Test func layerGateIgnoresCommentedImports() throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "// import CompanionServices\n  // @testable import CompanionUI\n",
        "CompanionCoreTestSupport/S.swift": "// @testable import CompanionCore\n",
    ], passes: true, "commented imports")
}

@Test func layerGateMatchesWholeIdentifiers() throws {
    // ServicesTestSupport is legal for UITests: only bare CompanionServices is forbidden there.
    try expectLayerResult([
        "CompanionServicesTests/T.swift": "import CompanionServicesTestSupport\n",
        "CompanionUITests/U.swift": "import CompanionUITestSupport\n",
    ], passes: true, "identifier boundary")
    try expectLayerResult([
        "CompanionUITests/U.swift": "import CompanionServicesTestSupport\n",
    ], passes: false, "UITests -> ServicesTestSupport still fails", rule: "R2")
}

@Test func layerGateRejectsImportFormsWithAttributesAndKinds() throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "@_exported import CompanionUI\n",
    ], passes: false, "@_exported form", rule: "R2")
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "import struct CompanionServices.Thing\n",
    ], passes: false, "import struct form", rule: "R2")
}

@Test func layerGateRejectsResourcesInUITests() throws {
    let root = try fixture(["CompanionUITests/T.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: ["CompanionUITests": (true, false)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]")
           && result.output.contains("CompanionUITests declares resources"),
           "R3: UITests with resources: \(result.output)")
}

@Test func layerGateRejectsResourcesInUITestSupport() throws {
    let root = try fixture(["CompanionUITestSupport/S.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: ["CompanionUITestSupport": (true, false)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]")
           && result.output.contains("CompanionUITestSupport declares resources"),
           "R3: UITestSupport with resources: \(result.output)")
}

@Test func layerGateRejectsDefaultIsolationInUITestSupport() throws {
    let root = try fixture(["CompanionUITestSupport/S.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: ["CompanionUITestSupport": (false, true)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]") && result.output.contains("defaultIsolation"),
           "R3: UITestSupport with defaultIsolation: \(result.output)")
}

@Test func layerGateAcceptsCleanManifest() throws {
    let root = try fixture(["CompanionUITests/T.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [
        "CompanionUITests": (false, false), "CompanionUITestSupport": (false, false),
        "CompanionCoreTests": (true, true),
    ])
    let result = try runLayers(root, manifest: json)
    expect(result.status == 0, "R3: clean manifest: \(result.output)")
}

@Test func layerGateFailsClosedOnUnparseableManifest() throws {
    let root = try fixture(["CompanionUITests/T.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let bad = root.appendingPathComponent("manifest.json")
    try "not json".write(to: bad, atomically: true, encoding: .utf8)
    let result = try runLayers(root, manifest: bad)
    expect(result.status != 0 && result.output.contains("[error]"), "fail closed on bad JSON: \(result.output)")
}

@Test func layerGateFailsClosedWithoutTestsDirectory() throws {
    let root = try scriptTempRoot("layers-empty")
    defer { removeScriptTemp(root) }
    let result = try runLayers(root)
    expect(result.status != 0 && result.output.contains("[error]"), "fail closed when <root>/Tests is missing: \(result.output)")
}

// MARK: - Access-level imports and statement separators

@Test func layerGateRejectsAccessLevelImports() throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "public import CompanionServices\n",
    ], passes: false, "R2: public import", rule: "R2")
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "package import CompanionUI\n",
    ], passes: false, "R2: package import", rule: "R2")
    try expectLayerResult([
        "CompanionCoreTestSupport/S.swift": "@testable public import CompanionCore\n",
    ], passes: false, "R1: @testable public import in a support folder", rule: "R1")
}

@Test func layerGateSeesASecondImportAfterASemicolon() throws {
    // Interpolated: spelled out after a semicolon, the module name would read as
    // a real second import statement to the gate scanning this very file (R2).
    let forbiddenModule = "CompanionUI"
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "import Foundation; import \(forbiddenModule)\n",
    ], passes: false, "R2: import after a semicolon", rule: "R2")
    try expectLayerResult([
        "CompanionCoreTestSupport/S.swift": "import Foundation; @testable import CompanionCore\n",
    ], passes: false, "R1: @testable after a semicolon", rule: "R1")
}

// MARK: - R2, table-driven

/// The plan's R2 table, written out by hand: deriving it from the script
/// would make the test agree with whatever the script says.
struct LayerPair: Sendable, CustomTestStringConvertible {
    let folder: String
    let module: String
    var testDescription: String { "\(folder) -> \(module)" }
}

private let layerPairs: [LayerPair] = {
    let table: [(folders: [String], forbidden: [String])] = [
        (["CompanionTestKit"], [
            "CompanionCore", "CompanionServices", "CompanionUI",
            "CompanionCoreTestSupport", "CompanionServicesTestSupport", "CompanionUITestSupport",
        ]),
        (["CompanionCoreTestSupport", "CompanionCoreTests"], [
            "CompanionServices", "CompanionUI", "CompanionServicesTestSupport", "CompanionUITestSupport",
        ]),
        (["CompanionServicesTestSupport", "CompanionServicesTests"], [
            "CompanionUI", "CompanionUITestSupport",
        ]),
        (["CompanionUITestSupport", "CompanionUITests"], [
            "CompanionServices", "CompanionServicesTestSupport",
        ]),
    ]
    return table.flatMap { row in
        row.folders.flatMap { folder in row.forbidden.map { LayerPair(folder: folder, module: $0) } }
    }
}()

@Test(arguments: layerPairs)
func layerGateRejectsEveryForbiddenImport(pair: LayerPair) throws {
    try expectLayerResult([
        "\(pair.folder)/T.swift": "import \(pair.module)\n",
    ], passes: false, "R2: \(pair.testDescription)", rule: "R2")
}

@Test func layerGateAllowsNeighbouringModuleNames() throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "import CompanionServicesExtra\n",
        "CompanionServicesTests/T.swift": "import CompanionUIKit\n",
        "CompanionTestKit/K.swift": "import Foundation\n",
    ], passes: true, "identifier boundary on longer module names")
}

@Test(arguments: ["struct", "class", "enum", "protocol", "typealias", "func", "let", "var"])
func layerGateRejectsEveryImportKind(kind: String) throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "import \(kind) CompanionServices.Thing\n",
    ], passes: false, "R2: import \(kind)", rule: "R2")
}

@Test func layerGateRejectsStackedAttributes() throws {
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "@MainActor @testable import CompanionServices\n",
    ], passes: false, "R2: stacked attributes", rule: "R2")
}

@Test func layerGateRejectsTestableWhereTheLayerIsForbidden() throws {
    // R1 allows @testable in a *Tests folder; R2 must still apply.
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "@testable import CompanionServices\n",
    ], passes: false, "R2 survives R1's allowance", rule: "R2")
}

// MARK: - Fail closed

@Test func layerGateFailsClosedOnAnUnreadableFolder() throws {
    let root = try fixture(["CompanionCoreTests/T.swift": "import CompanionCore\n"])
    let locked = root.appendingPathComponent("Tests/CompanionCoreTests").path
    defer {
        chmod(locked, 0o755)
        removeScriptTemp(root)
    }
    expect(chmod(locked, 0o000) == 0, "fixture: folder locked")
    let result = try runLayers(root)
    expect(result.status != 0 && result.output.contains("[error]"),
           "an unreadable folder is an error, not a pass: \(result.output)")
}

@Test func layerGateFailsClosedWithoutPython() throws {
    let root = try fixture(["CompanionUITests/T.swift": "import CompanionUI\n"])
    let bin = try scriptTempRoot("layers-bin")
    defer {
        removeScriptTemp(root)
        removeScriptTemp(bin)
    }
    for tool in ["bash", "grep", "find", "basename", "dirname"] {
        let real = ["/bin/\(tool)", "/usr/bin/\(tool)"].first { FileManager.default.fileExists(atPath: $0) }
        try FileManager.default.createSymbolicLink(
            atPath: bin.appendingPathComponent(tool).path, withDestinationPath: real ?? "/usr/bin/\(tool)")
    }
    let json = try manifest(root, targets: ["CompanionUITests": (false, false)])
    let result = try runLayers(root, manifest: json, env: ["PATH": bin.path])
    expect(result.status != 0 && result.output.contains("[error]"),
           "no python3 means no manifest check, which must fail: \(result.output)")
}

// MARK: - R3, target absent from the manifest

@Test func layerGateRejectsAFolderWithoutItsManifestTarget() throws {
    let root = try fixture(["CompanionUITests/T.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [:], omit: ["CompanionUITests"])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("Tests/CompanionUITests exists"),
           "R3: UITests folder but no UITests target: \(result.output)")
}

@Test func layerGateRejectsASwiftFileLooseInTests() throws {
    // No target owns a file directly under Tests/, so its tests never run.
    let root = try fixture([
        "CompanionCoreTestSupport/S.swift": "import CompanionCore\n",
        "Loose.swift": "import Testing\n", "Other.swift": "import Testing\n", "README.md": "notes\n",
    ])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [:])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]") && result.output.contains("Tests/Loose.swift")
           && result.output.contains("Tests/Other.swift") && !result.output.contains("README"),
           "R3: every loose Swift file is named, a loose non-Swift file is not: \(result.output)")
}

@Test func layerGateSkipsR3WhenTheFolderIsAbsent() throws {
    let root = try fixture(["CompanionCoreTests/T.swift": "import CompanionCore\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: ["CompanionCoreTests": (true, true)])
    let result = try runLayers(root, manifest: json)
    expect(result.status == 0, "R3: neither folder nor target: \(result.output)")
}

// MARK: - R4, @_exported import

@Test func layerGateRejectsExportedImportInATestsFolder() throws {
    try expectLayerResult([
        "CompanionIntegrationTests/T.swift": "@_exported import CompanionTestKit\n",
    ], passes: false, "R4: @_exported in IntegrationTests", rule: "R4")
}

@Test func layerGateRejectsExportedImportInASupportFolder() throws {
    try expectLayerResult([
        "CompanionCoreTestSupport/S.swift": "@_exported import CompanionTestKit\n",
    ], passes: false, "R4: @_exported in a support folder", rule: "R4")
}

@Test func layerGateRejectsExportedImportInTheRetiredCompanionTests() throws {
    // The transitional target is gone; its exemption went with it.
    try expectLayerResult([
        "CompanionTests/SupportImports.swift": "@_exported import CompanionTestKit\n",
    ], passes: false, "R4: @_exported in Tests/CompanionTests", rule: "R4")
}

// MARK: - R3 on the support targets (real dump-package shape)

private typealias ManifestTarget = [String: Any]

private func target(
    _ name: String, type: String = "regular", deps: [String] = [], settings: Bool = false,
    shape: String = "byName", path: String? = nil
) -> ManifestTarget {
    var entry: ManifestTarget = [
        "name": name,
        "type": type,
        "resources": [],
        "settings": settings ? [["kind": ["enableUpcomingFeature": ["_0": "X"]], "tool": "swift"]] : [],
        "dependencies": deps.map { [shape: [$0, NSNull()]] },
    ]
    if let path { entry["path"] = path }
    return entry
}

/// Mirrors `swift package dump-package`: everything under Tests/ declares its
/// path; the production targets use the default Sources/ and declare none.
private func cleanTargets() -> [ManifestTarget] {
    func underTests(
        _ name: String, type: String = "regular", deps: [String]
    ) -> ManifestTarget {
        target(name, type: type, deps: deps, path: "Tests/\(name)")
    }
    return [
        target("CompanionCore"),
        target("CompanionServices", deps: ["CompanionCore"]),
        target("CompanionUI", deps: ["CompanionCore"]),
        target("CompanionApp", type: "executable", deps: ["CompanionCore", "CompanionServices", "CompanionUI"]),
        underTests("CompanionTestKit", deps: []),
        underTests("CompanionCoreTestSupport", deps: ["CompanionCore", "CompanionTestKit"]),
        underTests("CompanionServicesTestSupport",
                   deps: ["CompanionServices", "CompanionCoreTestSupport", "CompanionTestKit"]),
        underTests("CompanionUITestSupport", deps: ["CompanionUI", "CompanionCoreTestSupport", "CompanionTestKit"]),
        underTests("CompanionCoreTests", type: "test",
                   deps: ["CompanionCore", "CompanionCoreTestSupport", "CompanionTestKit"]),
        underTests("CompanionServicesTests", type: "test",
                   deps: ["CompanionCore", "CompanionServices", "CompanionServicesTestSupport",
                          "CompanionCoreTestSupport", "CompanionTestKit"]),
        underTests("CompanionUITests", type: "test",
                   deps: ["CompanionCore", "CompanionUI", "CompanionUITestSupport",
                          "CompanionCoreTestSupport", "CompanionTestKit"]),
        underTests("CompanionIntegrationTests", type: "test",
                   deps: ["CompanionCore", "CompanionServices", "CompanionUI", "CompanionTestKit",
                          "CompanionCoreTestSupport", "CompanionServicesTestSupport", "CompanionUITestSupport"]),
    ]
}

private enum ProductsInput {
    case real
    case missing
    case value(Any)
}

/// Replaces the named target in the clean manifest, or appends it.
private func manifestFile(
    _ root: URL, replacing replacement: ManifestTarget? = nil, products: ProductsInput = .real
) throws -> URL {
    var targets = cleanTargets()
    if let replacement {
        if let index = targets.firstIndex(where: { $0["name"] as? String == replacement["name"] as? String }) {
            targets[index] = replacement
        } else {
            targets.append(replacement)
        }
    }
    var object: [String: Any] = ["targets": targets]
    switch products {
    case .real: object["products"] = realProducts()
    case .missing: break
    case .value(let value): object["products"] = value
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    let url = root.appendingPathComponent("manifest.json")
    try data.write(to: url)
    return url
}

private func expectManifestResult(
    _ replacement: ManifestTarget?, passes: Bool, _ label: String,
    folders: [String: String] = ["CompanionCoreTestSupport/S.swift": "import CompanionCore\n"],
    products: ProductsInput = .real, mention: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let root = try fixture(folders)
    defer { removeScriptTemp(root, sourceLocation: sourceLocation) }
    let result = try runLayers(root, manifest: try manifestFile(root, replacing: replacement, products: products))
    expect(result.status == 0 ? passes : !passes, "\(label): \(result.output)", sourceLocation: sourceLocation)
    if !passes {
        expect(result.output.contains("[R3]"), "\(label): output names R3: \(result.output)",
               sourceLocation: sourceLocation)
        if let mention {
            expect(result.output.contains(mention), "\(label): output names \(mention): \(result.output)",
                   sourceLocation: sourceLocation)
        }
    }
}

@Test func layerGateAcceptsTheRealShapedCleanManifest() throws {
    try expectManifestResult(nil, passes: true, "R3: clean manifest with all support targets")
}

@Test func layerGateAcceptsTargetShapedDependencies() throws {
    try expectManifestResult(
        target("CompanionCoreTestSupport", deps: ["CompanionCore", "CompanionTestKit"], shape: "target"),
        passes: true, "R3: dependencies spelled as target")
}

@Test func layerGateRejectsSettingsOnASupportTarget() throws {
    try expectManifestResult(
        target("CompanionCoreTestSupport", deps: ["CompanionCore", "CompanionTestKit"], settings: true),
        passes: false, "R3: support target with settings")
}

@Test func layerGateRejectsASupportTargetOfTypeTest() throws {
    try expectManifestResult(
        target("CompanionCoreTestSupport", type: "test", deps: ["CompanionCore", "CompanionTestKit"]),
        passes: false, "R3: support target of type test")
}

@Test func layerGateRejectsCoreSupportDependingOnServices() throws {
    try expectManifestResult(
        target("CompanionCoreTestSupport", deps: ["CompanionCore", "CompanionTestKit", "CompanionServices"]),
        passes: false, "R3: CoreTestSupport -> Services")
}

@Test func layerGateRejectsTestKitDependingOnAnyCompanionTarget() throws {
    try expectManifestResult(
        target("CompanionTestKit", deps: ["CompanionCore"]),
        passes: false, "R3: TestKit -> Core")
}

@Test func layerGateRejectsServicesSupportDependingOnUI() throws {
    try expectManifestResult(
        target("CompanionServicesTestSupport", deps: ["CompanionServices", "CompanionUI"]),
        passes: false, "R3: ServicesTestSupport -> UI")
}

@Test func layerGateRejectsUISupportDependingOnServicesSupport() throws {
    try expectManifestResult(
        target("CompanionUITestSupport", deps: ["CompanionUI", "CompanionServicesTestSupport"]),
        passes: false, "R3: UITestSupport -> ServicesTestSupport")
}

@Test func layerGateRejectsAProductionTargetDependingOnSupport() throws {
    try expectManifestResult(
        target("CompanionApp", type: "executable",
               deps: ["CompanionCore", "CompanionServices", "CompanionUI", "CompanionCoreTestSupport"]),
        passes: false, "R3: CompanionApp -> CoreTestSupport")
    try expectManifestResult(
        target("CompanionCore", deps: ["CompanionTestKit"]),
        passes: false, "R3: CompanionCore -> TestKit")
}

@Test func layerGateRejectsASupportFolderWithoutItsManifestTarget() throws {
    let root = try fixture(["CompanionUITestSupport/S.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [:], omit: ["CompanionUITestSupport"])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("Tests/CompanionUITestSupport exists"),
           "R3: support folder but no support target: \(result.output)")
}

// MARK: - R3 fix round: every production target, every folder, test-target dependencies

@Test func layerGateRejectsAnyProductionTargetDependingOnSupport() throws {
    try expectManifestResult(
        target("CompanionFoo", deps: ["CompanionCore", "CompanionTestKit"]),
        passes: false, "R3: an unlisted production target -> TestKit")
}

@Test func layerGateRejectsAFolderWithoutAnyManifestTarget() throws {
    let root = try fixture(["CompanionCoreTests/T.swift": "import CompanionCore\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [:], omit: ["CompanionCoreTests"])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("Tests/CompanionCoreTests exists"),
           "R3: CoreTests folder but no CoreTests target: \(result.output)")
}

@Test func layerGateIgnoresFoldersWithoutSwiftFiles() throws {
    try expectManifestResult(
        nil, passes: true, "R3: a fixtures folder needs no target",
        folders: ["Fixtures/notes.txt": "data\n", "CompanionCoreTestSupport/S.swift": "import CompanionCore\n"])
}

@Test func layerGateRejectsServicesTestsDependingOnUI() throws {
    try expectManifestResult(
        target("CompanionServicesTests", type: "test",
               deps: ["CompanionCore", "CompanionServices", "CompanionUI", "CompanionServicesTestSupport",
                      "CompanionCoreTestSupport", "CompanionTestKit"]),
        passes: false, "R3: ServicesTests -> UI")
}

@Test func layerGateRejectsCoreTestsDependingOnAnUnlistedLayer() throws {
    try expectManifestResult(
        target("CompanionCoreTests", type: "test",
               deps: ["CompanionCore", "CompanionServicesTestSupport", "CompanionTestKit"]),
        passes: false, "R3: CoreTests -> ServicesTestSupport")
}

@Test func layerGateRejectsTheRetiredCompanionTestsTarget() throws {
    try expectManifestResult(
        target("CompanionTests", type: "test",
               deps: ["CompanionCore", "CompanionServices", "CompanionUI", "CompanionTestKit",
                      "CompanionCoreTestSupport", "CompanionServicesTestSupport", "CompanionUITestSupport"]),
        passes: false, "R3: a CompanionTests target is no longer allowed", mention: "CompanionTests")
}

// MARK: - R3, support targets recognised by name

@Test func layerGateTreatsAnyTestSupportNamedTargetAsSupport() throws {
    // A new support target must not slip past the production-dependency check.
    try expectManifestResult(
        target("CompanionCore", deps: ["CompanionFooTestSupport"]),
        passes: false, "R3: production -> an unlisted *TestSupport", mention: "CompanionFooTestSupport")
}

@Test func layerGateRejectsASupportTargetWithoutALayerTableEntry() throws {
    try expectManifestResult(
        target("CompanionFooTestSupport", deps: ["CompanionCore"]),
        passes: false, "R3: *TestSupport with no table entry", mention: "CompanionFooTestSupport")
}

@Test func layerGateRejectsAProductListingAnUnlistedSupportTarget() throws {
    try expectManifestResult(
        target("CompanionFooTestSupport", deps: ["CompanionCore"]),
        passes: false, "R3: product -> an unlisted *TestSupport",
        products: .value(realProducts() + [library("Foo", targets: ["CompanionFooTestSupport"])]),
        mention: "lists CompanionFooTestSupport")
}

@Test func layerGateRejectsExportedImportBehindAStackedAttribute() throws {
    try expectLayerResult([
        "CompanionIntegrationTests/T.swift": "@MainActor @_exported import CompanionTestKit\n",
    ], passes: false, "R4: stacked attributes", rule: "R4")
}

// MARK: - R3, test-target dependency table: negative cases

/// (target, extra dependency) pairs the table must reject. The base set is the
/// clean manifest's own, so the only difference is the one widened edge.
struct ExtraDependency: Sendable, CustomTestStringConvertible {
    let target: String
    let extra: String
    var testDescription: String { "\(target) -> \(extra)" }
}

private let forbiddenTestEdges: [ExtraDependency] = [
    ExtraDependency(target: "CompanionUITests", extra: "CompanionServices"),
    ExtraDependency(target: "CompanionUITests", extra: "CompanionServicesTestSupport"),
    ExtraDependency(target: "CompanionIntegrationTests", extra: "CompanionApp"),
    ExtraDependency(target: "CompanionCoreTests", extra: "CompanionServices"),
    ExtraDependency(target: "CompanionServicesTests", extra: "CompanionUITestSupport"),
]

@Test(arguments: forbiddenTestEdges)
func layerGateRejectsAWidenedTestTargetDependency(edge: ExtraDependency) throws {
    let base = try #require(cleanTargets().first { $0["name"] as? String == edge.target })
    let names = (base["dependencies"] as? [[String: [Any]]] ?? []).compactMap { $0["byName"]?.first as? String }
    try expectManifestResult(
        target(edge.target, type: "test", deps: names + [edge.extra]),
        passes: false, "R3: \(edge.testDescription)", mention: edge.extra)
}

// MARK: - R3, products

private func library(_ name: String, targets: [String]) -> [String: Any] {
    ["name": name, "settings": [Any](), "targets": targets, "type": ["library": ["automatic"]]]
}

@Test func layerGateAcceptsTheRealShapedProducts() throws {
    try expectManifestResult(nil, passes: true, "R3: only the companion executable", products: .real)
}

@Test func layerGateRejectsALibraryProductListingTheTestKit() throws {
    try expectManifestResult(
        nil, passes: false, "R3: library product -> TestKit",
        products: .value(realProducts() + [library("Kit", targets: ["CompanionTestKit"])]))
}

@Test func layerGateRejectsAnExecutableProductListingASupportTarget() throws {
    let exe: [String: Any] = [
        "name": "companion", "settings": [Any](), "targets": ["CompanionApp", "CompanionUITestSupport"],
        "type": ["executable": NSNull()],
    ]
    try expectManifestResult(nil, passes: false, "R3: executable product -> UITestSupport", products: .value([exe]))
}

@Test func layerGateRejectsAProductListingATestTarget() throws {
    try expectManifestResult(
        nil, passes: false, "R3: product -> a test target",
        products: .value(realProducts() + [library("T", targets: ["CompanionCoreTests"])]))
}

@Test func layerGateRejectsAProductListingAnUnknownTarget() throws {
    try expectManifestResult(
        nil, passes: false, "R3: product -> a target the manifest does not have",
        products: .value(realProducts() + [library("Ghost", targets: ["CompanionGhost"])]),
        mention: "CompanionGhost")
}

@Test func layerGatePassesAnEmptyProductsList() throws {
    try expectManifestResult(nil, passes: true, "R3: no products at all is fine", products: .value([Any]()))
}

@Test func layerGateFailsClosedWhenProductsIsMissing() throws {
    try expectManifestResult(nil, passes: false, "R3: no products key", products: .missing)
}

@Test(arguments: [
    #""a string""#, #"{"name": "x"}"#, #"[{"name": "x"}]"#,
    #"[{"name": "x", "targets": "CompanionApp"}]"#, #"[{"name": "x", "targets": [1]}]"#, "[1]", "null",
])
func layerGateFailsClosedOnMalformedProducts(json: String) throws {
    let products = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
    try expectManifestResult(nil, passes: false, "R3: malformed products \(json)", products: .value(products))
}

// MARK: - R3, support by location and missing layer targets

@Test func layerGateTreatsATargetUnderTestsAsSupportWhateverItsName() throws {
    // A support target named outside the *TestSupport pattern is still test code.
    try expectManifestResult(
        target("CompanionFakes", deps: ["CompanionCore"], path: "Tests/CompanionFakes"),
        passes: false, "R3: a regular target under Tests/ with no layer-table entry",
        mention: "support target CompanionFakes has no layer-table entry")
}

@Test func layerGateTreatsOtherSpellingsOfTestsAsSupport() throws {
    // SwiftPM keeps the path as written, and APFS is case-insensitive, so a
    // literal "Tests/" prefix would miss these.
    for path in ["./Tests/CompanionFakes", "tests/CompanionFakes", "Tests", "Sources/../Tests/CompanionFakes"] {
        try expectManifestResult(
            target("CompanionFakes", deps: ["CompanionCore"], path: path),
            passes: false, "R3: support spelled \(path)",
            mention: "support target CompanionFakes has no layer-table entry")
    }
}

@Test func layerGateLeavesARegularTargetOutsideTestsAlone() throws {
    try expectManifestResult(
        target("CompanionFoo", deps: ["CompanionCore"], path: "Sources/CompanionFoo"),
        passes: true, "R3: a production target with an explicit Sources/ path")
}

@Test func layerGateLeavesAnExtraTestTargetUnderTestsAlone() throws {
    // A test target is never support, so it needs no layer-table entry.
    try expectManifestResult(
        target("CompanionExtraTests", type: "test", deps: ["CompanionCore"], path: "Tests/CompanionExtraTests"),
        passes: true, "R3: a test target outside the layer table")
}

@Test func layerGateRejectsAProductionDependencyOnATestTarget() throws {
    try expectManifestResult(
        target("CompanionUI", deps: ["CompanionCore", "CompanionCoreTests"]),
        passes: false, "R3: production -> a test target",
        mention: "production target CompanionUI depends on CompanionCoreTests")
}

@Test func layerGateRejectsAProductionDependencyOnATargetUnderTests() throws {
    let root = try fixture(["CompanionCoreTestSupport/S.swift": "import CompanionCore\n"])
    defer { removeScriptTemp(root) }
    var targets = cleanTargets()
    targets.append(target("CompanionFakes", deps: ["CompanionCore"], path: "Tests/CompanionFakes"))
    if let index = targets.firstIndex(where: { $0["name"] as? String == "CompanionUI" }) {
        targets[index] = target("CompanionUI", deps: ["CompanionCore", "CompanionFakes"])
    }
    let url = root.appendingPathComponent("manifest.json")
    try JSONSerialization.data(withJSONObject: ["targets": targets, "products": realProducts()]).write(to: url)
    let result = try runLayers(root, manifest: url)
    expect(result.status != 0 && result.output.contains("production target CompanionUI depends on CompanionFakes"),
           "R3: production -> a target under Tests/: \(result.output)")
}

@Test func layerGateRejectsAManifestMissingALayerTarget() throws {
    // No folder either, so only the layer table can notice the target is gone.
    let root = try fixture(["CompanionCoreTestSupport/S.swift": "import CompanionCore\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [:], omit: ["CompanionServicesTestSupport"])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]")
           && result.output.contains("CompanionServicesTestSupport is missing"),
           "R3: a layer target dropped from the manifest: \(result.output)")
}

@Test func layerGateRejectsAManifestMissingALayerTestTarget() throws {
    let root = try fixture(["CompanionCoreTestSupport/S.swift": "import CompanionCore\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [:], omit: ["CompanionIntegrationTests"])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("CompanionIntegrationTests is missing"),
           "R3: a layer test target dropped from the manifest: \(result.output)")
}
