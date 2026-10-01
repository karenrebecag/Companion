import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// "Companion Next" y com.karen.companion.next fueron andamio: nacieron para
// que LaunchServices no abriera el prototipo al pedir el rebuild (ledger).
// Quien descargue el DMG no instala un andamio: instala Companion.

@Test @MainActor func productIdentityTests() {
    testTheTwoIdentitiesNeverCollide()
    testIdentityIsRecognisedAtRuntime()
    testTheBundleScriptMatchesTheSource()
}

/// La cicatriz que esto conserva: dos apps con el mismo bundle id en una Mac
/// y LaunchServices abre la que resolvió primero.
@MainActor func testTheTwoIdentitiesNeverCollide() {
    let release = ProductIdentity.release
    let dev = ProductIdentity.development
    expect(release.bundleID != dev.bundleID,
           "identidad: release y desarrollo no comparten bundle id")
    expect(release.logFileName != dev.logFileName,
           "identidad: ni archivo de log, o los turnos se mezclan al depurar")
    expectEq(release.bundleID, "com.karen.companion",
             "identidad: el producto reclama el id sin sufijo")
    expectEq(release.displayName, "Companion",
             "identidad: en el Finder se llama Companion")
    expect(dev.bundleID.hasPrefix(release.bundleID),
           "identidad: desarrollo es una variante del producto, no otro app")
}

/// El binario tiene que saber cuál es sin recompilarse distinto: lo dice el
/// bundle que lo envuelve.
@MainActor func testIdentityIsRecognisedAtRuntime() {
    expectEq(ProductIdentity.of(bundleID: "com.karen.companion"), .release,
             "runtime: el id de release se reconoce")
    expectEq(ProductIdentity.of(bundleID: "com.karen.companion.next"),
             .development, "runtime: y el de desarrollo también")
    expectEq(ProductIdentity.of(bundleID: nil), .development,
             "runtime: sin bundle (swift run) se asume desarrollo")
    expectEq(ProductIdentity.of(bundleID: "com.otra.cosa"), .development,
             "runtime: un id desconocido nunca se hace pasar por el producto")
}

/// El plist lo escribe bash; la fuente vive en Swift. Si divergen, la app se
/// instala con una identidad que su propio código no reconoce.
@MainActor func testTheBundleScriptMatchesTheSource() {
    let script = (try? String(
        contentsOfFile: repoPath("scripts/bundle.sh"), encoding: .utf8)) ?? ""
    expect(!script.isEmpty, "script: bundle.sh se puede leer desde los tests")
    // Asignaciones exactas, no subcadenas: "com.karen.companion.next"
    // contiene al id de release y haría pasar un test flojo.
    for identity in ProductIdentity.allCases {
        expect(script.contains("BUNDLE_ID=\"\(identity.bundleID)\""),
               "script: bundle.sh asigna \(identity.bundleID)")
        expect(script.contains("DISPLAY_NAME=\"\(identity.displayName)\""),
               "script: bundle.sh asigna \(identity.displayName)")
        expect(script.contains("LOG_NAME=\"\(identity.logFileName)\""),
               "script: bundle.sh asigna \(identity.logFileName)")
    }
}
