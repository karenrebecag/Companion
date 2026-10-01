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

private let supportTargets: Set<String> = [
    "CompanionTestKit", "CompanionCoreTestSupport", "CompanionServicesTestSupport", "CompanionUITestSupport",
]

private func manifest(_ root: URL, targets: [String: (resources: Bool, isolation: Bool)]) throws -> URL {
    let entries: [[String: Any]] = targets.keys.sorted().map { name in
        let spec = targets[name]!
        return [
            "name": name,
            "type": supportTargets.contains(name) ? "regular" : "test",
            "resources": spec.resources ? [["path": "Fonts", "rule": ["copy": [String: String]()]]] : [],
            "settings": spec.isolation
                ? [["kind": ["defaultIsolation": ["_0": "MainActor"]], "tool": "swift"]] : [],
        ]
    }
    let data = try JSONSerialization.data(withJSONObject: ["targets": entries])
    let url = root.appendingPathComponent("manifest.json")
    try data.write(to: url)
    return url
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
    expect(result.status != 0 && result.output.contains("[R3]"), "R3: UITests with resources: \(result.output)")
}

@Test func layerGateRejectsResourcesInUITestSupport() throws {
    let root = try fixture(["CompanionUITestSupport/S.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: ["CompanionUITestSupport": (true, false)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]"), "R3: UITestSupport with resources: \(result.output)")
}

@Test func layerGateRejectsDefaultIsolationInUITestSupport() throws {
    let root = try fixture(["CompanionUITestSupport/S.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: ["CompanionUITestSupport": (false, true)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]"), "R3: UITestSupport with defaultIsolation: \(result.output)")
}

@Test func layerGateAcceptsCleanManifest() throws {
    let root = try fixture(["CompanionUITests/T.swift": "import CompanionUI\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: [
        "CompanionUITests": (false, false), "CompanionUITestSupport": (false, false),
        "CompanionTests": (true, true),
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
    let json = try manifest(root, targets: ["CompanionTests": (false, false)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]"),
           "R3: UITests folder but no UITests target: \(result.output)")
}

@Test func layerGateSkipsR3WhenTheFolderIsAbsent() throws {
    let root = try fixture(["CompanionTests/T.swift": "import CompanionCore\n"])
    defer { removeScriptTemp(root) }
    let json = try manifest(root, targets: ["CompanionTests": (true, true)])
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

@Test func layerGateAllowsExportedImportInCompanionTests() throws {
    // CompanionTests still holds the voice files until PR 4; the exemption goes with that folder.
    try expectLayerResult([
        "CompanionTests/SupportImports.swift": "@_exported import CompanionTestKit\n",
    ], passes: true, "R4: @_exported in CompanionTests")
}

// MARK: - R3 on the support targets (real dump-package shape)

private typealias ManifestTarget = [String: Any]

private func target(
    _ name: String, type: String = "regular", deps: [String] = [], settings: Bool = false,
    shape: String = "byName"
) -> ManifestTarget {
    [
        "name": name,
        "type": type,
        "resources": [],
        "settings": settings ? [["kind": ["enableUpcomingFeature": ["_0": "X"]], "tool": "swift"]] : [],
        "dependencies": deps.map { [shape: [$0, NSNull()]] },
    ]
}

private func cleanTargets() -> [ManifestTarget] {
    [
        target("CompanionCore"),
        target("CompanionServices", deps: ["CompanionCore"]),
        target("CompanionUI", deps: ["CompanionCore"]),
        target("CompanionApp", type: "executable", deps: ["CompanionCore", "CompanionServices", "CompanionUI"]),
        target("CompanionTestKit"),
        target("CompanionCoreTestSupport", deps: ["CompanionCore", "CompanionTestKit"]),
        target("CompanionServicesTestSupport",
               deps: ["CompanionServices", "CompanionCoreTestSupport", "CompanionTestKit"]),
        target("CompanionUITestSupport", deps: ["CompanionUI", "CompanionCoreTestSupport", "CompanionTestKit"]),
        target("CompanionCoreTests", type: "test",
               deps: ["CompanionCore", "CompanionCoreTestSupport", "CompanionTestKit"]),
        target("CompanionServicesTests", type: "test",
               deps: ["CompanionCore", "CompanionServices", "CompanionServicesTestSupport",
                      "CompanionCoreTestSupport", "CompanionTestKit"]),
        target("CompanionUITests", type: "test",
               deps: ["CompanionCore", "CompanionUI", "CompanionUITestSupport",
                      "CompanionCoreTestSupport", "CompanionTestKit"]),
        target("CompanionIntegrationTests", type: "test",
               deps: ["CompanionCore", "CompanionServices", "CompanionUI", "CompanionTestKit",
                      "CompanionCoreTestSupport", "CompanionServicesTestSupport", "CompanionUITestSupport"]),
        target("CompanionTests", type: "test", deps: ["CompanionCore", "CompanionServicesTestSupport"]),
    ]
}

/// Replaces the named target in the clean manifest, or appends it.
private func manifestFile(_ root: URL, replacing replacement: ManifestTarget? = nil) throws -> URL {
    var targets = cleanTargets()
    if let replacement {
        if let index = targets.firstIndex(where: { $0["name"] as? String == replacement["name"] as? String }) {
            targets[index] = replacement
        } else {
            targets.append(replacement)
        }
    }
    let data = try JSONSerialization.data(withJSONObject: ["targets": targets])
    let url = root.appendingPathComponent("manifest.json")
    try data.write(to: url)
    return url
}

private func expectManifestResult(
    _ replacement: ManifestTarget?, passes: Bool, _ label: String,
    folders: [String: String] = ["CompanionCoreTestSupport/S.swift": "import CompanionCore\n"],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let root = try fixture(folders)
    defer { removeScriptTemp(root, sourceLocation: sourceLocation) }
    let result = try runLayers(root, manifest: try manifestFile(root, replacing: replacement))
    expect(result.status == 0 ? passes : !passes, "\(label): \(result.output)", sourceLocation: sourceLocation)
    if !passes {
        expect(result.output.contains("[R3]"), "\(label): output names R3: \(result.output)",
               sourceLocation: sourceLocation)
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
    let json = try manifest(root, targets: ["CompanionTests": (false, false)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]"),
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
    let json = try manifest(root, targets: ["CompanionTests": (false, false)])
    let result = try runLayers(root, manifest: json)
    expect(result.status != 0 && result.output.contains("[R3]"),
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

@Test func layerGateLeavesTheLegacyCompanionTestsUnconstrained() throws {
    try expectManifestResult(
        target("CompanionTests", type: "test",
               deps: ["CompanionCore", "CompanionServices", "CompanionUI", "CompanionTestKit",
                      "CompanionCoreTestSupport", "CompanionServicesTestSupport", "CompanionUITestSupport"]),
        passes: true, "R3: legacy CompanionTests keeps every dependency")
}

@Test func layerGateRejectsExportedImportBehindAStackedAttribute() throws {
    try expectLayerResult([
        "CompanionIntegrationTests/T.swift": "@MainActor @_exported import CompanionTestKit\n",
    ], passes: false, "R4: stacked attributes", rule: "R4")
}
