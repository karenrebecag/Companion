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

private func manifest(_ root: URL, targets: [String: (resources: Bool, isolation: Bool)]) throws -> URL {
    let entries: [[String: Any]] = targets.keys.sorted().map { name in
        let spec = targets[name]!
        return [
            "name": name,
            "type": "test",
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
    try expectLayerResult([
        "CompanionCoreTests/T.swift": "import Foundation; import CompanionUI\n",
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
