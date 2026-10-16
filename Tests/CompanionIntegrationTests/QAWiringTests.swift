import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@testable import CompanionUI

// Puente QA PR-2: the composition root hands the same gate to both roads, and
// nothing grants a critical action without the owner's own check.

private let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")

private func source(_ path: String) -> String {
    (try? String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

@Test func theRootBuildsOneGateWithTheSystemOwnerCheckAndHandsItToBothRoads() {
    let qa = source("CompanionApp/CompanionMainQA.swift")
    expect(qa.contains("owner: LocalAuthOwnerCheck()"), "el gate usa Touch ID / contraseña del sistema")
    expect(qa.contains("model.qaGate = gate"), "el chat consulta ese gate")
    expect(qa.contains("QALiveBand.band("), "con el clasificador de hechos reales")
    expect(!qa.contains("bandWithoutFacts"), "nunca el clasificador sin hechos en la ruta viva")
    let main = source("CompanionApp/CompanionMain.swift")
    expect(main.contains("qaGate: qa.gate"), "el puente recibe el mismo gate")
    expect(source("CompanionApp/BridgeHost.swift").contains("qaGate: qaGate)"), "y se lo pasa a su ParentToolGuard")
}

@Test func onlyTheGateCanProduceAGrantAndOnlyAfterTheOwnerConfirmed() {
    let granting = ["Core", "Services", "UI", "App"].flatMap { layer -> [String] in
        let dir = sources.appendingPathComponent("Companion\(layer)")
        return Conformance.swiftFiles(in: dir).compactMap { file in
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            return text.contains("return .granted") ? file.lastPathComponent : nil
        }
    }
    expectEq(granting.sorted(), ["QAApprovalPolicy.swift", "QAGate.swift"], "la politica y el gate, nadie mas")
    expect(source("CompanionCore/Approvals/QAApprovalPolicy.swift").contains("case .confirmed: return .granted"),
           "la politica solo concede desde OwnerCheck.confirmed")
    expect(source("CompanionServices/Approvals/QAGate.swift").contains("case .granted:\n            return .granted"),
           "y el gate solo repite esa concesion")
}

@Test func theQAScopeIsKeptInMemoryNeverInUserDefaults() {
    expect(!source("CompanionUI/Settings/QAScopePreference.swift").contains("UserDefaults.standard"),
           "muere con el proceso")
}

@Test @MainActor func theQAScopeStartsOffAndNeedsTheHandsAndAnOwnerCheck() {
    let original = HandsLendingPreference.enabled
    defer {
        QAScopePreference.disable()
        HandsLendingPreference.enabled = original
    }
    QAScopePreference.disable()
    expect(!QAScopePreference.enabled, "nace apagado")
    HandsLendingPreference.enabled = false
    expect(!QAScopePreference.set(true, handsLent: false, canVerify: true), "no enciende sin las manos")
    expect(!QAScopePreference.set(true, handsLent: true, canVerify: false), "ni sin prueba de dueña")
    HandsLendingPreference.enabled = true
    expect(QAScopePreference.set(true, handsLent: true, canVerify: true), "con ambas, enciende")
    expect(QAScopePreference.enabled, "y lo lee")
    HandsLendingPreference.enabled = false
    expect(!QAScopePreference.enabled, "cerrar las manos se lleva el modo QA")
}

@Test @MainActor func theQAScopeNotifiesOnlyOnARealChange() {
    let original = HandsLendingPreference.enabled
    defer {
        QAScopePreference.disable()
        HandsLendingPreference.enabled = original
    }
    HandsLendingPreference.enabled = true
    QAScopePreference.disable()
    let counter = LockedBox(0)
    let observer = NotificationCenter.default.addObserver(
        forName: .companionQAScopeDidChange, object: nil, queue: nil
    ) { _ in counter.withLock { $0 += 1 } }
    defer { NotificationCenter.default.removeObserver(observer) }
    QAScopePreference.set(false, handsLent: true, canVerify: true)
    expectEq(counter.value, 0, "apagado sobre apagado no avisa")
    QAScopePreference.set(true, handsLent: true, canVerify: true)
    QAScopePreference.set(true, handsLent: true, canVerify: true)
    expectEq(counter.value, 1, "encender avisa una vez")
    QAScopePreference.disable()
    expectEq(counter.value, 2, "apagar avisa")
}
