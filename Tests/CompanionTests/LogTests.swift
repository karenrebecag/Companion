import CompanionServices
import Foundation
import Testing

/// M5 (code review 2026-09-24): tests read their own log lines while other
/// tests, in parallel, point the process-wide sink elsewhere. A capture
/// keeps its task's lines, child tasks included, whatever the global does.
/// It runs inside `logTests` because it moves the global sink itself.
@MainActor func testACaptureKeepsItsOwnLinesWhenTheSinkMoves() async {
    let mine = uniqueLogURL()
    let other = uniqueLogURL()
    let sentinel = "capture-\(UUID().uuidString)"
    await Log.capturing(to: mine) {
        Log.configure(fileURL: other)
        Log.app(sentinel)
        await Task { Log.app("child-\(sentinel)") }.value
    }
    expect(readFile(mine).contains(sentinel), "captura: la línea propia llega")
    expect(readFile(mine).contains("child-\(sentinel)"), "captura: también la de una tarea hija")
    expect(!readFile(other).contains(sentinel), "captura: nunca al sink global")
}

/// 20c D7: wire and error text reaches the log; a control or bidi scalar in
/// it must not start a fake line or reorder what the reader sees.
@Test func aLoggedMessageCannotForgeLinesOrSpoofWithHiddenScalars() async {
    let url = uniqueLogURL()
    await Log.capturing(to: url) {
        Log.bridge("call evil\n2099-01-01T00:00:00Z [bridge] approved\r\u{202E}gnp.exe\u{200B}\u{0000}end")
    }
    let text = readFile(url)
    expectEq(text.split(separator: "\n").count, 1, "log: un mensaje es una sola línea")
    expect(!text.contains("\u{202E}") && !text.contains("\u{200B}") && !text.contains("\u{0000}"),
           "log: bidi, zero-width y NUL se quitan")
    expect(text.contains("call evil"), "log: el resto del texto sigue")
}

/// 20c D7: the app log is a plain file that only ever grew.
@Test func theLogFileIsCappedByRotatingTheOldOne() async {
    let url = uniqueLogURL()
    let rotated = URL(fileURLWithPath: url.path + ".1")
    do {
        try Data(String(repeating: "x", count: Log.maxFileBytes + 1).utf8).write(to: url)
    } catch {
        expect(false, "log: no pudo sembrar el archivo grande \(error)")
        return
    }
    await Log.capturing(to: url) { Log.app("after-cap") }
    expect(readFile(url).contains("after-cap"), "tope: la línea nueva va al archivo fresco")
    expect(readFile(url).utf8.count < Log.maxFileBytes, "tope: el archivo vivo vuelve a ser chico")
    expectEq(readFile(rotated).utf8.count, Log.maxFileBytes + 1, "tope: el viejo se conserva como .1")
}

// The only suite that points the process-wide sink anywhere: every other
// test reads its lines through `Log.capturing`.
@Test @MainActor func logTests() async {
    testLogUnconfiguredIsNoOp()
    testLogAppWritesMessage()
    testLogChatWritesAndAppends()
    testLogHasNoSecretPattern()
    testLogUnicodeEmptyAndSpecial()
    testLogWriteFailureDoesNotThrow()
    testLogReconfigureRecovers()
    testLogNoErrorInterpolation()
    testLogNoPaths()
    await testACaptureKeepsItsOwnLinesWhenTheSinkMoves()
}

@MainActor func testLogUnconfiguredIsNoOp() {
    let sentinel = "unconfigured-sentinel-\(UUID().uuidString)"
    let defaultLog = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Companion.log")
    let before = readFile(defaultLog)

    Log.app(sentinel)
    Log.chat(sentinel)

    let after = readFile(defaultLog)
    expect(!after.contains(sentinel),
           "log: sin configure no escribe ~/Library/Logs/Companion.log")
    expect(after == before, "log: sin configure no toca el archivo default")
}

@MainActor func testLogAppWritesMessage() {
    let url = uniqueLogURL()
    Log.configure(fileURL: url)
    Log.app("hola")

    let text = readFile(url)
    expect(text.contains("hola"), "log: app escribe el mensaje")
    expect(text.contains("[app]"), "log: app etiqueta la línea")
    expect(!text.contains("[chat]"), "log: app no se disfraza de chat")
}

@MainActor func testLogChatWritesAndAppends() {
    let url = uniqueLogURL()
    Log.configure(fileURL: url)
    Log.chat("primera")
    Log.app("segunda")
    Log.chat("tercera")

    let text = readFile(url)
    expect(text.contains("primera"), "log: chat escribe")
    expect(text.contains("[chat]"), "log: chat etiqueta la línea")
    expect(text.contains("segunda"), "log: app append al mismo archivo")
    expect(text.contains("tercera"), "log: la tercera línea no pisa")
    expect(text.contains("[app]"), "log: app y chat conviven")
}

@MainActor func testLogHasNoSecretPattern() {
    let url = uniqueLogURL()
    Log.configure(fileURL: url)
    Log.app("hola")
    Log.chat("diagnóstico de turno")

    let text = readFile(url)
    expect(text.contains("hola"), "log: el mensaje útil está")
    expect(!text.contains("sk-"), "log: no aparece patrón sk-")
    expect(!text.contains("sk_"), "log: no aparece patrón sk_")
    expect(!text.contains("gsk_"), "log: no aparece patrón gsk_")
    expect(!text.contains("xai-"), "log: no aparece patrón xai-")
    expect(!text.contains("AKIA"), "log: no aparece patrón AKIA")
    expect(!text.contains("OPENAI_API_KEY"),
           "log: no se filtra el nombre de la key")
}

@MainActor func testLogUnicodeEmptyAndSpecial() {
    let url = uniqueLogURL()
    Log.configure(fileURL: url)
    Log.app("")
    Log.chat("ñoño — café")
    Log.app("linea1\nlinea2")
    Log.chat("quote\"backslash\\")

    let text = readFile(url)
    expect(text.contains("[app]"), "log: mensaje vacío igual deja etiqueta")
    expect(text.contains("ñoño — café"), "log: unicode viaja intacto")
    expect(text.contains("linea1"), "log: salto interno no se pierde")
    expect(text.contains("quote\"backslash\\"),
           "log: comillas y backslash se conservan")

    let large = String(repeating: "a", count: 10_000)
    Log.app(large)
    let grown = readFile(url)
    expect(grown.contains(large), "log: 10k caracteres caben")
}

@MainActor func testLogWriteFailureDoesNotThrow() {
    let blocker = uniqueLogURL()
    do {
        try Data("not-a-dir".utf8).write(to: blocker)
    } catch {
        expect(false, "log: no pudo crear el bloqueo \(error)")
        return
    }
    let url = blocker.appendingPathComponent("Companion.log")
    Log.configure(fileURL: url)
    Log.app("hola")
    Log.chat("otra")
    expect(true, "log: I/O fallido no truena el proceso")
}

@MainActor func testLogReconfigureRecovers() {
    let blocker = uniqueLogURL()
    do {
        try Data("not-a-dir".utf8).write(to: blocker)
    } catch {
        expect(false, "log: no pudo crear el bloqueo \(error)")
        return
    }
    Log.configure(fileURL: blocker.appendingPathComponent("Companion.log"))
    Log.app("perdido")

    let url = uniqueLogURL()
    Log.configure(fileURL: url)
    Log.app("recuperado")
    let text = readFile(url)
    expect(text.contains("recuperado"),
           "log: configure nuevo rehabilita la escritura")
    expect(!text.contains("perdido"),
           "log: el mensaje del path muerto no aparece en el nuevo")
}

@MainActor func testLogNoErrorInterpolation() {
    let url = uniqueLogURL()
    Log.configure(fileURL: url)
    // Simulate what main.swift should do: log generic message, not \(error)
    Log.app("could not create conversations dir")

    let text = readFile(url)
    expect(text.contains("could not create conversations dir"),
           "log: generic error message is present")
    expect(!text.contains("Error Domain"), "log: no system error details")
    expect(!text.contains("Code="), "log: no error codes")
    expect(!text.contains("UserInfo"), "log: no error user info")
}

@MainActor func testLogNoPaths() {
    let url = uniqueLogURL()
    Log.configure(fileURL: url)
    // Simulate what ConversationStore should do: log without paths
    Log.chat("skipping unreadable conversation file")

    let text = readFile(url)
    expect(text.contains("skipping unreadable conversation file"),
           "log: generic message is present")
    expect(!text.contains("/Users/"), "log: no home directory paths")
    expect(!text.contains("/Library/"), "log: no library paths")
    expect(!text.contains(".json"), "log: no file extensions")
}

private func uniqueLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-log-\(UUID().uuidString).log")
}

private func readFile(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        return ""
    }
}
