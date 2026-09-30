@testable import CompanionCore
import Foundation
import Testing

// 16q-3a: the ledger that pairs verdicts with decisions, and the agreement counters.

private func version(_ tool: String, _ args: String) -> ActionVersion {
    ActionVersion(toolName: tool, argumentsJSON: args)
}

private func version(_ args: String) -> ActionVersion {
    version("app:slack:slack-send-message", args)
}

private func ver(_ n: Int) -> ActionVersion { version("t", "{\"n\":\(n)}") }

// MARK: - Ledger

private let v1 = version(#"{"a":1}"#)
private let v2 = version(#"{"a":2}"#)

@Test func judgeLedgerPairsVerdictThenDecision() {
    let opened = JudgeLedger().opening(v1, at: 100)
    let (afterVerdict, early) = opened.recording(verdict: .covered, for: v1, at: 101)
    expect(early == nil, "16q-3a ledger: el veredicto solo no empareja")
    let (afterDecision, pair) = afterVerdict.recording(decision: .approved, for: v1, at: 105.5)
    expectEq(pair, JudgeLedger.Pair(verdict: .covered, decision: .approved, verdictFirst: true, msDecision: 5500),
             "16q-3a ledger: par con veredicto primero y ms desde que se abrio")
    expectEq(afterDecision.count, 0, "16q-3a ledger: el par sale del ledger")
}

@Test func judgeLedgerPairsDecisionBeforeVerdict() {
    let (afterDecision, early) = JudgeLedger().recording(decision: .denied, for: v1, at: 10)
    expect(early == nil, "16q-3a ledger: la decision sola no empareja")
    let (afterVerdict, pair) = afterDecision.recording(verdict: .notCovered(.otherTarget), for: v1, at: 12)
    expectEq(pair?.verdictFirst, false, "16q-3a ledger: la decision llego antes")
    expectEq(pair?.decision, .denied, "16q-3a ledger: decision")
    expectEq(pair?.verdict, .notCovered(.otherTarget), "16q-3a ledger: veredicto")
    expectEq(afterVerdict.count, 0, "16q-3a ledger: emparejado y fuera")
}

@Test func judgeLedgerNeverPairsDifferentVersions() {
    let (a, _) = JudgeLedger().recording(verdict: .covered, for: v1, at: 0)
    let (b, pair) = a.recording(decision: .approved, for: v2, at: 1)
    expect(pair == nil, "16q-3a ledger: versiones distintas no se emparejan (invariante 9)")
    expectEq(b.count, 2, "16q-3a ledger: cada una espera a su pareja")
}

@Test func judgeLedgerKeepsAVerdictWithoutDecisionUntilItExpires() {
    let (ledger, _) = JudgeLedger().recording(verdict: .covered, for: v1, at: 0)
    expectEq(ledger.count, 1, "16q-3a ledger: veredicto sin decision queda")
}

@Test func judgeLedgerDropsNonPairableDecisions() {
    for decision in [ApprovalDecision.expired, .cancelled, .voiceResolved] {
        let (withVerdict, _) = JudgeLedger().recording(verdict: .covered, for: v1, at: 0)
        let (after, pair) = withVerdict.recording(decision: decision, for: v1, at: 1)
        expect(pair == nil, "16q-3a ledger: \(decision) queda fuera de la metrica")
        expectEq(after.count, 0, "16q-3a ledger: \(decision) libera la entrada")
    }
}

@Test func judgeLedgerCapsAtThirtyTwoDroppingTheOldest() {
    var ledger = JudgeLedger()
    let versions = (0 ..< 33).map { version(#"{"n":\#($0)}"#) }
    for (i, v) in versions.enumerated() {
        (ledger, _) = ledger.recording(verdict: .covered, for: v, at: TimeInterval(i))
    }
    expectEq(ledger.count, 32, "16q-3a ledger: tope de 32")
    let (_, oldest) = ledger.recording(decision: .approved, for: versions[0], at: 40)
    expect(oldest == nil, "16q-3a ledger: la mas antigua se descarto")
    let (_, newest) = ledger.recording(decision: .approved, for: versions[32], at: 40)
    expect(newest != nil, "16q-3a ledger: la mas nueva sigue")
}

@Test func judgeLedgerExpiresEntriesAfterOneHundredTwentySeconds() {
    let (ledger, _) = JudgeLedger().recording(verdict: .covered, for: v1, at: 1000)
    let (alive, pairAlive) = ledger.recording(decision: .approved, for: v1, at: 1119.9)
    expect(pairAlive != nil, "16q-3a ledger: a 119,9 s aun vive")
    expectEq(alive.count, 0, "16q-3a ledger: emparejado")
    let (_, pairLate) = ledger.recording(decision: .approved, for: v1, at: 1120)
    expect(pairLate == nil, "16q-3a ledger: a 120 s ya no empareja")
    let (purged, _) = ledger.recording(verdict: .covered, for: v2, at: 1200)
    expectEq(purged.count, 1, "16q-3a ledger: la vencida se purga al escribir")
}

@Test func judgeLedgerIsImmutable() {
    let base = JudgeLedger()
    let (next, _) = base.recording(verdict: .covered, for: v1, at: 0)
    expectEq(base.count, 0, "16q-3a ledger: el original no cambia")
    expectEq(next.count, 1, "16q-3a ledger: la copia si")
}

@Test func ledgerTieCountsAsVerdictFirst() {
    let (a, _) = JudgeLedger().recording(verdict: .covered, for: v1, at: 50)
    let (_, pair) = a.recording(decision: .approved, for: v1, at: 50)
    expectEq(pair?.verdictFirst, true, "16q-3a ledger: mismo instante, veredicto primero, mutacion: < en vez de <=")
    let (b, _) = JudgeLedger().recording(decision: .approved, for: v1, at: 50)
    let (_, reversed) = b.recording(verdict: .covered, for: v1, at: 50)
    expectEq(reversed?.verdictFirst, true, "16q-3a ledger: el empate cuenta igual llegue en el orden que llegue")
    let (c, _) = JudgeLedger().recording(decision: .approved, for: v1, at: 50)
    let (_, late) = c.recording(verdict: .covered, for: v1, at: 50.001)
    expectEq(late?.verdictFirst, false, "16q-3a ledger: un milisegundo despues ya no es a tiempo")
}

@Test func ledgerEvictsTheLeastRecentlyTouched() {
    var ledger = JudgeLedger()
    for i in 0 ..< 32 { (ledger, _) = ledger.recording(verdict: .covered, for: ver(i), at: TimeInterval(i)) }
    (ledger, _) = ledger.recording(verdict: .notCovered(.unclear), for: ver(0), at: 40)
    expectEq(ledger.count, 32, "16q-3a ledger: actualizar no crece")
    (ledger, _) = ledger.recording(verdict: .covered, for: ver(99), at: 41)
    expectEq(ledger.count, 32, "16q-3a ledger: el 33 desaloja uno")
    let (_, evicted) = ledger.recording(decision: .approved, for: ver(1), at: 42)
    expect(evicted == nil, "16q-3a ledger: cae la 1, la menos tocada, mutacion: actualizar en su sitio")
    let (_, kept) = ledger.recording(decision: .approved, for: ver(0), at: 42)
    expect(kept != nil, "16q-3a ledger: la 0 se toco despues y sigue")
}

@Test func ledgerTTLIsAnchoredAtOpeningNotAtTheLastTouch() {
    let opened = JudgeLedger().opening(v1, at: 1000)
    let (touched, _) = opened.recording(verdict: .covered, for: v1, at: 1100)
    let (_, stillAlive) = touched.recording(decision: .approved, for: v1, at: 1119.9)
    expect(stillAlive != nil, "16q-3a ledger: a 119,9 s de abrirse aun empareja")
    let (_, tooLate) = touched.recording(decision: .approved, for: v1, at: 1120)
    expect(tooLate == nil, "16q-3a ledger: tocarla a los 100 s no la alarga, mutacion: anclar al ultimo toque")
}

@Test func ledgerLateVerdictAfterAnExpiryLeavesOnlyAVerdict() {
    let (afterExpiry, none) = JudgeLedger().recording(decision: .expired, for: v1, at: 60)
    expect(none == nil, "16q-3a ledger: el vencimiento no empareja")
    expectEq(afterExpiry.count, 0, "16q-3a ledger: y no deja entrada")
    let (afterVerdict, pair) = afterExpiry.recording(verdict: .covered, for: v1, at: 61)
    expect(pair == nil, "16q-3a ledger: el veredicto tardio no se empareja con el vencimiento")
    expectEq(afterVerdict.count, 1, "16q-3a ledger: queda esperando la siguiente hoja de la misma version")
    let (_, retried) = afterVerdict.recording(decision: .approved, for: v1, at: 70)
    expectEq(retried?.verdict, .covered, "16q-3a ledger: si la misma accion se reintenta, el mismo veredicto vale")
    let (aged, _) = afterVerdict.recording(verdict: .covered, for: ver(2), at: 61 + 120)
    expectEq(aged.count, 1, "16q-3a ledger: si no se reintenta, el TTL la purga")
}

@Test func ledgerMeasuresMsDecisionFromTheFirstSighting() {
    let (a, _) = JudgeLedger().recording(decision: .approved, for: v1, at: 10)
    let (_, first) = a.recording(verdict: .covered, for: v1, at: 12)
    expectEq(first?.msDecision, 0, "16q-3a ledger: decision sin apertura previa, cero ms")
    expectEq(first?.verdictFirst, false, "16q-3a ledger: decision primero")
    let opened = JudgeLedger().opening(v1, at: 8)
    let (b, _) = opened.recording(decision: .approved, for: v1, at: 10)
    let (_, opening) = b.recording(verdict: .covered, for: v1, at: 12)
    expectEq(opening?.msDecision, 2000, "16q-3a ledger: desde que se abrio hasta la decision, no hasta el veredicto")
    let (c, _) = opened.recording(verdict: .covered, for: v1, at: 9)
    let (_, normal) = c.recording(decision: .denied, for: v1, at: 10.25)
    expectEq(normal?.msDecision, 2250, "16q-3a ledger: veredicto primero, mismo ancla")
}

@Test func ledgerKeepsTheFirstVerdictOfAVersion() {
    let (a, _) = JudgeLedger().recording(verdict: .covered, for: v1, at: 1)
    let (b, secondPair) = a.recording(verdict: .notCovered(.otherTarget), for: v1, at: 3)
    expect(secondPair == nil, "16q-3a ledger: un segundo veredicto no empareja")
    expectEq(b.count, 1, "16q-3a ledger: y no duplica la entrada")
    let (_, pair) = b.recording(decision: .approved, for: v1, at: 2.5)
    expectEq(pair?.verdict, .covered, "16q-3a ledger: manda el primero, mutacion: el ultimo pisa")
    expectEq(pair?.verdictFirst, true, "16q-3a ledger: y su instante es el del primero")
}

// MARK: - Agreement

private func pair(_ verdict: JudgeVerdict, _ decision: ApprovalDecision, first: Bool = true) -> JudgeLedger.Pair {
    JudgeLedger.Pair(verdict: verdict, decision: decision, verdictFirst: first, msDecision: 100)
}

@Test func judgeAgreementCountsTheFourCells() {
    var agreement = JudgeAgreement()
    agreement = agreement.recording(pair(.covered, .approved))
    agreement = agreement.recording(pair(.covered, .denied, first: false))
    agreement = agreement.recording(pair(.notCovered(.notAsked), .denied))
    agreement = agreement.recording(pair(.notCovered(.unclear), .approved))
    expectEq(agreement.paired, 4, "16q-3a acuerdo: emparejados")
    expectEq(agreement.coveredApproved, 1, "16q-3a acuerdo: cubierta y aprobada")
    expectEq(agreement.falseCover, 1, "16q-3a acuerdo: falsa cubierta")
    expectEq(agreement.notCoveredDenied, 1, "16q-3a acuerdo: no cubierta y negada")
    expectEq(agreement.approved, 2, "16q-3a acuerdo: aprobadas")
    expectEq(agreement.onTime, 3, "16q-3a acuerdo: a tiempo")
    expectEq(agreement.agreementRate, 0.5, "16q-3a acuerdo: (1+1)/4")
    expectEq(agreement.utilityRate, 0.5, "16q-3a acuerdo: 1/2 de los clics ahorrados")
}

@Test func judgeAgreementNeverCountsFailedAsCovered() {
    var agreement = JudgeAgreement()
    for failure in [JudgeFailure.timeout, .http, .invalid, .noProvider, .noWords, .tooMany, .cancelled] {
        agreement = agreement.recording(.failed(failure), ms: 10)
        agreement = agreement.recording(pair(.failed(failure), .approved))
        agreement = agreement.recording(pair(.failed(failure), .denied))
    }
    expectEq(agreement.coveredApproved, 0, "16q-3a acuerdo: failed no es cubierta aprobada")
    expectEq(agreement.falseCover, 0, "16q-3a acuerdo: failed no es falsa cubierta")
    expectEq(agreement.notCoveredDenied, 0, "16q-3a acuerdo: failed tampoco infla el acuerdo")
    expectEq(agreement.failed, 7, "16q-3a acuerdo: los fallos se cuentan aparte")
    expectEq(agreement.paired, 14, "16q-3a acuerdo: pero si emparejan")
    expectEq(agreement.approved, 7, "16q-3a acuerdo: y las aprobaciones cuentan para la utilidad")
    expectEq(agreement.utilityRate, 0.0, "16q-3a acuerdo: utilidad cero sin cubiertas")
}

@Test func judgeAgreementRatesAreNilWithoutData() {
    let empty = JudgeAgreement()
    expect(empty.agreementRate == nil && empty.utilityRate == nil && empty.failRate == nil
        && empty.onTimeRate == nil && empty.latency(percentile: 0.5) == nil,
           "16q-3a acuerdo: sin datos no hay tasas inventadas")
}

@Test func judgeAgreementComputesFailRateAndLatencyPercentiles() {
    var agreement = JudgeAgreement()
    for ms in 1 ... 100 { agreement = agreement.recording(.covered, ms: ms) }
    agreement = agreement.recording(.failed(.timeout), ms: 2500)
    expectEq(agreement.judged, 101, "16q-3a acuerdo: juzgados")
    expectEq(agreement.failRate, 1.0 / 101.0, "16q-3a acuerdo: fallo = failed / juzgados")
    expectEq(agreement.latency(percentile: 0.5), 51, "16q-3a acuerdo: p50")
    expectEq(agreement.latency(percentile: 0.95), 96, "16q-3a acuerdo: p95")
}

@Test func judgeAgreementNearestRankOnAHundredSamples() {
    var agreement = JudgeAgreement()
    for ms in (1 ... 100).reversed() { agreement = agreement.recording(.covered, ms: ms) }
    expectEq(agreement.latency(percentile: 0.5), 50, "16q-3a acuerdo: p50 de 100 es la muestra 50")
    expectEq(agreement.latency(percentile: 0.95), 95, "16q-3a acuerdo: p95 de 100 es la muestra 95")
    expectEq(agreement.latency(percentile: 0), 1, "16q-3a acuerdo: p0 es el minimo")
    expectEq(agreement.latency(percentile: 1.0), 100, "16q-3a acuerdo: p100 es el maximo")
    expectEq(agreement.latency(percentile: 1.7), 100, "16q-3a acuerdo: fuera de rango se acota arriba")
    expectEq(agreement.latency(percentile: -0.3), 1, "16q-3a acuerdo: fuera de rango se acota abajo")
}

@Test func judgeAgreementUtilityIsNilWhenNothingWasApproved() {
    var agreement = JudgeAgreement()
    agreement = agreement.recording(pair(.covered, .denied))
    agreement = agreement.recording(pair(.notCovered(.notAsked), .denied))
    expectEq(agreement.paired, 2, "16q-3a acuerdo: hay pares")
    expectEq(agreement.approved, 0, "16q-3a acuerdo: ninguna aprobada")
    expect(agreement.utilityRate == nil, "16q-3a acuerdo: sin aprobaciones no hay utilidad que medir")
    expectEq(agreement.agreementRate, 0.5, "16q-3a acuerdo: pero el acuerdo si existe")
}

@Test func judgeAgreementLogLineUsesTheSpecKeys() {
    var agreement = JudgeAgreement()
    agreement = agreement.recording(pair(.covered, .approved))
    expectEq(agreement.description,
             "paired=1 false_cover=0 covered_approved=1 approved=1 not_covered_denied=0 failed=0 on_time=1",
             "16q-3a acuerdo: la linea judge-agree de la spec 11")
}

// MARK: - Latency window (fix round, finding 3)

@Test func judgeAgreementKeepsOnlyTheMostRecentLatencies() {
    let window = JudgeAgreement.maxLatencySamples
    var agreement = JudgeAgreement()
    for _ in 0 ..< 10 { agreement = agreement.recording(.covered, ms: 1_000_000) }
    for ms in 1 ... window {
        agreement = agreement.recording(.covered, ms: ms)
        expect(agreement.latencies.count <= window, "16q-3a acuerdo: la ventana nunca pasa de \(window)")
    }
    expectEq(agreement.latencies.count, window, "16q-3a acuerdo: la ventana se llena")
    expectEq(agreement.latency(percentile: 1.0), window, "16q-3a acuerdo: las muestras viejas salieron")
    expectEq(agreement.latency(percentile: 0), 1, "16q-3a acuerdo: y las recientes siguen")
    expectEq(agreement.judged, window + 10, "16q-3a acuerdo: el contador de juzgados no se acota")
}
