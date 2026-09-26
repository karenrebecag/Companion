import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 15f-3 (TDD row 5) and code review 2026-09-25 (HIGH-B).
// 15f-3: the specialist's spoken outcome left no `said=` line.
// HIGH-B: in classic mode that outcome was the MODEL-FACING instruction
// ("El especialista respondió «…». Acusa en una línea…") handed straight
// to the synthesizer, past the JSON guard and the language gate. It is now
// a fixed line in our own words plus a real summarizing turn through the
// hold brain and `TurnMouth`; `said=` is written once the audio is done,
// with what was actually spoken.

@Test @MainActor func subAgentSaidTests() async {
    await testClassicJobDoneSpeaksOwnWordsAndASummaryTurn()
    await testClassicJobFailureSpeaksOwnWordsAndASummaryTurn()
    await testWithDebugOffTheJobOutcomeLeavesNoFile()
    await testAPressOverTheAnnouncementLogsWhatAlreadySounded()
}

private let instructionMarkers = ["El especialista respondió", "Acusa en una línea", "El encargo «", "Díselo"]

private func transcriptURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-subagent-\(UUID().uuidString).log")
}

private func contents(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

/// A hold that delegates, then the summary round the job's end asks for.
@MainActor private func runJobHold(
    _ h: VoiceHarness, submitted: @escaping @MainActor () -> Bool, summary: [ChatDelta]
) async {
    h.transcriber.stoppedText = "crea un archivo"
    h.chat.rounds = [[.handoff(Handoff(goal: "crea prueba.txt", context: ""))], summary]
    await h.session.hold()
    await pumpUntil("subagente: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("subagente: el submitter corrió") { submitted() }
    await pumpUntil("subagente: la boca habla") { h.synth.finished && h.synth.queue.count >= 2 }
}

@MainActor func testClassicJobDoneSpeaksOwnWordsAndASummaryTurn() async {
    let url = transcriptURL()
    let jobs = CapturingSubmitter()
    let h = makeVoiceHarness(jobs: jobs, language: .es, debugTranscripts: true)
    await h.session.attachTranscriptLog(TranscriptDebugLog(fileURL: url))
    await runJobHold(h, submitted: { !jobs.goals.isEmpty }, summary: [
        .text("Creé prueba.txt en tu escritorio. "),
        .text(#"{"goal":"verifica","path":"/tmp/x"}"#),
        .text(" El log dice: Permission denied while writing the backup file."),
    ])
    let spoken = h.synth.queue.joined(separator: " ")
    expectEq(h.synth.queue.first, "Listo, ya está en pantalla.", "HIGH-B: primero, palabras propias")
    for marker in instructionMarkers {
        expect(!spoken.contains(marker), "HIGH-B: nunca la instrucción al modelo (\(marker))")
    }
    expect(!spoken.contains("{"), "HIGH-B: el JSON del resumen no se dice (\(spoken))")
    expect(spoken.contains("Creé prueba.txt en tu escritorio."), "HIGH-B: el resumen se dice")
    expect(spoken.contains("Permission denied while writing the backup file."),
           "HIGH-B: la línea de error en inglés citada se queda (HIGH-A)")

    let request = h.chat.histories.last ?? []
    expectEq(request.count, 1, "HIGH-B: el turno de resumen es un solo mensaje")
    expectEq(request.first?.role, .user, "HIGH-B: con el resultado como turno de usuario")
    expect(request.first?.content.contains("ok") == true, "HIGH-B: lleva el resultado del especialista")
    expect(h.chat.toolsSeen.isEmpty, "HIGH-B: el resumen no ofrece herramientas")

    await settle()
    expect(!contents(url).contains("said=Listo"), "HIGH-B: said= no se escribe antes de sonar")
    h.synth.spoken = spoken
    h.synth.yield(.finished)
    await pumpUntil("HIGH-B: said= tras terminar el audio") { contents(url).contains("said=") }
    let said = contents(url).split(separator: "\n").filter { $0.contains("said=") }
    expectEq(said.count, 1, "HIGH-B: una línea said= del anuncio")
    expect(said.first?.hasSuffix("said=\(spoken)") == true, "HIGH-B: said= es lo que sonó")
}

@MainActor func testClassicJobFailureSpeaksOwnWordsAndASummaryTurn() async {
    let url = transcriptURL()
    let submitted = TextBox()
    let jobs = RefusingJobSubmitter(output: "Error: EACCES permission denied", seen: submitted)
    let h = makeVoiceHarness(jobs: jobs, language: .es, debugTranscripts: true)
    await h.session.attachTranscriptLog(TranscriptDebugLog(fileURL: url))
    await runJobHold(h, submitted: { !submitted.all.isEmpty }, summary: [
        .text("No tenía permiso para escribir en esa carpeta."),
    ])
    let spoken = h.synth.queue.joined(separator: " ")
    expectEq(h.synth.queue.first, "No pude terminarlo.", "HIGH-B: fallo en palabras propias")
    for marker in instructionMarkers {
        expect(!spoken.contains(marker), "HIGH-B: nunca la instrucción al modelo (\(marker))")
    }
    expect(spoken.contains("No tenía permiso"), "HIGH-B: el resumen del fallo se dice")
    expect(h.chat.histories.last?.first?.content.contains("EACCES") == true,
           "HIGH-B: el motivo va al turno de resumen")
}

@MainActor func testWithDebugOffTheJobOutcomeLeavesNoFile() async {
    let url = transcriptURL()
    let jobs = CapturingSubmitter()
    let h = makeVoiceHarness(jobs: jobs, language: .es, debugTranscripts: false)
    await h.session.attachTranscriptLog(TranscriptDebugLog(fileURL: url))
    await runJobHold(h, submitted: { !jobs.goals.isEmpty }, summary: [.text("Listo.")])
    h.synth.spoken = h.synth.queue.joined(separator: " ")
    h.synth.yield(.finished)
    await settle()
    expect(!FileManager.default.fileExists(atPath: url.path),
           "15f-3: con la depuración apagada no hay archivo")
}

/// LOW-4: `said=` follows `cutTurn`'s rule — what already sounded, never
/// what was only queued.
@MainActor func testAPressOverTheAnnouncementLogsWhatAlreadySounded() async {
    let url = transcriptURL()
    let jobs = CapturingSubmitter()
    let h = makeVoiceHarness(jobs: jobs, language: .es, debugTranscripts: true)
    await h.session.attachTranscriptLog(TranscriptDebugLog(fileURL: url))
    await runJobHold(h, submitted: { !jobs.goals.isEmpty }, summary: [
        .text("Creé prueba.txt en tu escritorio."),
    ])
    h.synth.spoken = "Listo, ya está en pantalla."
    h.synth.stopped = false
    await h.session.hold()
    await pumpUntil("LOW-4: said= al cortar") { contents(url).contains("said=") }
    let said = contents(url).split(separator: "\n").filter { $0.contains("said=") }
    expectEq(said.count, 1, "LOW-4: una línea")
    expect(said.first?.hasSuffix("said=Listo, ya está en pantalla.") == true,
           "LOW-4: solo lo que sonó (\(said))")
    expect(h.synth.stopped, "LOW-4: el anuncio se calla al pulsar")
}

private final class RefusingJobSubmitter: JobSubmitter, @unchecked Sendable {
    let output: String
    let seen: TextBox
    init(output: String, seen: TextBox) {
        self.output = output
        self.seen = seen
    }
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        seen.append(handoff.goal)
        return JobResult(output: output, isError: true)
    }
    func cancel() async {}
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}
