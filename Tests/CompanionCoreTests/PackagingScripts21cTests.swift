import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// 21c S3: the packaging scripts read as text. Only the lines bash executes
// count, so a comment can never satisfy a check. The behaviour of those
// scripts is pinned in PackageContents21cTests and ReleaseScript21cTests.

@Test @MainActor func packagingScripts21cTests() {
    testBundleScriptSkipsInstallAndRunsTheSmoke()
    testReleaseScriptStructure()
    testSmokeScriptAssertsTheIsolatedLaunch()
}

// MARK: - Script text, executable lines only

/// A shell script reduced to what bash runs: blank and comment lines dropped.
struct ExecutableShellLines {
    let lines: [String]

    init(_ text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }
    }

    init(file relative: String) {
        self.init(scriptText(relative))
    }

    func first(containing needle: String) -> Int? { lines.firstIndex { $0.contains(needle) } }
    func exact(_ line: String) -> [Int] { lines.indices.filter { lines[$0] == line } }
    func contains(_ needle: String) -> Bool { first(containing: needle) != nil }

    /// if/for/while/until/case and `{` blocks still open before line `index`.
    func depth(before index: Int) -> Int {
        lines[..<index].reduce(0) { depth, raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            let word = line.split(separator: " ").first.map(String.init) ?? ""
            let opens = ["if", "for", "while", "until", "case"].contains(word) || line.hasSuffix("{")
            let closesInline = line.hasSuffix("; fi") || line.hasSuffix("; done") || line.hasSuffix(" esac")
            let closes = ["fi", "done", "esac", "}"].contains(word)
            return depth + (opens && !closesInline ? 1 : 0) - (closes ? 1 : 0)
        }
    }

    /// A command whose failure `set -e` turns into the script's failure: its
    /// own line, column 0, outside any block, not chained to a neighbour.
    func isStandaloneCommand(_ index: Int) -> Bool {
        let line = lines[index]
        guard !line.hasPrefix(" "), !line.hasPrefix("\t"), depth(before: index) == 0 else { return false }
        if index > 0 {
            let previous = lines[index - 1].trimmingCharacters(in: .whitespaces)
            if ["\\", "||", "&&", "|"].contains(where: { previous.hasSuffix($0) }) { return false }
        }
        if index + 1 < lines.count {
            let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
            if ["||", "&&", "|"].contains(where: { next.hasPrefix($0) }) { return false }
        }
        return true
    }

    /// True when every index exists and they appear in the given order.
    static func inOrder(_ indices: [Int?]) -> Bool {
        let found = indices.compactMap { $0 }
        return found.count == indices.count && found == found.sorted()
    }
}

private let smokeCall = #""$ROOT/scripts/package-smoke.sh" "$APP""#
let contentsLibSource = #". "$ROOT/scripts/package-contents.sh""#

@MainActor func testBundleScriptSkipsInstallAndRunsTheSmoke() {
    let script = ExecutableShellLines(file: "scripts/bundle.sh")
    let raw = scriptText("scripts/bundle.sh")
    expect(!script.exact("set -euo pipefail").isEmpty, "21c QA: bundle.sh corre con set -euo pipefail")
    let smoke = script.exact(smokeCall)
    expectEq(smoke.count, 1, "21c QA: bundle.sh llama al smoke una vez, en una linea ejecutable propia")
    expect(smoke.first.map(script.isStandaloneCommand) == true,
           "21c QA: el smoke de bundle.sh va en columna 0, fuera de bloques, sin || ni &&")
    expect(ExecutableShellLines.inOrder([
        script.first(containing: "codesign --force"), smoke.first,
        script.first(containing: "COMPANION_NO_INSTALL:-"), script.first(containing: #"ditto "$APP" "$INSTALL""#),
    ]), "21c D6/smoke: firma, smoke, guard de no-instalar y ditto, en ese orden (lineas ejecutables)")
    expect(!script.contains("/tmp/companion-codesign.err"), "21c LOW: bundle.sh ya no usa un .err fijo en /tmp")
    expect(script.contains("mktemp") && script.lines.contains { $0.hasPrefix("trap ") && $0.contains("rm") },
           "21c LOW: el error de codesign va a un mktemp que un trap borra")
    expect(!script.contains(#"cp -R "$ROOT/Extensions/browser"#),
           "21c item 6: bundle.sh ya no copia Extensions/browser entera")
    expect(script.contains(contentsLibSource) && script.contains("browser_extension_copy "),
           "21c item 6: bundle.sh copia la extension por la lista de scripts/package-contents.sh")
    expect(!raw.contains("Resources/Fonts"), "21c fuentes: bundle.sh ya no copia Contents/Resources/Fonts")
    expect(!raw.contains("SKIP_SMOKE") && !raw.contains("NO_SMOKE"),
           "21c smoke: sin valvula para saltarlo (la spec no la preve)")
}

@MainActor func testReleaseScriptStructure() {
    let script = ExecutableShellLines(file: "scripts/release.sh")
    expect(!script.exact("set -euo pipefail").isEmpty, "21c QA: release.sh corre con set -euo pipefail")
    let bundle = script.exact(#"COMPANION_NO_INSTALL=1 "$ROOT/scripts/bundle.sh" release"#)
    expectEq(bundle.count, 1, "21c D6: release.sh llama a bundle.sh con COMPANION_NO_INSTALL=1")
    expect(bundle.first.map(script.isStandaloneCommand) == true, "21c D6: esa llamada no esta encadenada ni en un bloque")
    expectEq(script.lines.filter { $0.contains("scripts/bundle.sh") }.count, 1,
             "21c D6: ninguna otra llamada a bundle.sh puede instalar")
    let smoke = script.exact(smokeCall)
    expectEq(smoke.count, 1, "21c re-smoke: release.sh corre el smoke sobre la app re-firmada")
    expect(smoke.first.map(script.isStandaloneCommand) == true,
           "21c re-smoke: columna 0, fuera de bloques, sin || ni &&")
    expect(ExecutableShellLines.inOrder([
        script.first(containing: "--options runtime"), smoke.first, script.first(containing: "hdiutil create"),
    ]), "21c re-smoke: re-firma, smoke y hdiutil, en ese orden")
    expect(ExecutableShellLines.inOrder([script.first(containing: "COMPANION_ALLOW_DIRTY"), bundle.first]),
           "21c D7: la politica de dirty se decide antes de compilar")
}

@MainActor func testSmokeScriptAssertsTheIsolatedLaunch() {
    let script = ExecutableShellLines(file: "scripts/package-smoke.sh")
    expect(!script.lines.isEmpty, "21c smoke: existe scripts/package-smoke.sh")
    expect(!script.exact("set -euo pipefail").isEmpty, "21c QA: package-smoke.sh corre con set -euo pipefail")
    for needle in ["sandbox-exec", "COMPANION_RESOURCE_PROBE=1", ResourceProbe.marker,
                   "could not load resource bundle", #"codesign --verify --strict "$APP""#, "BrowserExtension"] {
        expect(script.contains(needle), "21c smoke: una linea ejecutable contiene \(needle)")
    }
    expect(script.contains(#"codesign --verify --strict "$app""#),
           "21c LOW: el smoke verifica la firma de cada copia que ejecuta")
    expect(script.contains(contentsLibSource), "21c item 6: el smoke lee la misma lista que bundle.sh")
    for (needle, label) in [
        (#"browser_extension_strays "$APP"#, "rechaza archivos de la extension fuera de la lista"),
        (#"browser_extension_strays "$STRAY"#, "control negativo de la extension"),
        (#"app_forbidden_entries "$APP""#, "escanea la app entera"),
        (#"resource_folder_strays "$APP"#, "compara las carpetas de recursos con git"),
        (#"app_forbidden_entries "$SKILLS_STRAY""#, "control negativo del escaneo en un bundle de Skills"),
        (#"resource_folder_strays "$SKILLS_STRAY"#, "control negativo de la comparacion con git"),
    ] {
        expect(script.contains(needle), "21c smoke: \(label)")
    }
}

// MARK: - Shared helpers for the 21c script tests

func scriptText(_ relative: String, sourceLocation: SourceLocation = #_sourceLocation) -> String {
    do {
        return try String(contentsOfFile: repoPath(relative), encoding: .utf8)
    } catch {
        Issue.record("21c: no se pudo leer \(relative): \(error)", sourceLocation: sourceLocation)
        return ""
    }
}

/// Reads to EOF before waiting: the pipe closing is the event, never a timer.
func runProcess(_ exe: String, _ args: [String], env: [String: String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: exe)
    process.arguments = args
    process.environment = env
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}
