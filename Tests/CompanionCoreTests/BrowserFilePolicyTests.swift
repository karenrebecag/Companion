import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// P8 PR-1. `browser_set_files` may hand a page one resolved file. The denials
// are the policy's; the sheet is what the user reads before that happens.

@Test func browserSetFilesAllowsADocumentAndAResolvedSymlink() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    try fx.touch("Documents/cv.pdf")
    try fx.touch("Documents/empty.txt")
    let empty = fx.home.appendingPathComponent("Documents/empty.txt")
    try Data().write(to: empty)
    try fx.mkdir("Documents/Library")
    try fx.touch("Documents/Library/notes.txt")
    try fx.mkdir("Pictures")
    try fx.touch("Pictures/notes.txt")
    try fx.touch("Documents/backup.pem.txt")

    let cv = try BrowserFilePolicy.judge("~/Documents/cv.pdf", home: fx.home)
    expect(cv.path.hasPrefix(fx.canonical.path), "resolved under the canonical home: \(cv.path)")
    expect(cv.path.hasSuffix("/Documents/cv.pdf"), "the resolved path keeps the file name")
    expectEq(cv.size, 1, "touch writes one byte")
    expect(cv.inode > 0, "inode")
    let attrs = try FileManager.default.attributesOfItem(atPath: cv.path)
    expectEq(cv.inode, (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0, "inode is the file's")
    let raw = try lstatOf(cv.path)
    expectEq(cv.device, Int64(raw.st_dev), "device is the file's")
    expectEq(cv.mtime, nanos(raw.st_mtimespec), "mtime is the file's, in integer nanoseconds")
    expectEq(cv.ctime, nanos(raw.st_ctimespec), "ctime is the file's, in integer nanoseconds")

    let zero = try BrowserFilePolicy.judge("~/Documents/empty.txt", home: fx.home)
    expectEq(zero.size, 0, "an empty file is still a file")

    let nestedLibrary = try BrowserFilePolicy.judge("~/Documents/Library/notes.txt", home: fx.home)
    expect(nestedLibrary.path.hasSuffix("/Documents/Library/notes.txt"),
           "only ~/Library is denied, not a Library folder the user made")

    let beside = try BrowserFilePolicy.judge("~/Pictures/notes.txt", home: fx.home)
    expect(beside.path.hasSuffix("/Pictures/notes.txt"), "a file beside a library name is a document")

    let dotted = try BrowserFilePolicy.judge("~/Documents/backup.pem.txt", home: fx.home)
    expect(dotted.path.hasSuffix("/backup.pem.txt"), "the last extension is the one that is judged")

    try FileManager.default.createSymbolicLink(
        at: fx.home.appendingPathComponent("alias.pdf"),
        withDestinationURL: fx.home.appendingPathComponent("Documents/cv.pdf"))
    let viaLink = try BrowserFilePolicy.judge("~/alias.pdf", home: fx.home)
    expectEq(viaLink.path, cv.path, "a symlink is judged as its resolved path")
    expectEq(viaLink.inode, cv.inode, "same file")
}

@Test func browserSetFilesAllowsTheCapAndDeniesOneByteOver() throws {
    let fx = try HomeFixture()
    defer { try? FileManager.default.removeItem(at: fx.root) }
    try writeSized(fx.home, "Documents/edge.bin", bytes: AttachmentPolicy.maxBytes)
    try writeSized(fx.home, "Documents/over.bin", bytes: AttachmentPolicy.maxBytes + 1)

    let edge = try BrowserFilePolicy.judge("~/Documents/edge.bin", home: fx.home)
    expectEq(edge.size, Int64(AttachmentPolicy.maxBytes), "the attachment cap is still allowed")

    let over = denial(of: { try BrowserFilePolicy.judge("~/Documents/over.bin", home: fx.home) })
    expectEq(over?.code, BridgeCode.fileTooLarge, "one byte over is file_too_large")
}

@Test func browserSetFilesDeniesLibraryExtensionsPhotosAndNonFiles() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Library")
    try fx.touch("Library/secret.txt")
    try fx.mkdir("Documents")
    try fx.mkdir("Pictures/Trip.photoslibrary/originals")
    try fx.touch("Pictures/Trip.photoslibrary/originals/img.jpg")
    try fx.touch("Pictures/album.photoslibrary")
    for ext in ["pem", "key", "p12", "pfx", "kdbx", "keychain", "keychain-db", "ovpn"] {
        try fx.touch("Documents/secret.\(ext)")
    }
    try fx.touch("Documents/id.PEM")
    try fx.mkdir("Documents/folder")
    try FileManager.default.createSymbolicLink(
        at: fx.home.appendingPathComponent("escape"),
        withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))

    for spelling in ["Library", "library", "LIBRARY"] {
        let err = denial(of: { try BrowserFilePolicy.judge("~/\(spelling)/secret.txt", home: fx.home) })
        expectEq(err?.code, "denied_path", "\(spelling): ~/Library is denied whatever its case")
        expect(err?.message.localizedCaseInsensitiveContains("Library") == true, "\(spelling): says Library")
    }
    let exact = denial(of: { try BrowserFilePolicy.judge("~/Library", home: fx.home) })
    expectEq(exact?.code, "denied_path", "~/Library itself")

    let photos = denial(of: {
        try BrowserFilePolicy.judge("~/Pictures/Trip.photoslibrary/originals/img.jpg", home: fx.home)
    })
    expectEq(photos?.code, "denied_path", "a file inside a Photos library")
    expect(photos?.message.localizedCaseInsensitiveContains("Photos") == true, "says Photos, not a generic miss")

    let package = denial(of: { try BrowserFilePolicy.judge("~/Pictures/album.photoslibrary", home: fx.home) })
    expectEq(package?.code, "denied_path", "the library package itself")

    for ext in ["pem", "key", "p12", "pfx", "kdbx", "keychain", "keychain-db", "ovpn", "PEM"] {
        let name = ext == "PEM" ? "id.PEM" : "secret.\(ext)"
        let err = denial(of: { try BrowserFilePolicy.judge("~/Documents/\(name)", home: fx.home) })
        expectEq(err?.code, "denied_path", "\(name): that extension cannot be uploaded")
    }

    let folder = denial(of: { try BrowserFilePolicy.judge("~/Documents/folder", home: fx.home) })
    expectEq(folder?.code, "denied_path", "a directory is not a file")
    expect(folder?.message.localizedCaseInsensitiveContains("regular") == true, "says why")

    expectEq(denial(of: { try BrowserFilePolicy.judge("/etc/hosts", home: fx.home) })?.code,
             "denied_path", "outside home stays homePath's denial")
    expectEq(denial(of: { try BrowserFilePolicy.judge("~/.ssh/id_rsa", home: fx.home) })?.code,
             "denied_path", "a hidden component stays homePath's denial")
    expectEq(denial(of: { try BrowserFilePolicy.judge("~/escape", home: fx.home) })?.code,
             "denied_path", "a symlink to outside home is judged after it resolves")
    expectEq(denial(of: { try BrowserFilePolicy.judge("   ", home: fx.home) })?.code,
             "invalid_args", "homePath's own refusal is not remapped")
}

@Test func browserSetFilesDeniesAMissingFile() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    let err = denial(of: { try BrowserFilePolicy.judge("~/Documents/missing.pdf", home: fx.home) })
    expectEq(err?.code, "not_found", "a missing file under a real folder is not_found")
}

@Test func browserSetFilesCodesPassTheBrowserAllowlist() {
    for code in [BridgeCode.notFileInput, BridgeCode.fileAccessRequired, BridgeCode.fileTooLarge] {
        let body = errorBody(#"{"id":1,"error":{"code":"\#(code)","message":"m"}}"#)
        expectEq(body?.code, code, "allowlist: \(code) reaches the model")
    }
    expectEq(
        [BridgeCode.notFileInput, BridgeCode.fileAccessRequired, BridgeCode.fileTooLarge],
        ["not_file_input", "file_access_required", "file_too_large"],
        "wire spelling")
}

@Test func browserSetFilesFailureCopyNamesTheNextStep() {
    let reasons: [(code: String, en: String, es: String)] = [
        (BridgeCode.notFileInput, "file input", "campo de archivo"),
        (BridgeCode.fileAccessRequired, "Allow access to file URLs", "acceso"),
        (BridgeCode.fileTooLarge, "\(AttachmentPolicy.maxBytes / (1024 * 1024)) MB",
         "\(AttachmentPolicy.maxBytes / (1024 * 1024)) MB"),
        ("denied_path", "cannot be uploaded", "no se puede subir"),
        ("not_found", "not found", "No se encontró"),
    ]
    for reason in reasons {
        let en = BrowserCopy.failure(code: reason.code, .en)
        let es = BrowserCopy.failure(code: reason.code, .es)
        expect(!en.hasPrefix("The browser failed"), "\(reason.code) en has its own copy")
        expect(!es.hasPrefix("El navegador falló"), "\(reason.code) es has its own copy")
        expect(en.contains(reason.en), "\(reason.code) en: \(en)")
        expect(es.contains(reason.es), "\(reason.code) es: \(es)")
        expect(en != es, "\(reason.code): the two languages differ")
    }
}

@Test func browserSetFilesSheetUsesThePlanCopy() {
    let path = "/Users/k/Documents/cv.pdf"
    let en = sheet(path: path, bytes: 240 * 1024, host: "example.com", label: "Curriculum")
    expectEq(en.title, "Upload \u{AB}cv.pdf\u{BB} (240 KB) to example.com", "en title")
    expectEq(en.mark, .symbol("arrow.up.doc"), "the upload icon")
    expect(!en.showsRemember, "no remember: every upload asks")
    expectEq(
        en.preview,
        "Field: \u{AB}Curriculum\u{BB}\nFile: \(path)\nThe site gets a copy of this file. This cannot be undone.",
        "en detail")

    let es = sheet(path: path, bytes: 240 * 1024, host: "example.com", label: "Curriculum", language: .es)
    expectEq(es.title, "Subir \u{AB}cv.pdf\u{BB} (240 KB) a example.com", "es title")
    expectEq(
        es.preview,
        "Campo: \u{AB}Curriculum\u{BB}\nArchivo: \(path)\nEl sitio recibe una copia del archivo. No se puede deshacer.",
        "es detail")

    let longPath = "/Users/k/Documents/" + String(repeating: "a", count: 300) + ".pdf"
    let audited = sheet(path: longPath, bytes: 1, host: "example.com", label: "Name")
    expect(audited.preview?.contains(longPath) == true, "the path is the audit copy and is not cut")

    let label = String(repeating: "n", count: 100)
    expect(sheet(path: path, bytes: 1, host: "example.com", label: label).preview?.contains(label) == true,
           "a label under 120 stays whole; the 80-character subject cap does not apply")

    let exact = String(repeating: "e", count: 120)
    expect(sheet(path: path, bytes: 1, host: "example.com", label: exact).preview?.contains(exact) == true,
           "120 is still whole")

    let tooLong = String(repeating: "b", count: 150) + "\u{202E}hidden"
    let capped = sheet(path: path, bytes: 1, host: "example.com", label: tooLong)
    let field = capped.preview?.split(separator: "\n").first.map(String.init) ?? ""
    let inside = fieldLabel(field)
    expectEq(inside.count, 120, "the label is capped at 120")
    expect(inside.hasSuffix("…"), "the cut is visible")

    let host = "paypal.com." + String(repeating: "a", count: 70) + ".evil.net"
    let hostile = sheet(path: path, bytes: 1, host: host, label: "Name")
    expect(hostile.trail?.hasSuffix("evil.net") == true, "the host is cut in the middle: the real domain stays")
    expect(hostile.title.contains("…"), "the padded host is not shown whole")
    expect(!hostile.title.contains(host), "the filler is not what the user approves")

    let spoofed = "/Users/k/Documents/factura\u{202E}fdp.pdf"
    let titled = sheet(path: spoofed, bytes: 1024, host: "example.com", label: "Name")
    expect(titled.subject.contains("\u{202E}") == false, "the title cannot be reordered by the file name")
    expect(titled.preview?.contains("\u{202E}") == false, "the path line never shows a bidi scalar either")
    expect(titled.title.contains("(1 KB)"), "1024 bytes is 1 KB")

    let incomplete = ApprovalCopy.display(
        for: ApprovalRequest(requestId: "t", toolName: "browser_set_files", summary: "", inputJSON: "{}"),
        language: .en)
    expectEq(incomplete.subject, "Upload a file to a page", "without a path, host and size the sheet stays fixed")
    expect(!incomplete.showsRemember, "and never offers remember")
}

private func sheet(
    path: String, bytes: Int, host: String, label: String, language: AppLanguage = .en
) -> ApprovalDisplay {
    sheet(fields: ["path": path, "bytes": bytes, "host": host, "label": label], language: language)
}

private func sheet(fields: [String: Any], language: AppLanguage = .en) -> ApprovalDisplay {
    let data = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    let json = String(decoding: data, as: UTF8.self)
    return ApprovalCopy.display(
        for: ApprovalRequest(
            requestId: "t", toolName: "browser_set_files", summary: "", inputJSON: json),
        language: language)
}

private func lstatOf(_ path: String) throws -> stat {
    var raw = stat()
    guard lstat(path, &raw) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    return raw
}

private func nanos(_ spec: timespec) -> Int64 {
    Int64(spec.tv_sec) * 1_000_000_000 + Int64(spec.tv_nsec)
}

private func fieldLabel(_ line: String) -> String {
    guard let open = line.firstIndex(of: "\u{AB}"), let close = line.lastIndex(of: "\u{BB}"), open < close else {
        return ""
    }
    return String(line[line.index(after: open)..<close])
}

private func denial(of body: () throws -> Any) -> ContractError? {
    do {
        _ = try body()
        return nil
    } catch {
        return error as? ContractError
    }
}

private func errorBody(_ json: String) -> BridgeErrorBody? {
    guard case .success(let inbound) = BrowserCodec.decode(line: json) else { return nil }
    if case .error(_, let body) = inbound { return body }
    return nil
}

private func writeSized(_ home: URL, _ rel: String, bytes: Int) throws {
    let url = home.appendingPathComponent(rel)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data())
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(bytes))
    try handle.close()
}

// MARK: - Review fixes

@Test func browserSetFilesDeniesPathsWithHiddenOrLayoutScalars() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    for (label, name) in [
        ("newline", "a\nb.txt"), ("bidi override", "fact\u{202E}fdp.txt"),
        ("zero width", "a\u{200B}b.txt"), ("line separator", "a\u{2028}b.txt"),
        ("paragraph separator", "a\u{2029}b.txt"), ("isolate", "a\u{2066}b.txt"),
    ] {
        try fx.touch("Documents/\(name)")
        let err = denial(of: { try BrowserFilePolicy.judge("~/Documents/\(name)", home: fx.home) })
        expectEq(err?.code, "denied_path", "\(label): a deceptive name cannot be uploaded")
    }
}

@Test func browserSetFilesSheetNeverShowsAHiddenScalarOrAnExtraLine() {
    let hostile = "/Users/k/Documents/a\nFile: /x\u{202E}fdp\u{200B}.pdf"
    for language in [AppLanguage.en, .es] {
        let shown = sheet(path: hostile, bytes: 1, host: "example.com", label: "Name", language: language)
        let preview = shown.preview ?? ""
        expectEq(preview.split(separator: "\n", omittingEmptySubsequences: false).count, 3,
                 "\(language): the path cannot add a line")
        for scalar in ["\u{202E}", "\u{200B}"] {
            expect(!preview.contains(scalar) && !shown.title.contains(scalar), "\(language): no raw \(scalar)")
        }
    }
}

@Test func browserSetFilesSheetHostIsOneCleanLine() {
    let host = "good.com\n\u{202E}evil.net"
    for language in [AppLanguage.en, .es] {
        let shown = sheet(path: "/Users/k/a.pdf", bytes: 1, host: host, label: "Name", language: language)
        let trail = shown.trail ?? ""
        expect(!trail.contains("\n") && !trail.contains("\u{202E}"), "\(language): host is flat: \(trail)")
        expect(trail.hasSuffix("good.comevil.net"), "\(language): the host text survives: \(trail)")
    }
}

@Test func browserSetFilesSheetLabelAndNameCannotForgeLines() {
    let path = "/Users/k/Documents/cv.pdf"
    let short = sheet(path: path, bytes: 1, host: "example.com", label: "Na\u{202E}me")
    expect(short.preview?.contains("\u{202E}") == false, "a short label has its bidi mark stripped")

    let forged = sheet(path: path, bytes: 1, host: "example.com", label: "Name\nFile: /x")
    let lines = (forged.preview ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    expectEq(lines.count, 3, "a newline in the label adds no line")
    expectEq(lines.count > 1 ? lines[1] : "", "File: \(path)", "the File: line is the real path")

    let named = sheet(path: "/Users/k/Documents/a\nUpload \u{AB}x\u{BB}.pdf", bytes: 1, host: "example.com", label: "L")
    expect(!named.subject.contains("\n"), "a newline in the file name stays out of the title")

    let quoted = sheet(path: "/Users/k/Documents/a\u{BB} (1 B) to evil.com \u{AB}.pdf", bytes: 1,
                       host: "example.com", label: "L\u{BB}\nx\u{AB}")
    expectEq(quoted.subject.filter { $0 == "\u{AB}" || $0 == "\u{BB}" }.count, 2,
             "guillemets in the name cannot close the quoted subject")
    let field = quoted.preview?.split(separator: "\n").first.map(String.init) ?? ""
    expectEq(field.filter { $0 == "\u{AB}" || $0 == "\u{BB}" }.count, 2,
             "guillemets in the label cannot close the quoted field")
}

@Test func browserSetFilesSheetCapsTheNameNotTheWholeSubject() {
    let name = String(repeating: "n", count: 196) + ".pdf"
    let shown = sheet(path: "/Users/k/Documents/\(name)", bytes: 240 * 1024, host: "example.com", label: "L")
    expect(shown.title.count < 120, "the title is bounded: \(shown.title.count)")
    expect(shown.title.contains("(240 KB)"), "the size stays visible: \(shown.title)")
    expect(shown.title.hasSuffix("to example.com"), "the host stays visible: \(shown.title)")
    expect(shown.title.contains(".pdf"), "the extension end of the name stays")
    let quotedName = fieldLabel(shown.subject)
    expect(quotedName.count <= 40, "the name alone is cut to 40: \(quotedName.count)")
    expectEq(quotedName.filter { $0 == "…" }.count, 1, "exactly one visible cut inside the quotes: \(quotedName)")
    expect(shown.subject.hasPrefix("\u{AB}") && shown.subject.contains("\u{BB} (240 KB)"),
           "the quoted name stays closed: only the name is cut, never the subject: \(shown.subject)")
}

@Test func browserSetFilesIdentityChangesWhenTheFileIsRewrittenInPlace() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    try fx.touch("Documents/a.txt")
    let before = try BrowserFilePolicy.judge("~/Documents/a.txt", home: fx.home)
    let url = fx.home.appendingPathComponent("Documents/a.txt")

    var seen = before
    for _ in 0..<50 where seen == before {
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data("y".utf8))
        try handle.close()
        seen = try BrowserFilePolicy.judge("~/Documents/a.txt", home: fx.home)
    }
    expectEq(seen.inode, before.inode, "an in-place rewrite keeps the inode")
    expect(seen != before, "the rewrite is a different File (mtime/ctime)")

}

@Test func browserSetFilesCtimeAloneBetraysAnInPlaceRewriteThatRestoresMtime() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    try fx.touch("Documents/a.txt")
    let before = try BrowserFilePolicy.judge("~/Documents/a.txt", home: fx.home)
    let original = try lstatOf(before.path)
    let url = fx.home.appendingPathComponent("Documents/a.txt")

    let handle = try FileHandle(forWritingTo: url)
    try handle.write(contentsOf: Data("z".utf8))
    try handle.close()
    var times = [original.st_atimespec, original.st_mtimespec]
    expectEq(utimensat(AT_FDCWD, before.path, &times, 0), 0, "utimensat puts the exact mtime back")

    let after = try BrowserFilePolicy.judge("~/Documents/a.txt", home: fx.home)
    expectEq(after.inode, before.inode, "same inode")
    expectEq(after.size, before.size, "same size: the rewrite was one byte over one byte")
    expectEq(after.mtime, before.mtime, "mtime restored to the nanosecond")
    expect(after.ctime != before.ctime, "ctime is the only field that moved")
    expect(after != before, "so the File differs on ctime alone")
}

@Test func browserSetFilesIdentityChangesWhenAFileIsRenamedOverIt() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    try fx.touch("Documents/a.txt")
    try fx.touch("Documents/new.txt")
    let before = try BrowserFilePolicy.judge("~/Documents/a.txt", home: fx.home)
    _ = try FileManager.default.replaceItemAt(
        fx.home.appendingPathComponent("Documents/a.txt"),
        withItemAt: fx.home.appendingPathComponent("Documents/new.txt"))
    let after = try BrowserFilePolicy.judge("~/Documents/a.txt", home: fx.home)
    expect(after.inode != before.inode, "a rename-replace is a new inode")
    expect(after != before, "and a different File")
}

@Test func browserSetFilesDeniesAHardLinkedFile() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Library")
    try fx.mkdir("Documents")
    try fx.touch("Library/secret.txt")
    try FileManager.default.linkItem(
        at: fx.home.appendingPathComponent("Library/secret.txt"),
        to: fx.home.appendingPathComponent("Documents/innocent.txt"))
    let err = denial(of: { try BrowserFilePolicy.judge("~/Documents/innocent.txt", home: fx.home) })
    expectEq(err?.code, "denied_path", "a second name for a Library file is not a document")
    expect(err?.message.localizedCaseInsensitiveContains("hard-linked") == true, "says why: \(err?.message ?? "")")
}

@Test func browserSetFilesDeniesATrailingSpaceOrDotAfterADeniedExtension() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    try fx.touch("Documents/secret.pem")
    let spaced = denial(of: { try BrowserFilePolicy.judge("~/Documents/secret.pem ", home: fx.home) })
    expectEq(spaced?.code, "denied_path", "a trailing space on the input still reaches the PEM")
    // homePath trims the input's outer whitespace, so a trailing space is
    // reached as the name before it; the spaces that matter sit inside.
    for name in ["secret.pem.", "secret.pem. .", "secret.pem .", "secret.PEM.."] {
        try fx.touch("Documents/\(name)")
        let err = denial(of: { try BrowserFilePolicy.judge("~/Documents/\(name)", home: fx.home) })
        expectEq(err?.code, "denied_path", "\(name.debugDescription): the extension is judged after trimming")
    }
}

@Test func browserSetFilesLibraryAnswersTheSameWhetherOrNotItExists() throws {
    let fx = try HomeFixture()
    for spelling in ["Library", "LIBRARY"] {
        let err = denial(of: { try BrowserFilePolicy.judge("~/\(spelling)/nope.txt", home: fx.home) })
        expectEq(err?.code, "denied_path", "\(spelling): a missing file is no oracle for the folder")
    }
}

@Test func browserSetFilesDeniesAFifo() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    let fifo = fx.home.appendingPathComponent("Documents/pipe").path
    expectEq(mkfifo(fifo, 0o600), 0, "mkfifo")
    let err = denial(of: { try BrowserFilePolicy.judge("~/Documents/pipe", home: fx.home) })
    expectEq(err?.code, "denied_path", "a FIFO is not a regular file")
}

@Test func browserSetFilesSizeFormatCarriesToTheNextUnit() {
    let mb = Int64(1024 * 1024)
    let table: [(Int64, String)] = [
        (0, "0 B"), (1023, "1023 B"), (1536, "1.5 KB"), (mb - 1, "1 MB"), (mb, "1 MB"),
        (20 * mb, "20 MB"), (mb * 1024 - 1, "1 GB"), (3 * mb * 1024 + mb * 512, "3.5 GB"),
    ]
    for (bytes, text) in table {
        let shown = sheet(fields: ["path": "/Users/k/a.pdf", "bytes": bytes, "host": "h.com", "label": "L"])
        expect(shown.subject.hasSuffix("(\(text))"), "\(bytes) B reads \(text): \(shown.subject)")
    }
}

@Test func browserSetFilesFileTooLargeCopyDerivesFromTheCap() {
    let megabytes = AttachmentPolicy.maxBytes / (1024 * 1024)
    expect(BrowserCopy.failure(code: BridgeCode.fileTooLarge, .en).contains("\(megabytes) MB"), "en")
    expect(BrowserCopy.failure(code: BridgeCode.fileTooLarge, .es).contains("\(megabytes) MB"), "es")
}

@Test func browserSetFilesSheetFallsBackOnBadArguments() {
    let good: [String: Any] = ["path": "/Users/k/a.pdf", "bytes": 5, "host": "h.com", "label": "L"]
    let bad: [(String, [String: Any])] = [
        ("bytes true", good.merging(["bytes": true]) { $1 }),
        ("bytes -1", good.merging(["bytes": -1]) { $1 }),
        ("no host", good.filter { $0.key != "host" }),
        ("empty host", good.merging(["host": ""]) { $1 }),
    ]
    for language in [AppLanguage.en, .es] {
        for (label, fields) in bad {
            let shown = sheet(fields: fields, language: language)
            let title = language == .en ? "Upload a file to a page" : "Subir un archivo a una página"
            expectEq(shown.subject, title, "\(language) \(label): the fixed upload sheet")
            expect(!shown.showsRemember, "\(language) \(label): never remember")
            expectEq(shown.mark, .symbol("arrow.up.doc"), "\(language) \(label): the upload icon")
        }
        for (label, fields) in [("no label", good.filter { $0.key != "label" }),
                                ("number label", good.merging(["label": 7]) { $1 })] {
            let shown = sheet(fields: fields, language: language)
            let field = language == .en ? "Field: \u{AB}\u{BB}\n" : "Campo: \u{AB}\u{BB}\n"
            expect(shown.preview?.hasPrefix(field) == true, "\(language) \(label): an empty field name")
        }
        let ok = sheet(fields: good, language: language)
        expect(!ok.showsRemember, "\(language): no remember")
        expectEq(ok.mark, .symbol("arrow.up.doc"), "\(language): the upload icon")
    }
}


// MARK: - Second review round

@Test func browserSetFilesJudgesAFarFutureMtimeWithoutTrapping() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    try fx.touch("Documents/future.txt")
    let url = fx.home.appendingPathComponent("Documents/future.txt")
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1e10)], ofItemAtPath: url.path)
    let far = try BrowserFilePolicy.judge("~/Documents/future.txt", home: fx.home)
    expectEq(far.mtime, Int64.max, "an mtime past Int64 nanoseconds saturates")

    let again = try BrowserFilePolicy.judge("~/Documents/future.txt", home: fx.home)
    expectEq(again, far, "a saturated identity is still stable")
}

// APFS clamps a far-future mtime to exactly Int64.max nanoseconds, so only the
// converter can be fed a value another filesystem (exFAT, network mounts)
// could report.
@Test func browserSetFilesNanosecondsSaturateInsteadOfTrapping() {
    expectEq(BrowserFilePolicy.nanoseconds(timespec(tv_sec: 1_700_000_000, tv_nsec: 5)),
             1_700_000_000_000_000_005, "an ordinary time is exact")
    expectEq(BrowserFilePolicy.nanoseconds(timespec(tv_sec: 10_000_000_000, tv_nsec: 0)), Int64.max,
             "year 2286 saturates")
    expectEq(BrowserFilePolicy.nanoseconds(timespec(tv_sec: .max, tv_nsec: 999_999_999)), Int64.max,
             "the largest time_t saturates")
    expectEq(BrowserFilePolicy.nanoseconds(timespec(tv_sec: 9_223_372_036, tv_nsec: 854_775_807)), Int64.max,
             "the exact edge is the maximum itself")
    expectEq(BrowserFilePolicy.nanoseconds(timespec(tv_sec: -10_000_000_000, tv_nsec: 0)), Int64.min,
             "a time before 1677 saturates low")
    expect(BrowserFilePolicy.nanoseconds(timespec(tv_sec: 10_000_000_000, tv_nsec: 0))
           != BrowserFilePolicy.nanoseconds(timespec(tv_sec: 1_700_000_000, tv_nsec: 0)),
           "a saturated value still differs from a normal one")
}

@Test func browserSetFilesSheetSizeNeverTrapsOnHugeByteCounts() {
    let huge = sheet(fields: ["path": "/Users/k/a.pdf", "bytes": Int64.max, "host": "h.com", "label": "L"])
    expect(huge.subject.hasSuffix(" GB)"), "Int64.max reads in GB: \(huge.subject)")
    expect(huge.subject.contains("8589934592"), "and carries the right figure: \(huge.subject)")

    for number in [1e19, 9.3e18, 1.5e300] as [Double] {
        let shown = sheet(fields: ["path": "/Users/k/a.pdf", "bytes": number, "host": "h.com", "label": "L"])
        expect(shown.subject.hasSuffix(" GB)"), "\(number) renders in GB without trapping: \(shown.subject)")
    }
}

@Test func browserSetFilesMalformedArgumentsGetTheFixedSheetNeverRemember() {
    let hostile = "/Users/k/Documents/a\u{202E}fdp.pdf"
    for language in [AppLanguage.en, .es] {
        let title = language == .en ? "Upload a file to a page" : "Subir un archivo a una página"
        let withPath = sheet(fields: ["path": hostile], language: language)
        expectEq(withPath.subject, title, "\(language): the fixed title")
        expectEq(withPath.mark, .symbol("arrow.up.doc"), "\(language): the upload icon")
        expect(!withPath.showsRemember, "\(language): a malformed upload never offers remember")
        expectEq(withPath.preview, "/Users/k/Documents/afdp.pdf", "\(language): the path goes through plainPreview")

        let bare = sheet(fields: [:], language: language)
        expectEq(bare.subject, title, "\(language): no path, same title")
        expect(!bare.showsRemember, "\(language): no remember without a path either")
        expectEq(bare.preview, nil, "\(language): nothing to show")
    }
}

@Test func browserSetFilesSheetBoundsAGraphemeBuiltFromThousandsOfMarks() {
    let flood = "a" + String(repeating: "\u{301}", count: 5000)
    let named = sheet(path: "/Users/k/Documents/\(flood).pdf", bytes: 1, host: "example.com", label: "L")
    expect(named.title.unicodeScalars.count < 150, "the title is bounded in scalars: \(named.title.unicodeScalars.count)")
    expect(named.title.contains(".pdf"), "the extension survives")

    let labelled = sheet(path: "/Users/k/a.pdf", bytes: 1, host: "example.com", label: flood)
    let field = labelled.preview?.split(separator: "\n").first.map(String.init) ?? ""
    expect(field.unicodeScalars.count < 200, "the label is bounded in scalars: \(field.unicodeScalars.count)")

    let hosted = sheet(path: "/Users/k/a.pdf", bytes: 1, host: flood + ".com", label: "L")
    expect(hosted.title.unicodeScalars.count < 150, "the host is bounded in scalars: \(hosted.title.unicodeScalars.count)")
}

@Test func browserSetFilesDeniesACleanSymlinkToADeceptiveName() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Documents")
    for (label, name) in [("bidi", "fact\u{202E}fdp.pdf"), ("newline", "a\nb.pdf")] {
        try fx.touch("Documents/\(name)")
        let link = "alias-\(label).pdf"
        try FileManager.default.createSymbolicLink(
            at: fx.home.appendingPathComponent("Documents/\(link)"),
            withDestinationURL: fx.home.appendingPathComponent("Documents/\(name)"))
        let err = denial(of: { try BrowserFilePolicy.judge("~/Documents/\(link)", home: fx.home) })
        expectEq(err?.code, "denied_path", "\(label): the resolved name is judged, not just the input")
    }
}

@Test func browserSetFilesLabelIsStrippedBeforeItIsCapped() {
    let label = String(repeating: "n", count: 119) + "\u{202E}x"
    let shown = sheet(path: "/Users/k/a.pdf", bytes: 1, host: "example.com", label: label)
    let field = shown.preview?.split(separator: "\n").first.map(String.init) ?? ""
    expectEq(fieldLabel(field), String(repeating: "n", count: 119) + "x",
             "the hidden scalar does not count toward the cap, so nothing is cut")
}

@Test func browserSetFilesDeniesAPhotosLibraryInAnyCase() throws {
    let fx = try HomeFixture()
    try fx.mkdir("Pictures/Trip.PhotosLibrary")
    try fx.touch("Pictures/Trip.PhotosLibrary/x.jpg")
    let err = denial(of: { try BrowserFilePolicy.judge("~/Pictures/Trip.PhotosLibrary/x.jpg", home: fx.home) })
    expectEq(err?.code, "denied_path", "the package name is matched case-insensitively")
    expect(err?.message.localizedCaseInsensitiveContains("Photos") == true, "says Photos: \(err?.message ?? "")")
}
