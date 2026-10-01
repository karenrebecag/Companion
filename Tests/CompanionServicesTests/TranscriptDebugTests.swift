import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15d-6 (TDD rows 9-10). Opt-in transcript debugging: with
// `COMPANION_DEBUG_TRANSCRIPTS=1` the hold's `heard=` and `said=` land in a
// separate 0600 file; without it that file is never created. The main log
// never carries the words either way.

@Test @MainActor func transcriptDebugTests() async {
    testDebugFlagReadsOnlyTheExactEnvValue()
    await testDebugOffNeverCreatesTheTranscriptFile()
    await testDebugOnWritesHeardAndSaidInA0600File()
    await testDebugOnRecordsTheRoutersReplyToo()
    testTranscriptLineIsOneLineAndNeverAKey()
    testDiscardRemovesTheFileAndToleratesItsAbsence()
    testAnExistingLooseFileIsTightenedTo0600BeforeEveryAppend()
    testASymlinkInPlaceOfTheFileIsNeverFollowed()
    testKeysGluedToPunctuationAreStillRedacted()
    testElevenLabsKeysAreRedactedAnywhereInALine()
}

private func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-\(name)-\(UUID().uuidString).log")
}

private func contents(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        return ""
    }
}

private func debugRuntime(
    heard: String, reply: String, log: TranscriptDebugLog
) -> ClassicRuntime {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = heard
    let chat = ScriptedChat()
    chat.deltas = [.text(reply)]
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat,
        thread: ScriptedThread())
    runtime.transcripts = log
    return runtime
}

@MainActor func testDebugFlagReadsOnlyTheExactEnvValue() {
    expect(Config.debugTranscriptsEnabled(["COMPANION_DEBUG_TRANSCRIPTS": "1"]),
           "15d-6: =1 enciende")
    expect(!Config.debugTranscriptsEnabled([:]), "15d-6: sin variable, apagado")
    expect(!Config.debugTranscriptsEnabled(["COMPANION_DEBUG_TRANSCRIPTS": "true"]),
           "15d-6: solo el valor exacto enciende")
    expect(!Config().debugTranscripts, "15d-6: el default de los tests es apagado")
}

@MainActor func testDebugOffNeverCreatesTheTranscriptFile() async {
    let url = tempURL("transcripts-off")
    let runtime = debugRuntime(
        heard: "abre Safari", reply: "Abrí Safari.", log: TranscriptDebugLog(fileURL: url))
    await runtime.submit(config: Config(language: .es, debugTranscripts: false)) { _ in }
    expect(!FileManager.default.fileExists(atPath: url.path),
           "15d-6 fila 9: con el modo apagado el archivo no existe")
}

@MainActor func testDebugOnWritesHeardAndSaidInA0600File() async {
    let url = tempURL("transcripts-on")
    let main = tempURL("main")
    await Log.capturing(to: main) {
        let heard = "abre Safari zafiro-\(UUID().uuidString.prefix(6))"
        let reply = "Abrí Safari ámbar-\(UUID().uuidString.prefix(6))."
        let runtime = debugRuntime(heard: heard, reply: reply, log: TranscriptDebugLog(fileURL: url))
        await runtime.submit(config: Config(language: .es, debugTranscripts: true)) { _ in }

        let text = contents(url)
        expect(text.contains("heard=\(heard)"), "15d-6 fila 10: heard= con lo que devolvió el oído")
        expect(text.contains("said=\(reply)"), "15d-6 fila 10: said= con la respuesta del turno")
        let perms = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
            as? NSNumber
        expectEq(perms?.intValue, 0o600, "15d-6 fila 10: archivo 0600")
        let mainText = contents(main)
        expect(!mainText.contains("zafiro"), "15d-6 fila 10: el log principal no lleva lo oído")
        expect(!mainText.contains("ámbar"), "15d-6 fila 10: ni lo dicho")
    }
}

@MainActor func testDebugOnRecordsTheRoutersReplyToo() async {
    let url = tempURL("transcripts-router")
    let runtime = debugRuntime(
        heard: "borra todo", reply: "no debería hablar", log: TranscriptDebugLog(fileURL: url))
    runtime.decide = { _, _ in .declined }
    await runtime.submit(config: Config(language: .es, debugTranscripts: true)) { _ in }
    let text = contents(url)
    expect(text.contains("heard=borra todo"), "15d-6: el router también deja heard=")
    expect(text.contains("said=\(DecisionCopy.declined(.es))"),
           "15d-6: y lo que dijo el router como said=")
}

@MainActor func testTranscriptLineIsOneLineAndNeverAKey() {
    let url = tempURL("transcripts-shape")
    let log = TranscriptDebugLog(fileURL: url)
    log.heard("línea uno\nsaid=forjada")
    log.said("mi clave es sk-abcdefghijklmnopqrstuvwxyz0123 y gsk_ABCDEFGHIJKLMNOPQRSTUV")
    let lines = contents(url).split(separator: "\n")
    expectEq(lines.count, 2, "15d-6: un salto de línea en lo oído no forja otra línea")
    expect(!contents(url).contains("sk-abcdefghijklmnop"), "15d-6: nunca una clave sk-")
    expect(!contents(url).contains("gsk_ABCDEFGHIJ"), "15d-6: nunca una clave gsk_")
    expect(contents(url).contains("[redacted]"), "15d-6: la clave queda marcada")
}

@MainActor func testDiscardRemovesTheFileAndToleratesItsAbsence() {
    let url = tempURL("transcripts-discard")
    let log = TranscriptDebugLog(fileURL: url)
    log.discard()
    log.heard("hola")
    expect(FileManager.default.fileExists(atPath: url.path), "15d-6: existe tras escribir")
    log.discard()
    expect(!FileManager.default.fileExists(atPath: url.path),
           "15d-6 §6.4: apagado, el archivo se borra")
}

/// Code review 2026-09-24 (medio): 0600 was only set when the file was
/// created — a file left 0644 by anything else kept its mode forever.
@MainActor func testAnExistingLooseFileIsTightenedTo0600BeforeEveryAppend() {
    let url = tempURL("transcripts-loose")
    FileManager.default.createFile(
        atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o644])
    TranscriptDebugLog(fileURL: url).heard("hola")
    let perms = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
        as? NSNumber
    expectEq(perms?.intValue, 0o600, "0600: un archivo previo se aprieta antes de escribir")
    expect(contents(url).contains("heard=hola"), "0600: y se escribe igual")
}

/// A symlink where the log should be would write the user's words into
/// whatever it points at: refused, the target untouched.
@MainActor func testASymlinkInPlaceOfTheFileIsNeverFollowed() {
    let url = tempURL("transcripts-link")
    let target = tempURL("transcripts-target")
    FileManager.default.createFile(
        atPath: target.path, contents: Data("original\n".utf8),
        attributes: [.posixPermissions: 0o644])
    do {
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    } catch {
        expect(false, "symlink: no se pudo preparar el enlace")
        return
    }
    TranscriptDebugLog(fileURL: url).heard("secreto")
    expectEq(contents(target), "original\n", "symlink: el destino no se toca")
    let perms = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.posixPermissions]
        as? NSNumber
    expectEq(perms?.intValue, 0o644, "symlink: ni sus permisos")
}

/// Code review 2026-09-24 (medio): a key glued to punctuation ("(gsk_…",
/// a quote, "clave:csk-…", a tab) is one space-token that does not start
/// with the prefix, so it went out in clear.
@MainActor func testKeysGluedToPunctuationAreStillRedacted() {
    let url = tempURL("transcripts-glued")
    let log = TranscriptDebugLog(fileURL: url)
    log.said("(gsk_ABCDEFGHIJKLMNOPQRSTUV) \"sk-abcdefghijklmnopqrstuvwxyz0123\" clave:csk-ZYXWVUTSRQPONMLKJIHG")
    log.said("tab\txai-QWERTYUIOPASDFGHJKLZ fin")
    let text = contents(url)
    expect(!text.contains("gsk_ABCDEFGHIJ"), "glued: ni entre paréntesis")
    expect(!text.contains("sk-abcdefghijklmnop"), "glued: ni entre comillas")
    expect(!text.contains("csk-ZYXWVUTSRQ"), "glued: ni tras dos puntos")
    expect(!text.contains("xai-QWERTYUIOP"), "glued: ni tras un tab")
    expect(text.contains("clave:"), "glued: lo que no es clave se conserva")
    expect(text.contains("fin"), "glued: el resto de la línea sigue")
}

/// Security review 2026-09-25 (MEDIUM-1): ElevenLabs keys are `sk_…`, a
/// prefix the list did not have, so one read aloud went out in clear.
@MainActor func testElevenLabsKeysAreRedactedAnywhereInALine() {
    let url = tempURL("transcripts-elevenlabs")
    let log = TranscriptDebugLog(fileURL: url)
    log.said("sk_0123456789abcdef0123456789abcdef al inicio")
    log.heard("la clave es (sk_ABCDEFGHIJKLMNOPQRSTUVWX) y ya")
    let text = contents(url)
    expect(!text.contains("sk_0123456789"), "M1: sk_ al inicio de la línea")
    expect(!text.contains("sk_ABCDEFGHIJ"), "M1: sk_ pegado a un paréntesis")
    expect(text.contains("[redacted]"), "M1: se marca como redactado")
    expect(text.contains("al inicio") && text.contains("y ya"), "M1: el resto se conserva")
    expectEq(TranscriptDebugLog.redacted("task_list corto"), "task_list corto",
             "M1: una palabra corta con sk_ no es clave")
}
