import CompanionTestKit
import Foundation
import Testing

// R3 source ownership: every .swift under Tests/ must be compiled by some
// target. The gate trusts `swift package describe`, which applies SwiftPM's
// own path/sources/exclude rules; docs/research/tests-sin-target.md.

private let gateEnv = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

/// A `swift package describe --type json` shape: each target's folder under
/// Tests/ and the sources SwiftPM resolved in it, relative to that folder.
private func describeFile(_ root: URL, _ owned: [String: [String]]) throws -> URL {
    let targets = owned.sorted { $0.key < $1.key }.map { name, sources in
        ["name": name, "path": "Tests/\(name)", "sources": sources, "type": "test"] as [String: Any]
    }
    let url = root.appendingPathComponent("describe.json")
    try JSONSerialization.data(withJSONObject: ["name": "companion", "targets": targets]).write(to: url)
    return url
}

private func runGate(_ root: URL, describe: URL) throws -> (status: Int32, output: String) {
    let manifest = try layerGateCleanManifest(root)
    return try runProcess("/bin/bash", [layerGateScript, root.path, manifest.path, describe.path], env: gateEnv)
}

private let support = ["CompanionCoreTestSupport/S.swift": "import CompanionCore\n"]

@Test func sourceGatePassesWhenEveryFileHasAnOwner() throws {
    let root = try layerGateFixture(support.merging(["CompanionCoreTests/A.swift": "import Testing\n"]) { $1 })
    defer { removeScriptTemp(root) }
    let describe = try describeFile(root, ["CompanionCoreTestSupport": ["S.swift"], "CompanionCoreTests": ["A.swift"]])
    let result = try runGate(root, describe: describe)
    expect(result.status == 0, "R3: every file owned: \(result.output)")
}

@Test(arguments: [
    "CompanionCoreTests/B.swift",          // left out by exclude: or sources:
    "CompanionCoreTests/Extra/C.swift",    // a subfolder the target's path does not reach
    "CompanionCoreTests/.Hidden.swift",    // SwiftPM skips dot names, so it never compiles
])
func sourceGateNamesAFileNoTargetCompiles(orphan: String) throws {
    let root = try layerGateFixture(support.merging([
        "CompanionCoreTests/A.swift": "import Testing\n", orphan: "import Testing\n",
    ]) { $1 })
    defer { removeScriptTemp(root) }
    let describe = try describeFile(root, ["CompanionCoreTestSupport": ["S.swift"], "CompanionCoreTests": ["A.swift"]])
    let result = try runGate(root, describe: describe)
    expect(result.status != 0 && result.output.contains("[R3]") && result.output.contains("Tests/\(orphan)")
           && !result.output.contains("Tests/CompanionCoreTests/A.swift"),
           "R3: \(orphan) is named, its owned sibling is not: \(result.output)")
}

@Test(arguments: ["not json", "{\"targets\": 3}", "{\"targets\": [{\"name\": \"X\", \"sources\": [\"A.swift\"]}]}"])
func sourceGateFailsClosedOnABadDescribe(body: String) throws {
    let root = try layerGateFixture(support)
    defer { removeScriptTemp(root) }
    let url = root.appendingPathComponent("describe.json")
    try body.write(to: url, atomically: true, encoding: .utf8)
    let result = try runGate(root, describe: url)
    expect(result.status != 0 && result.output.contains("[error]"), "R3: unreadable describe fails: \(result.output)")
}

@Test func sourceGateFailsClosedOnAMissingDescribe() throws {
    let root = try layerGateFixture(support)
    defer { removeScriptTemp(root) }
    let result = try runGate(root, describe: root.appendingPathComponent("absent.json"))
    expect(result.status != 0 && result.output.contains("[error]"), "R3: missing describe fails: \(result.output)")
}

/// Runs the real `swift package describe` in `root`, with the toolchain the
/// test runner was given (xcode-select or DEVELOPER_DIR).
private func swiftDescribe(_ root: URL) throws -> (status: Int32, output: String) {
    var env = gateEnv
    let outer = ProcessInfo.processInfo.environment
    env["HOME"] = outer["HOME"] ?? NSHomeDirectory()
    for key in ["DEVELOPER_DIR", "TMPDIR"] { if let value = outer[key] { env[key] = value } }
    return try runProcess("/bin/bash", ["-c", "cd \"$1\" && swift package describe --type json > describe.json",
                                        "sh", root.path], env: env)
}

/// Nested target paths are something only SwiftPM itself sees: describe
/// refuses them, and gates.sh fails the layer gate when describe fails.
@Test func sourceGateRealSwiftPMRefusesOverlappingTargets() throws {
    let root = try layerGateFixture(["Nest/N.swift": "let a = 1\n", "Nest/Inner/I.swift": "let b = 1\n"])
    defer { removeScriptTemp(root) }
    let package = """
        // swift-tools-version:6.0
        import PackageDescription
        let package = Package(name: "Fixture", targets: [
            .testTarget(name: "Nest", path: "Tests/Nest"),
            .testTarget(name: "Inner", path: "Tests/Nest/Inner"),
        ])
        """
    try package.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let made = try swiftDescribe(root)
    expect(made.status != 0 && made.output.contains("overlapping sources"),
           "describe refuses nested target paths: \(made.output)")
}

/// The real SwiftPM on a throwaway package, so the gate is checked against
/// what `describe` actually resolves, not against a guess of its rules.
@Test func sourceGateAgreesWithRealSwiftPM() throws {
    let root = try layerGateFixture([
        "Ex/In.swift": "let a = 1\n", "Ex/Out.swift": "let b = 1\n",
        "Src/Only/A.swift": "let c = 1\n", "Src/Top.swift": "let d = 1\n",
        "Empty/E.swift": "let e = 1\n",
        "Part/Inner/I.swift": "let f = 1\n", "Part/P.swift": "let g = 1\n",
    ])
    defer { removeScriptTemp(root) }
    let package = """
        // swift-tools-version:6.0
        import PackageDescription
        let package = Package(name: "Fixture", targets: [
            .testTarget(name: "Ex", path: "Tests/Ex", exclude: ["Out.swift"]),
            .testTarget(name: "Src", path: "Tests/Src", sources: ["Only"]),
            .testTarget(name: "Empty", path: "Tests/Empty", sources: []),
            .testTarget(name: "Inner", path: "Tests/Part/Inner"),
        ])
        """
    try package.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let describe = root.appendingPathComponent("describe.json")
    let made = try swiftDescribe(root)
    try #require(made.status == 0, "swift package describe failed: \(made.output)")
    // gates.sh runs describe on the real checkout; it must not leave build state behind.
    expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build").path),
           "describe leaves no .build in the package")
    let result = try runGate(root, describe: describe)
    for orphan in ["Tests/Ex/Out.swift", "Tests/Src/Top.swift", "Tests/Part/P.swift"] {
        expect(result.output.contains("FAIL [R3] \(orphan) "), "R3: SwiftPM leaves out \(orphan): \(result.output)")
    }
    for owned in ["Tests/Ex/In.swift", "Tests/Src/Only/A.swift", "Tests/Empty/E.swift", "Tests/Part/Inner/I.swift"] {
        expect(!result.output.contains(owned), "R3: SwiftPM compiles \(owned): \(result.output)")
    }
}
