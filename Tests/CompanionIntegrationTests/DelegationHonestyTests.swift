import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Dos defectos que una captura de uso real (2026-08-25) destapó a la vez: la
// usuaria pidió "crea prueba1.md en el escritorio", el especialista contestó
// que NO podía escribir ahí, y la voz cerró con "listo, ya quedó el archivo"
// sobre un archivo que nunca existió.
//
// Decisión de la dueña (revoca el default de la Wave 9h): Companion debe darle
// al especialista el toolbox completo y toda la máquina, igual que el CLI de
// Claude Code — los edits se auto-aceptan y los comandos piden permiso por la
// hoja de voz. El alcance es amplio; el volante de permisos se queda.
//
// Bug #1 — la voz cantaba victoria por un rechazo. `jobDoneAnnouncement` le
//   ordenaba al modelo "di solo que terminó", incondicional, y ese anuncio se
//   dispara con `isError:false` — justo lo que devuelve un rechazo cortés del
//   CLI. "Terminó el proceso" no es "se logró el objetivo".
// Bug #2 — el especialista corría en una subcarpeta, no en la cuenta. Sin una
//   carpeta elegida su alcance debe ser el home entero, para que ~/Desktop
//   quede dentro sin pedir nada.

// MARK: - Bug #1: el acuse no ordena cantar victoria; se remite a la respuesta

@Test @MainActor func voiceAcknowledgesTheReplyInsteadOfClaimingSuccess() async {
    await pinLanguage {
        let goal = "create prueba1.md on the Desktop"

        // El anuncio ya no manda afirmar éxito incondicional; defiere a lo que el
        // especialista realmente dijo.
        let announcement = Escalation.jobDoneAnnouncement(goal, .en)
        expect(!announcement.lowercased().contains("say only that it is done"),
               "acuse: no se le ordena al modelo cantar victoria")
        expect(announcement.lowercased().contains("unless the reply says so"),
               "acuse: se remite a lo que la respuesta del especialista dice")

        // Y el circuito: el texto real del especialista (aquí, un rechazo) aterriza
        // en el hilo, que es la verdad que el modelo debe acusar.
        let refusal = "I don't have permission to create a file on the Desktop."
        let thread = ScriptedThread()
        let announced = TextBox()
        await VoiceJobBridge.run(
            Handoff(goal: goal, context: ""),
            jobs: FixedSubmitter(result: JobResult(output: refusal, isError: false)),
            thread: thread,
            announce: { announced.append($0.instruction) },
            language: .en)

        expectEq(thread.turns.last?.content, refusal,
                 "circuito: la respuesta real del especialista queda en pantalla")
        let announcedText = announced.all.joined(separator: " ")
        expect(!announcedText.lowercased().contains("say only that it is done"),
               "circuito: la voz no recibe la orden de decir que quedó hecho")
    }
}

// MARK: - Bug #2: sin carpeta elegida, el alcance por defecto es toda la cuenta

@Test @MainActor func specialistReachesTheWholeAccountByDefault() {
    let saved = WorkdirPreference.stored
    defer { WorkdirPreference.stored = saved }
    WorkdirPreference.stored = nil  // nada elegido: el caso de arranque en frío

    let dir = WorkdirPreference.effective
    let home = FileManager.default.homeDirectoryForCurrentUser
        .resolvingSymlinksInPath().path

    expectEq(dir, home,
             "alcance: sin carpeta elegida el especialista arranca en tu "
             + "cuenta entera, como el CLI")
    let desktop = home + "/Desktop"
    expect(desktop.hasPrefix(dir + "/") || desktop == dir,
           "alcance: ~/Desktop queda dentro, sin pedir nada")
}
