import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Darwin
import Foundation
import Testing

// Shared fixtures for the browser_set_files tests.

let uploadTool = BrowserTool.setFiles.rawValue

final class SetFilesClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

/// Under the real home: the policy denies /tmp, and the runner judges with
/// `homeDirectoryForCurrentUser`, so a fixture home would not be the one it checks.
struct UploadFile {
    let home: URL
    let directory: URL
    let url: URL
    let tilde: String

    static func make(named: String = "cv.pdf", bytes: Data) throws -> UploadFile {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = "p8-set-files-\(UUID().uuidString)"
        let directory = home.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(named)
        try bytes.write(to: url)
        return UploadFile(home: home, directory: directory, url: url, tilde: "~/\(folder)/\(named)")
    }

    static func sparse(named: String, bytes: Int) throws -> UploadFile {
        let file = try make(named: named, bytes: Data())
        let fd = open(file.url.path, O_RDWR | O_TRUNC)
        defer { close(fd) }
        try #require(fd >= 0)
        try #require(ftruncate(fd, off_t(bytes)) == 0)
        return file
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

func uploadPage(
    origin: String = crm, generation: Int = 3, element: BrowserElement? = nil, elements: [BrowserElement]? = nil
) -> BrowserPage {
    let fields = elements ?? [element ?? webElement(8, "input", "CV", inputType: "file")]
    return BrowserPage(
        tab: 12, origin: origin, url: origin + "/form", title: "Form", text: "",
        generation: generation, elements: fields, truncated: false)
}

func uploadArguments(
    path: Any, tab: Any = 12, element: Any = 8, decoys: Bool = false
) throws -> String {
    var object: [String: Any] = ["element": element, "path": path, "tab": tab]
    if decoys {
        object["bytes"] = 1
        object["host"] = "evil.test"
        object["label"] = "PWNED"
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try #require(String(data: data, encoding: .utf8))
}

func isTabsCommand(_ command: BrowserCommand) -> Bool {
    if case .tabs = command { return true }
    return false
}

func sentSince(_ rig: BrowserToolRig, _ mark: Int) -> [BrowserCommand] {
    rig.channel.sent.dropFirst(mark).map(\.command)
}

func lstatOfUpload(_ path: String) throws -> stat {
    var raw = stat()
    try #require(lstat(path, &raw) == 0)
    return raw
}

/// One byte over one byte, then the original mtime. ctime still moves, which
/// is the only signal an in-place rewrite cannot put back.
@discardableResult
func rewriteKeepingMtime(_ path: String) throws -> BrowserFilePolicy.File {
    let original = try lstatOfUpload(path)
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try handle.write(contentsOf: Data("y".utf8))
    try handle.close()
    var times = [original.st_atimespec, original.st_mtimespec]
    try #require(utimensat(AT_FDCWD, path, &times, 0) == 0)
    return try BrowserFilePolicy.judge(path, home: FileManager.default.homeDirectoryForCurrentUser)
}

func prepared(
    page: BrowserPage = uploadPage(), now: @escaping @Sendable () -> Date = { Date() }
) async throws -> (BrowserToolRig, UploadFile, String) {
    let file = try UploadFile.make(bytes: Data("x".utf8))
    let rig = makeToolRig(page: page, now: now)
    await rig.read()
    let arguments = try uploadArguments(path: file.tilde)
    return (rig, file, arguments)
}
