import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func heardConfirmationTests() {
    testAVoiceBornJobRepeatsWhatItUnderstood()
    testTheGoalIsRepeatedVerbatim()
    testTheHeardNoticeTravelsInBothLanguages()
    testTypedJobsDoNotNeedIt()
}

@MainActor func testAVoiceBornJobRepeatsWhatItUnderstood() {
    // La causa raiz de la sesion del 24: el STT devolvio "Sinaırakalık forma",
    // el modelo invento "revisar el disco", y el encargo arranco sobre el
    // sistema de archivos sin que Karen viera nunca QUE se habia entendido.
    let notice = Escalation.heardNotice("revisar el disco", .es)
    expect(notice.contains("revisar el disco"),
           "el hilo repite lo entendido antes de tocar nada: \(notice)")
}

@MainActor func testTheGoalIsRepeatedVerbatim() {
    // Parafrasear seria la misma trampa otra vez: lo que se muestra tiene que
    // ser lo que se va a hacer, palabra por palabra.
    let goal = "borrar los temporales del escritorio"
    expect(Escalation.heardNotice(goal, .en).contains(goal),
           "sin reescribir el objetivo")
}

@MainActor func testTheHeardNoticeTravelsInBothLanguages() {
    expect(!Escalation.heardNotice("x", .en).contains("Entendí"),
           "el aviso en inglés no arrastra español")
    expect(Escalation.heardNotice("x", .es).lowercased().contains("entend"),
           "y el español está escrito")
}

@MainActor func testTypedJobsDoNotNeedIt() {
    // Escribiendo ya viste tus propias palabras en pantalla; repetirlas seria
    // el ruido que Karen ya senalo.
    expect(!Escalation.needsHeardNotice(bornFromVoice: false),
           "un encargo tecleado no repite nada")
    expect(Escalation.needsHeardNotice(bornFromVoice: true),
           "uno hablado si")
}
