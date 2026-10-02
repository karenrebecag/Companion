import CompanionTestKit
import Foundation
import Testing

// FileManager.default.temporaryDirectory is the user's whole temp folder on
// Darwin, and it ignores TMPDIR, so nothing outside the test can fence it.
// Three NativeExecutor tests used it as their own folder and removed it in a
// defer: every local run tried to empty the user's temp folder, other apps'
// files included. A test only ever removes a folder it created.

@Test func noTestRemovesTheWholeTemporaryDirectory() {
    expectTheScannerCatchesAWipe()
    guard let root = Conformance.repoRoot() else { return }
    let tests = root.appendingPathComponent("Tests")
    // This file's own fixtures spell the forbidden shape on purpose.
    let me = URL(fileURLWithPath: #filePath).standardizedFileURL.path
    let files = Conformance.swiftFiles(in: tests).filter { $0.standardizedFileURL.path != me }
    expect(!files.isEmpty, "temp: el escaneo no encontro fuentes en \(tests.path)")
    var wipes: [String] = []
    for file in files {
        guard let src = try? String(contentsOf: file, encoding: .utf8) else {
            expect(false, "temp: no se pudo leer \(file.path)")
            continue
        }
        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
        wipes += temporaryDirectoryWipes(in: src).map { "\(relative):\($0)" }
    }
    expectEq(wipes, [], "temp: ningun test borra el directorio temporal entero; usa una carpeta propia")
}

/// The scanner can fail: the shape that shipped is caught, the same shape
/// with a folder of its own is not, and neither is the name reused elsewhere.
private func expectTheScannerCatchesAWipe() {
    let wipe = """
        func a() {
            let tempDir = FileManager.default.temporaryDirectory.path
            defer { try? FileManager.default.removeItem(atPath: tempDir) }
        }
        """
    expectEq(temporaryDirectoryWipes(in: wipe), [2], "control: el defer que borra el temporal entero se detecta")

    let direct = "try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory)"
    expectEq(temporaryDirectoryWipes(in: direct), [1], "control: la llamada directa se detecta")

    let alias = """
        func e() {
            var t = fm.temporaryDirectory
            defer { try? fm.removeItem(at: t) }
        }
        """
    expectEq(temporaryDirectoryWipes(in: alias), [2], "control: el alias fm y var tambien se detectan")

    let own = """
        func b() {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("b-\\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
        }
        func c() {
            let tempDir = FileManager.default.temporaryDirectory
            let file = tempDir.appendingPathComponent("x")
        }
        func d() {
            defer { try? FileManager.default.removeItem(atPath: tempDir) }
        }
        """
    expectEq(temporaryDirectoryWipes(in: own), [], "control: una carpeta propia, o el mismo nombre en otra funcion, no cuentan")
}

/// 1-based lines that bind the whole temp directory and remove it in the same
/// function, or remove it directly. A continuation line starting with `.` is
/// joined to the one above, so `.appendingPathComponent` on the next line
/// makes the binding a folder of its own.
///
/// A heuristic that guards the shape that shipped, not a proof. It does not
/// follow the path through a helper, a conversion such as
/// `URL(fileURLWithPath:)`, a second alias, or a loop that empties the
/// folder child by child; a new shape like those gets its own control here.
private func temporaryDirectoryWipes(in src: String) -> [Int] {
    let tempDir = #"((FileManager\.default|FileManager\(\)|fm)\.temporaryDirectory(\.path)?|NSTemporaryDirectory\(\))"#
    let lines = joinedContinuations(src)
    var found: [Int] = []
    for (index, entry) in lines.enumerated() {
        if matches(#"removeItem\((at|atPath):\s*\#(tempDir)\s*\)"#, entry.text) {
            found.append(entry.line)
            continue
        }
        guard let name = firstCapture(#"\b(?:let|var)\s+(\w+)\s*=\s*\#(tempDir)\s*$"#, entry.text) else { continue }
        let wipe = #"removeItem\((at|atPath):\s*\#(name)\s*\)"#
        for later in lines[(index + 1)...] {
            if matches(#"^\s*(@Test|((private|package|public|static|@MainActor)\s+)*func\s)"#, later.text) { break }
            if matches(wipe, later.text) {
                found.append(entry.line)
                break
            }
        }
    }
    return found
}

private func joinedContinuations(_ src: String) -> [(line: Int, text: String)] {
    var out: [(line: Int, text: String)] = []
    for (offset, raw) in src.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") { continue }
        if trimmed.hasPrefix("."), let last = out.indices.last {
            out[last].text += trimmed
        } else {
            out.append((offset + 1, String(raw)))
        }
    }
    return out
}

private func matches(_ pattern: String, _ text: String) -> Bool {
    guard let re = try? NSRegularExpression(pattern: pattern) else {
        expect(false, "temp: patron invalido \(pattern)")
        return false
    }
    return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

private func firstCapture(_ pattern: String, _ text: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range])
}
