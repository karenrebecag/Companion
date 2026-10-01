import CompanionTestKit
import Foundation
import Testing

// 21c S3: release.sh and the smoke's ROOT guard, run for real in a throwaway
// tree where every tool that could build, sign or write a DMG is a stub.

@Test func releaseScript21cTests() throws {
    try testReleaseResmokesTheReSignedAppBeforeTheDMG()
    try testReleaseStopsBeforeTheDMGWhenTheResmokeFails()
    try testReleaseRefusesADirtyTree()
    try testReleaseDirtyValveLetsItThroughWithAWarning()
    try testReleaseIgnoresUntrackedDocs()
    try testReleaseWithoutGitIsDirty()
    try testReleaseJudgesItsOwnCheckoutNotAParentRepo()
    try testReleaseCountsAnIgnoredFileInTheResourcePathsAsDirty()
    try testSmokeRejectsARootTheSandboxProfileCannotQuote()
}

/// A copy of release.sh in `base/checkout`. bundle.sh and package-smoke.sh
/// are stubs beside it (release.sh derives ROOT from its own path, so the
/// real ones are unreachable) and codesign, hdiutil, xcrun and security are
/// stubs first on PATH. Every call lands in `log`.
private struct ReleaseRig {
    enum Git { case own, none, parent }

    let base: URL
    let root: URL
    var log: URL { root.appendingPathComponent("calls.log") }

    init(git: Git = .own) throws {
        base = try scriptTempRoot("release")
        root = base.appendingPathComponent("checkout")
        let scripts = root.appendingPathComponent("scripts")
        let bin = root.appendingPathComponent("bin")
        for dir in [scripts, bin, root.appendingPathComponent("Sources"), root.appendingPathComponent("docs")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(atPath: repoPath("scripts/release.sh"),
                                         toPath: scripts.appendingPathComponent("release.sh").path)
        try stub(scripts, "bundle.sh", """
            echo "bundle NO_INSTALL=${COMPANION_NO_INSTALL:-unset} $*" >> "$LOG"
            mkdir -p "$(dirname "$0")/../build/Companion.app"
            """)
        try stub(scripts, "package-smoke.sh", #"echo "smoke $1" >> "$LOG"; exit "${SMOKE_RC:-0}""#)
        try stub(bin, "codesign", #"echo "codesign $*" >> "$LOG""#)
        try stub(bin, "hdiutil", #"echo "hdiutil $1" >> "$LOG""#)
        try stub(bin, "xcrun", "exit 1")
        try stub(bin, "security", "exit 0")
        try write("Sources/A.swift", "let a = 1\n")
        try write(".gitignore", "calls.log\nbin/\nbuild/\n*.local\n")
        switch git {
        case .own: try commitAll(in: root)
        case .parent: try commitAll(in: base)
        case .none: break
        }
    }

    func write(_ relative: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(relative))
    }

    func run(_ extra: [String: String] = [:]) throws -> (status: Int32, output: String, calls: [String]) {
        var env = [
            "PATH": root.appendingPathComponent("bin").path + ":/usr/bin:/bin",
            "HOME": base.path,
            "LOG": log.path,
            "COMPANION_SIGN_IDENTITY": "Fake Developer ID",
            "GIT_CEILING_DIRECTORIES": base.deletingLastPathComponent().path,
        ]
        env.merge(extra) { $1 }
        let ran = try runProcess("/bin/bash", [root.appendingPathComponent("scripts/release.sh").path], env: env)
        var text = ""
        if FileManager.default.fileExists(atPath: log.path) { text = try String(contentsOf: log, encoding: .utf8) }
        return (ran.status, ran.output, text.split(separator: "\n").map(String.init))
    }

    func remove() { removeScriptTemp(base) }

    private func commitAll(in dir: URL) throws {
        for args in [["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "base"]] {
            let full = ["-C", dir.path, "-c", "user.name=t", "-c", "user.email=t@t",
                        "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args
            let ran = try runProcess("/usr/bin/git", full, env: ["HOME": base.path, "PATH": "/usr/bin:/bin"])
            if ran.status != 0 { throw CocoaError(.fileWriteUnknown, userInfo: ["git": ran.output]) }
        }
    }

    private func stub(_ dir: URL, _ name: String, _ body: String) throws {
        let url = dir.appendingPathComponent(name)
        try Data("#!/bin/bash\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

func testReleaseResmokesTheReSignedAppBeforeTheDMG() throws {
    let rig = try ReleaseRig()
    defer { rig.remove() }
    let ran = try rig.run()
    expectEq(ran.status, 0, "21c re-smoke: con todo en verde release.sh termina (\(ran.output))")
    expectEq(ran.calls.first, "bundle NO_INSTALL=1 release", "21c D6: release.sh construye sin instalar")
    let resign = ran.calls.firstIndex { $0.hasPrefix("codesign --force --deep --options runtime") }
    let smoke = ran.calls.firstIndex { $0.hasPrefix("smoke ") && $0.hasSuffix("/build/Companion.app") }
    let dmg = ran.calls.firstIndex { $0 == "hdiutil create" }
    expect(ExecutableShellLines.inOrder([resign, smoke, dmg]),
           "21c re-smoke: re-firma, smoke de esa misma app y despues el DMG (\(ran.calls))")
}

func testReleaseStopsBeforeTheDMGWhenTheResmokeFails() throws {
    let rig = try ReleaseRig()
    defer { rig.remove() }
    let ran = try rig.run(["SMOKE_RC": "1"])
    expect(ran.status != 0, "21c re-smoke: si el smoke de la app re-firmada falla, release.sh falla")
    expect(!ran.calls.contains("hdiutil create"), "21c re-smoke: y no crea el DMG (\(ran.calls))")
}

private func expectRefused(_ rig: ReleaseRig, _ label: String) throws {
    let ran = try rig.run()
    expect(ran.status != 0, "21c D7: \(label) = dirty, release.sh se niega (\(ran.output))")
    expect(!ran.calls.contains { $0.hasPrefix("bundle ") }, "21c D7: \(label): se niega antes de compilar")
    expect(ran.output.contains("COMPANION_ALLOW_DIRTY=1"), "21c D7: \(label): el mensaje nombra la valvula")
}

func testReleaseRefusesADirtyTree() throws {
    for (label, change) in [("sin trackear en Sources", "Sources/New.swift"), ("trackeado modificado", "Sources/A.swift")] {
        let rig = try ReleaseRig()
        defer { rig.remove() }
        try rig.write(change, "let b = 2\n")
        try expectRefused(rig, label)
    }
}

func testReleaseDirtyValveLetsItThroughWithAWarning() throws {
    let rig = try ReleaseRig()
    defer { rig.remove() }
    try rig.write("Sources/New.swift", "let b = 2\n")
    let ran = try rig.run(["COMPANION_ALLOW_DIRTY": "1"])
    expectEq(ran.status, 0, "21c D7: con la valvula pasa (\(ran.output))")
    expect(ran.calls.contains("bundle NO_INSTALL=1 release"), "21c D7: con la valvula compila")
    expect(ran.output.contains("aviso"), "21c D7: con la valvula imprime un aviso")
}

func testReleaseIgnoresUntrackedDocs() throws {
    let rig = try ReleaseRig()
    defer { rig.remove() }
    try rig.write("docs/notes.md", "x\n")
    let ran = try rig.run()
    expectEq(ran.status, 0, "21c D7: un archivo sin trackear solo en docs/ no es dirty (\(ran.output))")
}

func testReleaseWithoutGitIsDirty() throws {
    let rig = try ReleaseRig(git: .none)
    defer { rig.remove() }
    try expectRefused(rig, "sin git")
}

func testReleaseJudgesItsOwnCheckoutNotAParentRepo() throws {
    let rig = try ReleaseRig(git: .parent)
    defer { rig.remove() }
    try expectRefused(rig, "checkout sin git propio dentro de un repo padre limpio")
}

func testReleaseCountsAnIgnoredFileInTheResourcePathsAsDirty() throws {
    let rig = try ReleaseRig()
    defer { rig.remove() }
    try rig.write("Sources/secret.local", "K=1\n")
    try expectRefused(rig, "ignorado dentro de Sources")
}

// MARK: - package-smoke.sh ROOT guard

func testSmokeRejectsARootTheSandboxProfileCannotQuote() throws {
    for name in ["bad\"quote", "bad\\slash", "bad)paren", "plain"] {
        let base = try scriptTempRoot("smoke-root")
        defer { removeScriptTemp(base) }
        let scripts = base.appendingPathComponent(name).appendingPathComponent("scripts")
        let app = base.appendingPathComponent("Fake.app")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        for script in ["package-smoke.sh", "package-contents.sh"] {
            try FileManager.default.copyItem(atPath: repoPath("scripts/\(script)"),
                                             toPath: scripts.appendingPathComponent(script).path)
        }
        let ran = try runProcess("/bin/bash", [scripts.appendingPathComponent("package-smoke.sh").path, app.path],
                                 env: ["PATH": "/usr/bin:/bin:/usr/sbin", "HOME": base.path])
        expect(ran.status != 0, "21c LOW: \(name): sin checkout real el smoke nunca pasa")
        let rejected = ran.output.contains("no cabe en el perfil de sandbox-exec")
        if name == "plain" {
            expect(!rejected && ran.output.contains("self-test sin control"),
                   "21c LOW: una ruta limpia pasa el guard y cae en el self-test, no en un error cualquiera (\(ran.output))")
        } else {
            expect(rejected, "21c LOW: \(name): ROOT con \" \\ o ) se rechaza con un error claro (\(ran.output))")
        }
    }
}
