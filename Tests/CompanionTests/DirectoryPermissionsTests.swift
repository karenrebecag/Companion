import Foundation
import Testing

@Test @MainActor func directoryPermissionsTests() {
    testCreateDirectoryWith0700Permissions()
}

@MainActor func testCreateDirectoryWith0700Permissions() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-test-\(UUID().uuidString)")

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // When: create a directory with 0o700 permissions
    do {
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    } catch {
        expect(false, "directory creation failed: \(error)")
        return
    }

    // Then: verify the directory has 0o700 permissions
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: tempDir.path),
          let perms = attrs[.posixPermissions] as? NSNumber else {
        expect(false, "could not read directory permissions")
        return
    }

    let mode = perms.uintValue & 0o777
    expectEq(mode, 0o700, "directory permissions should be 0o700")
}
