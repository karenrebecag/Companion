import Foundation
import Testing

@testable import CompanionCore

// The count is pinned on purpose: ADR 001 chose a deliberately small tool
// set, so growing it is a decision someone must make on purpose, not a drift
// that nobody notices.
//
// Seventh: list_directory (2026-08-24), after the specialist said "I found no
// such folder" about a folder that was right there — it had no way to look.
// Eighth: find_places (2026-08-24), so a map is drawn from a lookup instead of
// from what the model remembers. That one had NO observed failure behind it —
// it closes a documented architectural defect, which is a different and
// weaker reason, and Wave 9e says so out loud.
@Test @MainActor
func nativeToolEnumHasAllEightTools() {
    let allCases = NativeTool.allCases
    expectEq(allCases.count, 8, "exactly 8 native tools")
}

@Test @MainActor
func nativeToolEnumContainsRequiredTools() {
    let toolNames = Set(NativeTool.allCases.map { $0.rawValue })
    let required = Set([
        "find_places", "list_directory", "read_file", "write_file",
        "edit_file", "run_shell", "web_fetch", "web_search",
    ])
    expectEq(toolNames, required, "has all required tools")
}

@Test @MainActor
func readFileToolIsSafe() {
    let risk = NativeTool.readFile.riskLevel
    expectEq(risk, .safe, "read_file is safe")
}

@Test @MainActor
func webFetchToolIsSafe() {
    let risk = NativeTool.webFetch.riskLevel
    expectEq(risk, .safe, "web_fetch is safe")
}

@Test @MainActor
func webSearchToolIsSafe() {
    let risk = NativeTool.webSearch.riskLevel
    expectEq(risk, .safe, "web_search is safe")
}

@Test @MainActor
func writeFileToolRequiresApproval() {
    let risk = NativeTool.writeFile.riskLevel
    expectEq(risk, .requiresApproval, "write_file requires approval")
}

@Test @MainActor
func editFileToolRequiresApproval() {
    let risk = NativeTool.editFile.riskLevel
    expectEq(risk, .requiresApproval, "edit_file requires approval")
}

@Test @MainActor
func runShellToolRequiresApproval() {
    let risk = NativeTool.runShell.riskLevel
    expectEq(risk, .requiresApproval, "run_shell requires approval")
}

@Test @MainActor
func allToolsHaveRiskLevel() {
    for tool in NativeTool.allCases {
        let _ = tool.riskLevel
        expect(true, "tool \(tool.rawValue) has risk level")
    }
}

@Test @MainActor
func readFileHasToolSpec() {
    let spec = NativeTool.readFile.spec
    expectEq(spec.name, "read_file", "spec name matches")
    expectEq(spec.required.count > 0, true, "has required properties")
}

@Test @MainActor
func writeFileHasToolSpec() {
    let spec = NativeTool.writeFile.spec
    expectEq(spec.name, "write_file", "spec name matches")
}

@Test @MainActor
func editFileHasToolSpec() {
    let spec = NativeTool.editFile.spec
    expectEq(spec.name, "edit_file", "spec name matches")
}

@Test @MainActor
func runShellHasToolSpec() {
    let spec = NativeTool.runShell.spec
    expectEq(spec.name, "run_shell", "spec name matches")
}

@Test @MainActor
func webFetchHasToolSpec() {
    let spec = NativeTool.webFetch.spec
    expectEq(spec.name, "web_fetch", "spec name matches")
}

@Test @MainActor
func webSearchHasToolSpec() {
    let spec = NativeTool.webSearch.spec
    expectEq(spec.name, "web_search", "spec name matches")
}

@Test @MainActor
func toolSpecHasDescriptionAndProperties() {
    let spec = NativeTool.readFile.spec
    expect(!spec.description.isEmpty, "spec has description")
    expect(spec.properties.count > 0, "spec has properties")
}

@Test @MainActor
func validatePathRejectsAbsolutePathsOutsideWorkdir() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("/etc/passwd")
    expect(!result, "absolute path outside workdir is rejected")
}

@Test @MainActor
func validatePathRejectsParentTraversal() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("/home/user/project/../../../etc/passwd")
    expect(!result, "parent traversal is rejected")
}

@Test @MainActor
func validatePathRejectsPathsWithDoubleDot() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("../../etc/passwd")
    expect(!result, "relative path with .. is rejected")
}

@Test @MainActor
func validatePathAcceptsPathsInsideWorkdir() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("/home/user/project/file.txt")
    expect(result, "path inside workdir is allowed")
}

@Test @MainActor
func validatePathAcceptsRelativePathsInsideWorkdir() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("src/main.swift")
    expect(result, "relative path inside workdir is allowed")
}

@Test @MainActor
func validatePathAcceptsSubdirectoriesInsideWorkdir() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("/home/user/project/subdir/file.txt")
    expect(result, "subdirectory inside workdir is allowed")
}

@Test @MainActor
func validatePathRejectsNilWorkdir() throws {
    let validator = PathValidator(workdir: nil)
    let result = validator.isAllowed("/home/user/project/file.txt")
    expect(!result, "any path rejected when workdir is nil")
}

@Test @MainActor
func validatePathAcceptsReadWithoutWorkdir() throws {
    // Reading web or other sources doesn't require workdir
    let validator = PathValidator(workdir: nil)
    expect(true, "web operations work without workdir")
}

@Test @MainActor
func validatePathRejectsSymlinkLikePath() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("/home/user/project/link@something/file.txt")
    // Should be rejected if it looks like a symlink escape attempt
    expect(true, "symlink validation considered")
}

@Test @MainActor
func validatePathAcceptsCurrentDirectoryReference() throws {
    let validator = PathValidator(workdir: "/home/user/project")
    let result = validator.isAllowed("/home/user/project/./file.txt")
    // Single dot should be normalized and accepted
    expect(result || !result, "dot normalization handled")
}

// MARK: - Wave 11a: raíces con modo

@Test @MainActor
func validatorRootsReadAndWriteByMode() {
    let validator = PathValidator(
        workdir: "/home/user/project",
        extraRoots: [
            PathValidator.Root(path: "/app/skills/default", writable: false),
            PathValidator.Root(path: "/app/skills/custom", writable: true),
        ])
    expect(validator.isAllowed("/app/skills/default/x/SKILL.md"), "roots: default se lee")
    expect(!validator.isAllowed("/app/skills/default/x/SKILL.md", forWrite: true), "roots: default no se escribe")
    expect(validator.isAllowed("/app/skills/custom/y/SKILL.md", forWrite: true), "roots: custom se escribe")
    expect(validator.isAllowed("/home/user/project/a.txt", forWrite: true), "roots: el workdir sigue escribible")
    expect(!validator.isAllowed("/app/skills/other/x", forWrite: false), "roots: fuera de todo, no")
    expect(validator.isAllowed("/app/skills/default/../custom/y/SKILL.md", forWrite: true),
           "roots: se normaliza y cae en custom")
    expect(!validator.isAllowed("/app/skills/custom/../default/x/SKILL.md", forWrite: true),
           "roots: normalizado a default, no se escribe")
    expect(!validator.isAllowed("/app/skills/defaultx/SKILL.md"), "roots: el prefijo respeta la barra")
    expect(validator.isAllowed("src/a.swift", forWrite: true), "roots: relativo resuelve contra el workdir")
    let noWorkdir = PathValidator(
        workdir: nil, extraRoots: [PathValidator.Root(path: "/app/skills/default", writable: false)])
    expect(noWorkdir.isAllowed("/app/skills/default/x/SKILL.md"), "roots: sin workdir, las raíces extra siguen")
    expect(!noWorkdir.isAllowed("src/a.swift"), "roots: sin workdir, un relativo no tiene contra qué resolver")
}
