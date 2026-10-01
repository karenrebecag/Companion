import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func workdirTrustTests() {
    testHomeIsNotPersisted()
    testANarrowerFolderIsPersisted()
    testHomeStillWorksForThisSession()
    testNothingChosenMeansNoReach()
    testWritingOutsideIsStillRefused()
}

private let home = FileManager.default.homeDirectoryForCurrentUser.path

@MainActor func testHomeIsNotPersisted() {
    // Copiado literal de la referencia, y por la misma razon: la carpeta
    // personal es demasiado amplia para RECORDAR que la autorizaste. Elegirla
    // vale para hoy, no para siempre.
    WorkdirPreference.stored = nil
    WorkdirPreference.stored = home
    expect(WorkdirPreference.stored == nil,
           "elegir el home no deja huella en disco")
    WorkdirPreference.stored = nil
}

@MainActor func testANarrowerFolderIsPersisted() {
    let narrow = (home as NSString).appendingPathComponent("Desktop")
    guard FileManager.default.fileExists(atPath: narrow) else { return }
    WorkdirPreference.stored = narrow
    expect(WorkdirPreference.stored != nil,
           "una carpeta acotada si se recuerda entre arranques")
    WorkdirPreference.stored = nil
}

@MainActor func testHomeStillWorksForThisSession() {
    // No se prohibe elegirlo: se prohibe recordarlo.
    expect(WorkdirPreference.isAllowed(home),
           "el home sigue siendo una eleccion valida")
}

@MainActor func testNothingChosenMeansNoReach() {
    // Sin carpeta elegida el especialista no alcanza nada, y eso es el
    // default: preguntar cuando haga falta, no repartir el home de entrada.
    let validator = PathValidator(workdir: nil)
    expect(!validator.isAllowed(home), "sin carpeta, no hay alcance")
    expect(!validator.isAllowed("/tmp"), "ni fuera de ella")
}

@MainActor func testWritingOutsideIsStillRefused() {
    // No-regresion: en lectura y escritura fuera del limite somos MAS
    // estrictos que la referencia, y esta wave no afloja eso.
    let validator = PathValidator(workdir: (home as NSString)
        .appendingPathComponent("Desktop"))
    expect(!validator.isAllowed("/etc/hosts"), "fuera del limite, no")
    expect(!validator.isAllowed(home), "ni el padre del workdir")
}
