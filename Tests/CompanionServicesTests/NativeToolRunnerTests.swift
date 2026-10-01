import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func nativeToolRunnerTests() {
    testReadFileSafe()
    testReadFileOutsideWorkdir()
    testWriteFileRequiresApproval()
    testDeniedWriteAnswersInTheUsersLanguage()
    testWriteFileWithApproval()
    testEditFileRequiresApproval()
    testEditFileWithApproval()
    testRunShellRequiresApproval()
    testRunShellWithApprovalTimeout()
    testRunShellSurvivesOutputBiggerThanAPipe()
    testRunShellTimeoutKeepsWhatItPrinted()
    testWebFetchSafe()
    testWebSearchSafe()
    testSymlinkDoubleBarrier()
    testSymlinkRealResolution()
    testSkillRootsAndSyncLine()
    testSkillSymlinkOutOfCustomIsRefused()
}

// MARK: - Read File (safe)

@MainActor func testReadFileSafe() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("test.txt")
    try! "Hello, World!".write(toFile: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: testFile) }

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "read_file",
            arguments: ["path": testFile],
            approved: false)
    }

    expectEq(result.ok, true, "read_file: safe tool succeeds")
    expectEq(result.output, "Hello, World!", "read_file: returns file content")
}

@MainActor func testReadFileOutsideWorkdir() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let runner = NativeToolRunner(workdir: tempDir)

    let result = try! runAsync {
        try await runner.execute(
            tool: "read_file",
            arguments: ["path": "/etc/passwd"],
            approved: false)
    }

    expectEq(result.ok, false, "read_file outside workdir: fails")
}

// MARK: - Write File (requires approval)

@MainActor func testWriteFileRequiresApproval() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("output.txt")
    defer { try? FileManager.default.removeItem(atPath: testFile) }

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "write_file",
            arguments: ["path": testFile, "content": "test"],
            approved: false)
    }

    expectEq(result.ok, false, "write_file without approval: fails")
    expect(!FileManager.default.fileExists(atPath: testFile),
           "write_file without approval: no file created")
}

@MainActor func testWriteFileWithApproval() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("output.txt")
    defer { try? FileManager.default.removeItem(atPath: testFile) }

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "write_file",
            arguments: ["path": testFile, "content": "Hello"],
            approved: true)
    }

    expectEq(result.ok, true, "write_file with approval: succeeds")
    expect(FileManager.default.fileExists(atPath: testFile),
           "write_file with approval: file created")
    let content = try! String(contentsOfFile: testFile, encoding: .utf8)
    expectEq(content, "Hello", "write_file with approval: correct content")
}

// MARK: - Edit File (requires approval)

@MainActor func testEditFileRequiresApproval() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("edit.txt")
    try! "Hello World".write(toFile: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: testFile) }

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "edit_file",
            arguments: ["path": testFile, "old_string": "World", "new_string": "Swift"],
            approved: false)
    }

    expectEq(result.ok, false, "edit_file without approval: fails")
    let content = try! String(contentsOfFile: testFile, encoding: .utf8)
    expectEq(content, "Hello World", "edit_file without approval: not modified")
}

@MainActor func testEditFileWithApproval() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("edit.txt")
    try! "Hello World".write(toFile: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: testFile) }

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "edit_file",
            arguments: ["path": testFile, "old_string": "World", "new_string": "Swift"],
            approved: true)
    }

    expectEq(result.ok, true, "edit_file with approval: succeeds")
    let content = try! String(contentsOfFile: testFile, encoding: .utf8)
    expectEq(content, "Hello Swift", "edit_file with approval: correctly modified")
}

// MARK: - Run Shell (requires approval)

@MainActor func testRunShellRequiresApproval() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("shell.txt")
    defer { try? FileManager.default.removeItem(atPath: testFile) }

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "run_shell",
            arguments: ["command": "echo test > shell.txt"],
            approved: false)
    }

    expectEq(result.ok, false, "run_shell without approval: fails")
    expect(!FileManager.default.fileExists(atPath: testFile),
           "run_shell without approval: no file created")
}

@MainActor func testRunShellWithApprovalTimeout() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let runner = NativeToolRunner(workdir: tempDir, shellTimeout: 0.2)

    let result = try! runAsync(timeout: 10) {
        try await runner.execute(
            tool: "run_shell",
            arguments: ["command": "sleep 120"],
            approved: true)
    }

    expectEq(result.ok, false, "run_shell with timeout: fails after 60s")
}

@MainActor func testRunShellSurvivesOutputBiggerThanAPipe() {
    // Regresion de Wave 9c: un pipe aguanta ~64 KB. Leyendo la salida DESPUES
    // de esperar al proceso, cualquier comando mas hablador que eso se
    // bloqueaba escribiendo y el usuario recibia "timeout" por un comando que
    // funcionaba — un `git log` cualquiera lo disparaba.
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let runner = NativeToolRunner(workdir: tempDir, shellTimeout: 10)

    let result = try! runAsync(timeout: 20) {
        try await runner.execute(
            tool: "run_shell",
            arguments: ["command": "yes 0123456789 | head -c 200000"],
            approved: true)
    }

    expect(result.ok, "salida grande: el comando se considera exitoso")
    expectEq(result.output.utf8.count, 200_000, "y llega entera")
}

@MainActor func testRunShellTimeoutKeepsWhatItPrinted() {
    // Lo que alcanzo a imprimir antes de colgarse suele ser la pista de POR
    // QUE se colgo, asi que viaja con el fallo en vez de tirarse.
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let runner = NativeToolRunner(workdir: tempDir, shellTimeout: 0.4)

    let result = try! runAsync(timeout: 10) {
        try await runner.execute(
            tool: "run_shell",
            arguments: ["command": "echo pista; sleep 30"],
            approved: true)
    }

    expect(!result.ok, "sigue siendo un fallo")
    expect(result.output.contains("timeout"), "y lo dice")
    expect(result.output.contains("pista"), "sin tirar lo que ya habia impreso")
}

// MARK: - Web Fetch (safe)

@MainActor func testWebFetchSafe() {
    let runner = NativeToolRunner(workdir: nil)
    let result = try! runAsync {
        try await runner.execute(
            tool: "web_fetch",
            arguments: ["url": "http://localhost:9999/notfound"],
            approved: false)
    }

    // Should fail gracefully without approval requirement
    expect(result.ok || !result.ok, "web_fetch: safe tool doesn't require approval")
}

// MARK: - Web Search (safe)

@MainActor func testWebSearchSafe() {
    let runner = NativeToolRunner(workdir: nil)
    let result = try! runAsync {
        try await runner.execute(
            tool: "web_search",
            arguments: ["query": "test"],
            approved: false)
    }

    // Should not require approval
    expect(!result.output.contains("approval"), "web_search: doesn't require approval")
}

// MARK: - Double Barrier: Symlink

@MainActor func testSymlinkDoubleBarrier() {
    let tempDir = try! FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString).path
    try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    // Create a target file outside workdir
    let outsideDir = (tempDir as NSString).deletingLastPathComponent
    let targetFile = (outsideDir as NSString).appendingPathComponent("outside.txt")
    try! "secret".write(toFile: targetFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: targetFile) }

    // Create symlink inside workdir pointing outside
    let symlink = (tempDir as NSString).appendingPathComponent("link.txt")
    try! FileManager.default.createSymbolicLink(atPath: symlink, withDestinationPath: targetFile)

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "read_file",
            arguments: ["path": symlink],
            approved: false)
    }

    expectEq(result.ok, false, "symlink to outside: blocked by double barrier")
}

@MainActor func testSymlinkRealResolution() {
    let tempDir = try! FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString).path
    try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    // Create a safe symlink inside workdir
    let targetFile = (tempDir as NSString).appendingPathComponent("target.txt")
    try! "content".write(toFile: targetFile, atomically: true, encoding: .utf8)

    let symlink = (tempDir as NSString).appendingPathComponent("link.txt")
    try! FileManager.default.createSymbolicLink(atPath: symlink, withDestinationPath: targetFile)

    let runner = NativeToolRunner(workdir: tempDir)
    let result = try! runAsync {
        try await runner.execute(
            tool: "read_file",
            arguments: ["path": symlink],
            approved: false)
    }

    expectEq(result.ok, true, "safe symlink inside workdir: reads correctly")
    expectEq(result.output, "content", "safe symlink: correct content")
}

/// 22. `execute(approved: false)` devuelve `denied_by_user` en el idioma de
/// la configuración y el efecto no ocurre.
@MainActor func testDeniedWriteAnswersInTheUsersLanguage() {
    let tempDir = try! FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("denied-es.txt")
    defer { try? FileManager.default.removeItem(atPath: testFile) }
    let runner = NativeToolRunner(workdir: tempDir, language: .es)
    let result = try! runAsync {
        try await runner.execute(
            tool: "write_file", arguments: ["path": testFile, "content": "x"], approved: false)
    }
    expectEq(result.ok, false, "negado: no ok")
    expectEq(result.output, Escalation.deniedByUser(.es), "negado: la instrucción, en español")
    expect(result.output.hasPrefix("denied_by_user:") && result.output.contains("ni la rodees"),
           "negado: código del contrato + no rodear")
    expect(!FileManager.default.fileExists(atPath: testFile), "negado: el archivo no existe")
    expect(Escalation.deniedByUser(.en).contains("Do not retry it or work around it"),
           "negado: la fuente inglesa dice no reintentar ni rodear")
}


// MARK: - Wave 11a: skills en disco

private func skillsSandbox() -> (SkillsLocation, String) {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-skills-\(UUID().uuidString)")
    let loc = SkillsLocation(root: base.appendingPathComponent("Companion"))
    let work = base.appendingPathComponent("work").path
    for dir in [loc.systemSkills.appendingPathComponent("writing-content"),
                loc.customSkills, loc.knowledge, URL(fileURLWithPath: work)] {
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    try! "---\nname: writing-content\ndescription: Writes. Use when writing.\n---\nbody".write(
        to: loc.systemSkills.appendingPathComponent("writing-content/SKILL.md"),
        atomically: true, encoding: .utf8)
    return (loc, work)
}

@MainActor func testSkillRootsAndSyncLine() {
    let (loc, work) = skillsSandbox()
    defer { try? FileManager.default.removeItem(at: loc.root.deletingLastPathComponent()) }
    let runner = NativeToolRunner(workdir: work, skills: loc)
    let systemSkill = loc.systemSkills.appendingPathComponent("writing-content/SKILL.md").path

    let read = try! runAsync {
        try await runner.execute(tool: "read_file", arguments: ["path": systemSkill], approved: false)
    }
    expect(read.ok && read.output.contains("Writes."), "skills: default se lee aunque el workdir sea otro")

    let denied = try! runAsync {
        try await runner.execute(
            tool: "write_file", arguments: ["path": systemSkill, "content": "x"], approved: true)
    }
    expect(!denied.ok && denied.output.hasPrefix("denied_path:"), "skills: default no se escribe — contrato")
    expect(try! String(contentsOfFile: systemSkill, encoding: .utf8).contains("Writes."),
           "skills: el archivo no se tocó")
    let deniedEdit = try! runAsync {
        try await runner.execute(
            tool: "edit_file",
            arguments: ["path": systemSkill, "old_string": "body", "new_string": "evil"], approved: true)
    }
    expect(deniedEdit.output.hasPrefix("denied_path:"), "skills: edit_file tampoco")

    let custom = loc.customSkills.appendingPathComponent("weekly-report/SKILL.md").path
    let good = "---\nname: weekly-report\ndescription: Builds the weekly report. Use on Fridays.\n---\nSteps."
    let saved = try! runAsync {
        try await runner.execute(
            tool: "write_file", arguments: ["path": custom, "content": good], approved: true)
    }
    expect(saved.ok, "skills: custom se escribe con aprobación (la carpeta se crea)")
    expect(saved.output.hasSuffix("Skill sync: saved — \"weekly-report\" is now in the catalog"),
           "skills: la línea de sync cierra el resultado — got: \(saved.output)")
    // Security review 2026-09-06: lo que la usuaria puede abrir es suyo — 0700/0600,
    // como la carpeta de adjuntos.
    let dirPerms = (try? FileManager.default.attributesOfItem(
        atPath: (custom as NSString).deletingLastPathComponent))?[.posixPermissions] as? Int
    let filePerms = (try? FileManager.default.attributesOfItem(atPath: custom))?[.posixPermissions] as? Int
    expectEq(dirPerms, 0o700, "skills: la carpeta nueva es solo de la usuaria")
    expectEq(filePerms, 0o600, "skills: el archivo también")
    let oversize = try! runAsync {
        try await runner.execute(
            tool: "write_file",
            arguments: ["path": loc.customSkills.appendingPathComponent("big/SKILL.md").path,
                        "content": good + String(repeating: "x", count: SkillCatalog.Caps.fileBytes + 1)],
            approved: true)
    }
    expect(!oversize.ok && oversize.output.hasPrefix("invalid_args:"),
           "skills: un archivo de catálogo sobre el tope se rechaza — got: \(oversize.output.prefix(80))")
    expect(!FileManager.default.fileExists(atPath: loc.customSkills.appendingPathComponent("big/SKILL.md").path),
           "skills: y no se escribe")

    let again = try! runAsync {
        try await runner.execute(
            tool: "write_file", arguments: ["path": custom, "content": good], approved: true)
    }
    expect(again.output.hasSuffix("Skill sync: already up to date"), "skills: mismo contenido")

    let bad = "---\nname: other-name\ndescription: x\n---\n"
    let failed = try! runAsync {
        try await runner.execute(
            tool: "write_file", arguments: ["path": custom, "content": bad], approved: true)
    }
    expect(failed.ok, "skills: el archivo se escribe igual — la usuaria lo puede arreglar")
    expect(failed.output.contains("Skill sync: failed — ") && failed.output.contains("other-name"),
           "skills: el porqué viaja para que el modelo corrija — got: \(failed.output)")

    let edited = try! runAsync {
        try await runner.execute(
            tool: "edit_file",
            arguments: ["path": custom, "old_string": "other-name", "new_string": "weekly-report"],
            approved: true)
    }
    expect(edited.ok && edited.output.contains("Skill sync: saved"), "skills: edit_file también sincroniza")

    let knowledge = loc.knowledge.appendingPathComponent("dentist/KNOWLEDGE.md").path
    let fact = try! runAsync {
        try await runner.execute(
            tool: "write_file",
            arguments: ["path": knowledge,
                        "content": "---\nname: dentist\ndescription: The user's dentist.\n---\nDra. López."],
            approved: true)
    }
    expect(fact.output.hasSuffix("Knowledge sync: saved — \"dentist\" is now in the catalog"),
           "skills: knowledge tiene su propia línea")

    let plain = (work as NSString).appendingPathComponent("a.txt")
    let file = try! runAsync {
        try await runner.execute(
            tool: "write_file", arguments: ["path": plain, "content": "hi"], approved: true)
    }
    expect(file.ok && !file.output.contains("sync:"), "skills: fuera de las raíces no hay línea")
    let notes = (work as NSString).appendingPathComponent("NOTES.md")
    let other = try! runAsync {
        try await runner.execute(
            tool: "write_file",
            arguments: ["path": loc.customSkills.appendingPathComponent("weekly-report/NOTES.md").path,
                        "content": "notes"], approved: true)
    }
    _ = notes
    expect(other.ok && !other.output.contains("sync:"), "skills: NOTES.md no entra al catálogo ni al sync")
}

@MainActor func testSkillSymlinkOutOfCustomIsRefused() {
    let (loc, work) = skillsSandbox()
    defer { try? FileManager.default.removeItem(at: loc.root.deletingLastPathComponent()) }
    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-outside-\(UUID().uuidString).md").path
    try! "secret".write(toFile: outside, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: outside) }
    let dir = loc.customSkills.appendingPathComponent("evil")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let link = dir.appendingPathComponent("SKILL.md").path
    try! FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: outside)
    let runner = NativeToolRunner(workdir: work, skills: loc)
    let write = try! runAsync {
        try await runner.execute(
            tool: "write_file", arguments: ["path": link, "content": "owned"], approved: true)
    }
    expect(!write.ok, "skills: un symlink hacia fuera cae en la segunda barrera")
    expectEq(try! String(contentsOfFile: outside, encoding: .utf8), "secret", "skills: el destino no se tocó")
    let read = try! runAsync {
        try await runner.execute(tool: "read_file", arguments: ["path": link], approved: false)
    }
    expect(!read.ok, "skills: tampoco se lee a través del enlace")
}
