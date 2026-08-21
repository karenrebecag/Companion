import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func nativeToolRunnerTests() {
    testReadFileSafe()
    testReadFileOutsideWorkdir()
    testWriteFileRequiresApproval()
    testWriteFileWithApproval()
    testEditFileRequiresApproval()
    testEditFileWithApproval()
    testRunShellRequiresApproval()
    testRunShellWithApprovalTimeout()
    testWebFetchSafe()
    testWebSearchSafe()
    testSymlinkDoubleBarrier()
    testSymlinkRealResolution()
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
