import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Darwin
import Foundation
import Testing

// H-7 P8 PR-3. browser_set_files against the fake channel: a refused call
// must not send the upload, and the sheet is built from the lstat and the
// page, never from the arguments the model added.


// MARK: - happy path

@Test func setFilesHappyPathShowsTheVerifiedSheetAndSendsTheResolvedPath() async throws {
    let file = try UploadFile.make(bytes: Data(repeating: 0x61, count: 240 * 1024))
    defer { file.remove() }
    let rig = makeToolRig(page: uploadPage())
    await rig.read()
    let arguments = try uploadArguments(path: file.tilde, decoys: true)
    let judged = try BrowserFilePolicy.judge(file.tilde, home: file.home)

    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "yes, upload it"))
    let fields = try #require(ToolArguments.parse(request.inputJSON))
    expectEq(fields["path"] as? String, judged.path, "la ruta juzgada, no la que escribio el modelo")
    expectEq(fields["host"] as? String, "crm.example", "el host de la pagina")
    expectEq(fields["label"] as? String, "CV", "la etiqueta del elemento")
    let bytes = try #require(fields["bytes"] as? NSNumber)
    expectEq(bytes.int64Value, Int64(240 * 1024), "el tamano del lstat")
    expect(CFGetTypeID(bytes) != CFBooleanGetTypeID(), "un tamano no es un booleano")
    expect(!request.inputJSON.contains("evil.test"), "el host del argumento no entra en la hoja")
    expect(!request.inputJSON.contains("PWNED"), "la etiqueta del argumento no entra")
    expect(!request.inputJSON.contains("~"), "la hoja no muestra la virgulilla")

    let shown = ApprovalCopy.display(for: request, language: .en)
    expect(shown.subject.contains("240 KB"), "240 KiB se lee 240 KB: \(shown.subject)")
    expectEq(shown.trail, "to crm.example", "el host verificado")
    expect(shown.subject != "Upload a file to a page", "no es la hoja de argumentos rotos")
    expect(shown.preview?.contains(judged.path) == true, "el preview nombra el archivo resuelto")
    expect(shown.preview?.contains("CV") == true, "el campo es el de la pagina")
    expect(shown.preview?.contains("PWNED") != true, "no repite la etiqueta inyectada")
    expect(!shown.showsRemember, "subir un archivo no se recuerda")

    rig.runner.granted(request)
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.ok, "subio")
    expect(out.output.contains("uploaded [8]"), "nombra el elemento: \(out.output)")
    expect(!out.output.contains(judged.path), "el resultado no repite la ruta")
    expect(!out.output.contains("files-set"), "no repite el texto de la extension")
    let uploads = rig.channel.sent.filter { if case .setFiles = $0.command { return true }; return false }
    expectEq(uploads.count, 1, "un solo envio")
    expectEq(
        uploads.first?.command,
        .setFiles(tab: 12, generation: 3, element: 8, path: judged.path),
        "manda la ruta resuelta y la generacion leida")
    expectEq(uploads.first?.timeout, .seconds(15), "el mismo plazo que un click")
}

@Test func setFilesAcceptsAFileInputWhoseTypeIsNotLowercase() async throws {
    let (rig, file, arguments) = try await prepared(page: uploadPage(element: webElement(8, "input", "CV", inputType: "FILE")))
    defer { file.remove() }
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") != nil, "type=FILE es un campo de archivo")
}

@Test func setFilesSpokenYesStillAsksAndDoesNotSend() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = rig.runner.approval(for: rig.call(uploadTool, arguments), said: "yes, upload the cv")
    expect(request != nil, "un si hablado sigue siendo una hoja")
    let mark = rig.channel.sent.count
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "sin la hoja concedida no corre: \(out.output)")
    expect(!out.output.contains(BridgeCode.staleId), "no estaba vencido")
    expect(sentSince(rig, mark).filter(isTabsCommand).isEmpty && rig.channel.writes.isEmpty, "no lista ni envia")
}

@Test func setFilesWithoutAGrantStaysApprovalRequired() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let mark = rig.channel.sent.count
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains("approval_required"), "nunca se aprobo: \(out.output)")
    expect(!out.output.contains(BridgeCode.staleId), "la lectura sigue vigente")
    expect(rig.channel.writes.isEmpty && sentSince(rig, mark).filter(isTabsCommand).isEmpty, "no sale del proceso")
}

// MARK: - malformed, before any sheet

@Test func setFilesMalformedArgumentsShowNoSheetAndSendNothing() async throws {
    let file = try UploadFile.make(bytes: Data("x".utf8))
    defer { file.remove() }
    let rig = makeToolRig(page: uploadPage())
    await rig.read()
    let good = try uploadArguments(path: file.tilde)
    expect(rig.runner.approval(for: rig.call(uploadTool, good), said: "") != nil, "el mismo rig si pregunta cuando el argumento sirve")

    let leaked = "LEAKED"
    let long = String(repeating: "a", count: 4097)
    let emoji = String(repeating: "😀", count: 2000)
    let cases: [String] = [
        "not json",
        "{}",
        try uploadArguments(path: "\(leaked)\nfile"),
        try uploadArguments(path: "\(leaked)\u{0}file"),
        try uploadArguments(path: "\(leaked)\rfile"),
        try uploadArguments(path: ""),
        try uploadArguments(path: "   "),
        try uploadArguments(path: long),
        try uploadArguments(path: emoji),
        try uploadArguments(path: 1 as Any),
        try uploadArguments(path: file.tilde, tab: "x"),
        try uploadArguments(path: file.tilde, element: -1),
        try uploadArguments(path: file.tilde, element: "8x"),
        try uploadArguments(path: file.tilde, element: 1.5),
        #"{"element":8,"tab":12}"#,
        #"{"path":"\#(file.tilde)","tab":12}"#,
        #"{"element":8,"path":"\#(file.tilde)"}"#,
    ]
    for arguments in cases {
        expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "sin hoja: \(arguments.prefix(40))")
        let mark = rig.channel.sent.count
        let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
        expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "invalid_args: \(arguments.prefix(40)) -> \(out.output)")
        expect(!out.output.contains(leaked), "el argumento no se repite: \(out.output)")
        expect(sentSince(rig, mark).isEmpty, "un argumento roto no adopta ni envia")
    }
}

// MARK: - gates

@Test func setFilesRefusesWhenTheTabIsNotControlled() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    rig.runner.leases.release(tab: 12)
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "sin control no hay hoja")
    let mark = rig.channel.sent.count
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains(BridgeCode.notControlled), "not_controlled: \(out.output)")
    expect(!sentSince(rig, mark).contains { if case .setFiles = $0 { return true }; return false }, "no envia el archivo")
}

@Test func setFilesRefusesWhenThereIsNoRead() async throws {
    let file = try UploadFile.make(bytes: Data("x".utf8))
    defer { file.remove() }
    let rig = makeToolRig(page: uploadPage())
    let arguments = try uploadArguments(path: file.tilde)
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "sin lectura no hay hoja")
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains(BridgeCode.staleId), "pide leer: \(out.output)")
    expect(!out.output.contains("approval_required"), "no es una aprobacion pendiente")
    expect(rig.channel.writes.isEmpty, "no envia")
}

@Test func setFilesRefusesWhenTheReadIsOlderThanSixtySeconds() async throws {
    let clock = SetFilesClock(Date(timeIntervalSince1970: 1_700_000_000))
    let (rig, file, arguments) = try await prepared(now: { clock.now() })
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    clock.advance(61)
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "la ventana ya cerro")
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains(BridgeCode.staleId), "la ventana es la de la lectura: \(out.output)")
    expect(!out.output.contains("approval_required"), "el ticket de 60 s no alcanza")
    expect(rig.channel.writes.isEmpty, "no envia")
}

@Test func setFilesStillRunsWhenTheReadIsExactlySixtySecondsOld() async throws {
    let clock = SetFilesClock(Date(timeIntervalSince1970: 1_700_000_000))
    let (rig, file, arguments) = try await prepared(now: { clock.now() })
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    clock.advance(60)
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.ok, "60.0 sigue dentro de la ventana: \(out.output)")
}

@Test func setFilesAfterAnotherReadThatReplacedTheFieldIsJudgedAgainstTheNewField() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    rig.channel.setPage(uploadPage(generation: 4, element: webElement(8, "input", "CV", inputType: "text")))
    await rig.read()
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains(BridgeCode.notFileInput), "el numero ya es otro campo: \(out.output)")
    expect(!out.ok && rig.channel.writes.isEmpty, "no envia")
}

@Test func setFilesAfterAnotherReadOfAStillValidFieldNeedsANewSheet() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    rig.channel.setPage(uploadPage(generation: 4))
    await rig.read()
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains("approval_required"), "la hoja era de la generacion anterior: \(out.output)")
    expect(rig.channel.writes.isEmpty, "no envia a la generacion nueva")
    let again = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(again)
    expect(await rig.runner.execute(name: uploadTool, argumentsJSON: arguments).ok, "con la hoja nueva si corre")
}

@Test func setFilesRefusesAnElementThatIsNotAFileInput() async throws {
    let file = try UploadFile.make(bytes: Data("x".utf8))
    defer { file.remove() }
    let framed = BrowserElement(
        id: 8, frame: 1, role: "input", label: "CV", context: "",
        inputType: "file", autocomplete: nil, value: nil)
    let cases: [(String, BrowserElement)] = [
        ("text", webElement(8, "input", "CV", inputType: "text")),
        ("frame", framed),
        ("frame origin", webElement(8, "input", "CV", inputType: "file", frameOrigin: "https://ads.example")),
        ("empty frame origin", webElement(8, "input", "CV", inputType: "file", frameOrigin: "")),
    ]
    for (label, element) in cases {
        let rig = makeToolRig(page: uploadPage(element: element))
        await rig.read()
        let arguments = try uploadArguments(path: file.tilde)
        expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "\(label): sin hoja")
        let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
        expect(out.output.contains(BridgeCode.notFileInput), "\(label): \(out.output)")
        expect(rig.channel.writes.isEmpty, "\(label): no envia")
    }
}

@Test func setFilesRefusesAMissingElementAsStale() async throws {
    let (rig, file, arguments) = try await prepared(page: uploadPage(elements: []))
    defer { file.remove() }
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "sin elemento no hay hoja")
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains(BridgeCode.staleId), "el numero no esta en la lectura: \(out.output)")
    expect(!out.output.contains(BridgeCode.notFileInput), "no es un tipo equivocado")
    expect(rig.channel.writes.isEmpty, "no envia")
}

@Test func setFilesRefusesPathsThePolicyDenies() async throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let folder = "p8-set-files-\(UUID().uuidString)"
    let directory = home.appendingPathComponent(folder, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let hidden = directory.appendingPathComponent(".hidden", isDirectory: true)
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    let pem = directory.appendingPathComponent("secret.pem")
    try Data("x".utf8).write(to: pem)
    let linked = directory.appendingPathComponent("one.txt")
    try Data("x".utf8).write(to: linked)
    try FileManager.default.linkItem(at: linked, to: directory.appendingPathComponent("two.txt"))
    let album = directory.appendingPathComponent("Album.photoslibrary", isDirectory: true)
    try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
    let photo = album.appendingPathComponent("img.jpg")
    try Data("x".utf8).write(to: photo)
    let huge = try UploadFile.sparse(named: "big.bin", bytes: AttachmentPolicy.maxBytes + 1)
    defer { huge.remove() }

    let cases: [(String, String, String)] = [
        ("outside", "/tmp/\(folder).pdf", "denied_path"),
        ("library", "~/Library/\(folder).txt", "denied_path"),
        ("hidden", "~/\(folder)/.hidden/a.txt", "denied_path"),
        ("missing", "~/\(folder)/missing.pdf", "not_found"),
        ("pem", "~/\(folder)/secret.pem", "denied_path"),
        ("link", "~/\(folder)/two.txt", "denied_path"),
        ("photos", "~/\(folder)/Album.photoslibrary/img.jpg", "denied_path"),
        ("huge", huge.tilde, BridgeCode.fileTooLarge),
    ]
    for (label, path, code) in cases {
        let rig = makeToolRig(page: uploadPage())
        await rig.read()
        let arguments = try uploadArguments(path: path)
        expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "\(label): sin hoja")
        let mark = rig.channel.sent.count
        let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
        expect(out.output.contains(code), "\(label): \(out.output)")
        expect(!out.output.contains(folder), "\(label): no repite la ruta")
        expect(sentSince(rig, mark).filter(isTabsCommand).isEmpty && rig.channel.writes.isEmpty, "\(label): no lista ni envia")
    }
}

@Test func setFilesRefusesAPageThatIsNotHttp() async throws {
    let origins = [
        "javascript:alert(LEAKED)",
        "file:///etc/passwd",
        "https://alice:s3cret-LEAKED@crm.example",
    ]
    for origin in origins {
        let (rig, file, arguments) = try await prepared(page: uploadPage(origin: origin))
        defer { file.remove() }
        expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "sin hoja: \(origin.prefix(24))")
        let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
        expect(out.output.contains(BridgeCode.invalidArgs), "\(origin.prefix(24)): \(out.output)")
        expect(out.output.contains("only an http or https page can receive a file"), "no describe el origen")
        expect(!out.output.contains("LEAKED"), "no repite el origen: \(out.output)")
        expect(rig.channel.writes.isEmpty, "no envia")
    }
}

/// Always the ASCII the verified origin gives, with the scheme spelled out
/// whenever it is not https: the sheet must not let http read as https.
@Test func setFilesHostIsAlwaysAsciiAndNamesAnyNonHttpsScheme() async throws {
    let cases: [(String, String)] = [
        ("https://xn--mnchen-3ya.example:8443", "xn--mnchen-3ya.example:8443"),
        ("https://xn--a-8sb.example", "xn--a-8sb.example"),
        ("https://crm.example:443", "crm.example"),
        ("https://crm.example:8443", "crm.example:8443"),
        ("http://crm.example", "http://crm.example"),
        ("http://crm.example:80", "http://crm.example"),
        ("http://crm.example:8080", "http://crm.example:8080"),
        ("HTTP://CRM.example", "http://crm.example"),
    ]
    for (origin, host) in cases {
        let (rig, file, arguments) = try await prepared(page: uploadPage(origin: origin))
        defer { file.remove() }
        guard let request = rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") else {
            Issue.record("no sheet for \(origin)")
            continue
        }
        let fields = try #require(ToolArguments.parse(request.inputJSON))
        expectEq(fields["host"] as? String, host, origin)
        expect(request.summary.hasSuffix(" to \(host)"), "el resumen lleva el mismo host: \(request.summary)")
        let shown = ApprovalCopy.display(for: request, language: .en)
        expectEq(shown.trail, "to \(host)", "la hoja: \(origin)")
    }
}

/// A Unicode host is shown as the punycode the URL resolver gives, never
/// decoded; one that does not resolve to ASCII (a bidi override) gets no sheet.
@Test func setFilesShowsAUnicodeHostAsPunycodeAndRefusesOneThatHasNoAsciiForm() async throws {
    let punycode: [(String, String)] = [
        ("https://m\u{FC}nchen.example", "xn--mnchen-3ya.example"),
        ("https://\u{430}pple.example", "xn--pple-43d.example"),
    ]
    for (origin, host) in punycode {
        let (rig, file, arguments) = try await prepared(page: uploadPage(origin: origin))
        defer { file.remove() }
        let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
        expectEq(ToolArguments.parse(request.inputJSON)?["host"] as? String, host, "punycode, no decodificado")
    }

    let (rig, file, arguments) = try await prepared(page: uploadPage(origin: "https://pay\u{202E}pal.example"))
    defer { file.remove() }
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "un bidireccional no tiene hoja")
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.invalidArgs), "invalid_args: \(out.output)")
    expect(rig.channel.writes.isEmpty, "no envia")
}

// MARK: - identity

@Test func setFilesIdentityChangeBeforeExecuteSendsNothing() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    let bound = try BrowserFilePolicy.judge(file.tilde, home: file.home)
    let moved = try rewriteKeepingMtime(bound.path)
    expect(moved.ctime != bound.ctime, "el fixture movio ctime")
    expectEq(moved.mtime, bound.mtime, "mtime quedo igual")
    expectEq(moved.inode, bound.inode, "el inodo quedo igual")
    expectEq(moved.size, bound.size, "el tamano quedo igual")
    let mark = rig.channel.sent.count
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains("approval_required"), "la aprobacion era de otro archivo: \(out.output)")
    expect(sentSince(rig, mark).isEmpty && rig.channel.writes.isEmpty, "ni lista ni envia")
}

@Test func setFilesIdentityChangeWhileTheTabCheckIsInFlightSendsNoFile() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    let bound = try BrowserFilePolicy.judge(file.tilde, home: file.home)
    let gate = rig.channel.hold(isTabsCommand)
    let task = Task { await rig.runner.execute(name: uploadTool, argumentsJSON: arguments) }
    let inFlight = await gate.waitUntilReached()
    defer { gate.open() }
    expect(inFlight, "la lista de pestanas esta en vuelo")
    let moved = try rewriteKeepingMtime(bound.path)
    expect(moved.ctime != bound.ctime, "ctime se movio durante la lista")
    expectEq(moved.mtime, bound.mtime, "mtime no delata el cambio")
    expectEq(moved.inode, bound.inode, "el inodo tampoco")
    gate.open()
    let out = await task.value
    expect(out.output.contains(BridgeCode.targetChanged), "el segundo lstat ve el ctime: \(out.output)")
    expect(rig.channel.sent.contains { isTabsCommand($0.command) }, "la comprobacion de origen si se hizo")
    expect(rig.channel.writes.isEmpty, "el archivo no se envio")
}

@Test func setFilesDeletedFileIsNotFound() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    try FileManager.default.removeItem(at: file.url)
    let mark = rig.channel.sent.count
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains("not_found"), "borrado: \(out.output)")
    expect(!out.output.contains(BridgeCode.targetChanged), "no es otro archivo")
    expect(sentSince(rig, mark).filter(isTabsCommand).isEmpty && rig.channel.writes.isEmpty, "no envia")
}

@Test func setFilesRefusesWhenTheTabLeftItsOrigin() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    rig.channel.setTabs([BrowserTab(id: 12, title: "Other", url: "https://other.example/", active: false)])
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.output.contains(BridgeCode.staleId), "se fue del origen: \(out.output)")
    expect(rig.channel.writes.isEmpty, "no envia")
    expect(rig.channel.sent.contains { isTabsCommand($0.command) }, "miro la pestana en vivo")
}

@Test func setFilesSurfacesFileAccessRequired() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    rig.channel.failWrites(with: ContractError(code: BridgeCode.fileAccessRequired, message: "Allow access to file URLs"))
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.fileAccessRequired), "el codigo de la extension: \(out.output)")
    expect(out.output.contains("Allow access to file URLs"), "la copia nombra el permiso")
}

@Test func setFilesPathLengthIsCountedInUtf16UnitsAtTheShapeCheck() async throws {
    let limit = ParentToolPolicy.maxInputLength
    let filler = "~/" + String(repeating: "a/", count: (limit - 2) / 2)
    let exact = filler + String(repeating: "b", count: limit - filler.utf16.count)
    expectEq(exact.utf16.count, limit, "el fixture mide justo el tope")
    let rig = makeToolRig(page: uploadPage())
    await rig.read()

    let allowed = try uploadArguments(path: exact)
    let shaped = await rig.runner.execute(name: uploadTool, argumentsJSON: allowed)
    expect(!shaped.output.contains("path is too long"), "justo en el tope pasa la forma: \(shaped.output.prefix(80))")
    expect(!shaped.output.contains(BridgeCode.invalidArgs), "no es un argumento roto: \(shaped.output.prefix(80))")

    let over = try uploadArguments(path: exact + "b")
    expect(rig.runner.approval(for: rig.call(uploadTool, over), said: "") == nil, "sin hoja")
    let refused = await rig.runner.execute(name: uploadTool, argumentsJSON: over)
    expect(refused.output.contains(BridgeCode.invalidArgs) && refused.output.contains("path is too long"),
           "un tope mas es un argumento roto: \(refused.output.prefix(80))")
    expect(rig.channel.writes.isEmpty, "no envia")
}

// MARK: - what the extension answers

@Test(arguments: [
    BridgeCode.notFileInput, BridgeCode.fileTooLarge, BridgeCode.fileAccessRequired,
    BridgeCode.targetChanged, BridgeCode.staleId,
])
func setFilesMapsAnExtensionErrorToItsCodeAndForgetsTheRead(code: String) async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    rig.channel.failWrites(with: ContractError(code: code, message: "EXTENSION-WORDING"))
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(code), "\(code): \(out.output)")
    expect(!out.output.contains("EXTENSION-WORDING"), "\(code): the copy is ours, not the extension's")
    expectEq(uploadsSent(rig), 1, "\(code): the one attempt")
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "\(code): no sheet without a new read")
    let next = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(next.output.contains(BridgeCode.staleId), "\(code): the next call needs a read: \(next.output)")
}

@Test func setFilesTreatsAnySuccessThatIsNotDoneAsABadFrame() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    rig.channel.answerUploads(with: .tabs(id: 1, []))
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.badFrame), "bad_frame: \(out.output)")
    expect(!out.output.contains("uploaded"), "no se anuncia como subido")
}

private func uploadsSent(_ rig: BrowserToolRig) -> Int {
    rig.channel.writes.filter { if case .setFiles = $0 { return true }; return false }.count
}
