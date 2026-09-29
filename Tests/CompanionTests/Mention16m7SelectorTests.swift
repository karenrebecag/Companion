import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-7: the selector's behavior, on fakes. The system dialog appears
// only the first time she types `@`; without the permission the list offers
// apps and files; stale answers never repaint; a pick is text plus, at most,
// the one channel she opened.

private final class FakeContacts: ContactsProviding, @unchecked Sendable {
    private let lock = NSLock()
    var state: ContactsAccess
    var grants = true
    var book: [MentionCandidate] = []
    var channelBook: [String: [MentionChannel]] = [:]
    var searchDelay: [String: Duration] = [:]
    var requestDelay: Duration?
    private(set) var requests = 0
    private(set) var searches: [String] = []
    private(set) var channelCalls: [String] = []

    init(_ state: ContactsAccess) { self.state = state }

    func access() -> ContactsAccess { lock.withLock { state } }

    func requestAccess() async -> Bool {
        if let requestDelay { try? await Task.sleep(for: requestDelay) }
        return lock.withLock {
            requests += 1
            state = grants ? .granted : .denied
            return grants
        }
    }

    func search(_ query: String, limit: Int) async -> [MentionCandidate] {
        let delay = lock.withLock { () -> Duration? in searches.append(query); return searchDelay[query] }
        if let delay { try? await Task.sleep(for: delay) }
        guard access() == .granted else { return [] }
        return book.filter { $0.name.lowercased().contains(query.lowercased()) }
    }

    func channels(ofContact id: String) async -> [MentionChannel] {
        lock.withLock { channelCalls.append(id) }
        return channelBook[id] ?? []
    }
}

private func cand(_ kind: MentionCandidate.Kind, _ name: String, id: String? = nil) -> MentionCandidate {
    MentionCandidate(id: id ?? name, kind: kind, name: name)!
}

private let ana = cand(.contact, "Ana García", id: "c1")
private let email = MentionChannel(kind: .email, label: "work", value: "ana@example.com")!
private let phone = MentionChannel(kind: .phone, label: nil, value: "+52 55 0000 0000")!

@MainActor private func model(
    _ contacts: FakeContacts?, apps: [MentionCandidate] = [cand(.app, "Slack")],
    files: [MentionCandidate] = [cand(.file, "Ana notas.md", id: "/tmp/Ana notas.md")]
) -> MentionSelectorModel {
    MentionSelectorModel(sources: MentionSources(contacts: contacts, connectedApps: { apps }, recentFiles: { files }))
}

@Test @MainActor func mentionSelectorPermissionTests() async {
    let contacts = FakeContacts(.notDetermined)
    contacts.book = [ana]
    let selector = model(contacts)
    expectEq(contacts.requests, 0, "16m-7: crear el selector no pide el permiso (nunca al arrancar)")
    selector.update(draft: "hola")
    selector.update(draft: "")
    await settle()
    expectEq(contacts.requests, 0, "16m-7: teclear sin @ no lo pide")
    expectEq(contacts.searches.count, 0, "16m-7: ni busca")

    selector.update(draft: "hola @a")
    await pumpUntil("16m-7: lista") { selector.rows.count == 3 }
    expectEq(contacts.requests, 1, "16m-7: el primer @ pide el permiso una vez")
    expectEq(selector.rows.map(\.title), ["Ana García", "Slack", "Ana notas.md"], "16m-7: contactos, apps, archivos")
    selector.update(draft: "hola @ana")
    await settle()
    selector.update(draft: "")
    selector.update(draft: "@a")
    await settle()
    expectEq(contacts.requests, 1, "16m-7: el segundo @ no vuelve a preguntar")
}

@Test @MainActor func mentionSelectorWithoutPermissionTests() async {
    let denied = FakeContacts(.denied)
    denied.book = [ana]
    let selector = model(denied)
    selector.update(draft: "@an")
    await pumpUntil("16m-7: sin permiso") { !selector.rows.isEmpty }
    expectEq(selector.rows.map(\.title), ["Ana notas.md"], "16m-7: denegado ofrece apps y archivos que casan")
    expectEq(denied.requests, 0, "16m-7: denegado no vuelve a preguntar")
    expectEq(denied.channelCalls.count, 0, "16m-7: ni lee medios")

    let none = model(nil)
    none.update(draft: "@sl")
    await pumpUntil("16m-7: sin libreta") { !none.rows.isEmpty }
    expectEq(none.rows.map(\.title), ["Slack"], "16m-7: sin proveedor de contactos, solo apps y archivos")

    let refused = FakeContacts(.notDetermined)
    refused.grants = false
    let asked = model(refused)
    asked.update(draft: "@")
    await pumpUntil("16m-7: negó en el diálogo") { asked.rows.count == 2 }
    expectEq(asked.rows.map(\.title), ["Slack", "Ana notas.md"], "16m-7: si dice que no, la lista sigue con lo demás")
    await pumpUntil("16m-7: el diálogo terminó") { !asked.isRequestingAccess }
}

@Test @MainActor func mentionSelectorClosedDialogHoldsTheIslandTests() async {
    let contacts = FakeContacts(.notDetermined)
    contacts.requestDelay = .milliseconds(150)
    let selector = model(contacts)
    selector.update(draft: "@")
    await pumpUntil("16m-7: mientras el diálogo está abierto lo dice, para que la isla no se pliegue") { selector.isRequestingAccess }
    await pumpUntil("16m-7: fin del diálogo") { !selector.isRequestingAccess }
}

@Test @MainActor func mentionSelectorStaleAnswersTests() async {
    let contacts = FakeContacts(.granted)
    contacts.book = [cand(.contact, "Ana Slow", id: "s"), cand(.contact, "Anselmo", id: "f")]
    contacts.searchDelay["a"] = .milliseconds(150)
    let selector = model(contacts, apps: [], files: [])
    selector.update(draft: "@a")
    selector.update(draft: "@an")
    await pumpUntil("16m-7: la última consulta manda") { selector.rows.map(\.title) == ["Ana Slow", "Anselmo"] }
    try? await Task.sleep(for: .milliseconds(250))
    expectEq(selector.rows.map(\.title), ["Ana Slow", "Anselmo"], "16m-7: la respuesta lenta de la consulta vieja no repinta")
    selector.update(draft: "hola")
    expect(selector.rows.isEmpty && !selector.isOpen, "16m-7: sin @ se cierra")
}

@Test @MainActor func mentionSelectorKeysTests() async {
    let contacts = FakeContacts(.granted)
    contacts.book = [ana]
    let selector = model(contacts)
    var picks: [MentionPick] = []
    selector.onPick = { picks.append($0) }
    expect(!selector.press(.down), "16m-7: cerrado, las flechas son del campo")
    expect(!selector.press(.enter), "16m-7: cerrado, Return envía")
    selector.update(draft: "hola @a")
    await pumpUntil("16m-7: lista") { selector.rows.count == 3 }
    expectEq(selector.cursor, 0, "16m-7: el cursor arranca en la primera fila")
    expect(selector.press(.down) && selector.cursor == 1, "16m-7: abajo")
    expect(selector.press(.up) && selector.press(.up) && selector.cursor == 2, "16m-7: arriba da la vuelta")
    expect(selector.press(.down) && selector.cursor == 0, "16m-7: abajo da la vuelta")
    expect(selector.press(.escape) && !selector.isOpen, "16m-7: Esc cierra")
    selector.update(draft: "hola @a")
    await settle()
    expect(!selector.isOpen, "16m-7: la misma consulta descartada no se reabre sola")
    selector.update(draft: "hola @an")
    await pumpUntil("16m-7: otra consulta reabre, ya con los contactos") { selector.rows.first?.title == "Ana García" }
    expect(selector.press(.tab), "16m-7: Tab elige")
    expectEq(picks.count, 1, "16m-7: una elección")
    expectEq(picks.first?.draft, "hola @Ana García ", "16m-7: el nombre reemplaza lo tecleado")
    expectEq(picks.first?.mention?.name, "Ana García", "16m-7: la mención es la del contacto")
    expectEq(picks.first?.mention?.channel == nil, true, "16m-7: por defecto solo el nombre")
    expectEq(contacts.channelCalls.count, 0, "16m-7: elegir el nombre no lee correos ni teléfonos")
    expect(!selector.isOpen, "16m-7: al elegir se cierra")
}

@Test @MainActor func mentionSelectorChannelsTests() async {
    let contacts = FakeContacts(.granted)
    contacts.book = [ana]
    contacts.channelBook["c1"] = [email, phone]
    let selector = model(contacts, apps: [], files: [])
    var picks: [MentionPick] = []
    selector.onPick = { picks.append($0) }
    selector.update(draft: "@ana")
    await pumpUntil("16m-7: lista") { selector.rows.count == 1 }
    expect(selector.press(.right), "16m-7: derecha abre los medios")
    await pumpUntil("16m-7: medios") { selector.rows.count == 3 }
    expectEq(contacts.channelCalls, ["c1"], "16m-7: solo se leen los del contacto abierto")
    expectEq(selector.rows.first?.title, "Ana García", "16m-7: la primera fila sigue siendo solo el nombre")
    expectEq(selector.cursor, 0, "16m-7: el cursor cae en 'solo el nombre'")
    expect(selector.press(.left), "16m-7: izquierda vuelve")
    await pumpUntil("16m-7: vuelta") { selector.rows.count == 1 }
    expect(selector.press(.right), "16m-7: otra vez")
    await pumpUntil("16m-7: medios 2") { selector.rows.count == 3 }
    _ = selector.press(.down)
    _ = selector.press(.enter)
    expectEq(picks.first?.mention?.channel, email, "16m-7: viaja el medio que eligió, uno solo")
    expectEq(picks.first?.draft, "@Ana García ", "16m-7: en el campo queda solo el nombre")

    let lonely = FakeContacts(.granted)
    lonely.book = [ana]
    let plain = model(lonely, apps: [cand(.app, "Anki")], files: [])
    plain.update(draft: "@an")
    await pumpUntil("16m-7: lista 2") { plain.rows.count == 2 }
    _ = plain.press(.right)
    await settle()
    expectEq(plain.rows.count, 2, "16m-7: un contacto sin medios no abre nada")
    _ = plain.press(.down)
    _ = plain.press(.right)
    await settle()
    expectEq(plain.rows.count, 2, "16m-7: una app no tiene medios")
    expectEq(lonely.channelCalls, ["c1"], "16m-7: derecha sobre una app no lee la libreta")
}

@Test @MainActor func mentionSelectorPickKindsTests() async {
    let selector = model(nil)
    var picks: [MentionPick] = []
    selector.onPick = { picks.append($0) }
    selector.update(draft: "@")
    await pumpUntil("16m-7: lista") { selector.rows.count == 2 }
    selector.choose(0)
    expectEq(picks.first?.mention?.kind, .app, "16m-7: una app es una mención por nombre")
    expect(picks.first?.attach == nil, "16m-7: una app no adjunta nada")
    selector.update(draft: "@")
    await pumpUntil("16m-7: lista 2") { selector.rows.count == 2 }
    selector.choose(1)
    expectEq(picks.last?.attach, URL(fileURLWithPath: "/tmp/Ana notas.md"), "16m-7: un archivo se adjunta por el camino de los adjuntos")
    expectEq(picks.last?.mention?.kind, .file, "16m-7: y queda mencionado")
    selector.choose(99)
    expectEq(picks.count, 2, "16m-7: una fila que no existe no elige nada")
    selector.update(draft: "@sl")
    await pumpUntil("16m-7: lista 3") { !selector.rows.isEmpty }
    selector.update(draft: "otro texto")
    selector.choose(0)
    expectEq(picks.count, 2, "16m-7: si el borrador cambió antes del clic, no se pisa")
}

@Test @MainActor func mentionCopyTests() {
    let row = MentionSelectorModel.Row.candidate(ana)
    let label = MentionCopy.accessibility(row, index: 0, count: 4)
    expect(label.contains("Ana García") && label.contains("1") && label.contains("4"), "16m-7: VoiceOver dice nombre, tipo y posición: \(label)")
    expect(MentionCopy.accessibility(.candidate(cand(.app, "Slack")), index: 1, count: 4)
           != MentionCopy.accessibility(.candidate(cand(.file, "Slack")), index: 1, count: 4), "16m-7: el tipo se oye")
    expect(!MentionCopy.hint(canExpand: true).isEmpty && MentionCopy.hint(canExpand: true) != MentionCopy.hint(canExpand: false),
           "16m-7: la pista dice cómo abrir los medios solo en contactos")
}

@Test @MainActor func mentionMetricsTests() {
    expectEq(MentionMetrics.padding, 4, "16m-7 selector: padding 4")
    expectEq(MentionMetrics.maxHeight, 240, "16m-7 selector: 240 de alto máximo")
    expectEq(MentionMetrics.radius, 11, "16m-7 selector: radio 11")
    expectEq([MentionMetrics.itemPaddingY, MentionMetrics.itemPaddingX], [6, 8], "16m-7 ítem: 6 × 8")
    expectEq(MentionMetrics.itemRadius, 7, "16m-7 ítem: radio 7")
    expectEq(MentionMetrics.itemFontSize, 13, "16m-7 ítem: 13 px")
    expectEq(MentionMetrics.hoverAlpha, 0.16, "16m-7 ítem: hover acento al 16 %")
}

// MARK: - Review round

@Test @MainActor func mentionSelectorTabDuringDialogTests() async {
    let contacts = FakeContacts(.notDetermined)
    contacts.book = [ana]
    contacts.requestDelay = .milliseconds(250)
    let selector = model(contacts)
    var picks: [MentionPick] = []
    selector.onPick = { picks.append($0) }
    selector.update(draft: "hola @a")
    await pumpUntil("16m-7 review: apps y archivos ya están") { selector.rows.count == 2 }
    expect(selector.isRequestingAccess, "16m-7 review: el diálogo sigue abierto")
    expect(selector.press(.down), "16m-7 review: flecha abajo")
    expect(selector.press(.tab), "16m-7 review: Tab elige lo resaltado")
    expectEq(picks.count, 1, "16m-7 review: elegir no espera al diálogo")
    expectEq(picks.first?.mention?.name, "Ana notas.md", "16m-7 review: elige la fila que ella había resaltado, no otra")
    expectEq(picks.first?.draft, "hola @Ana notas.md ", "16m-7 review: y el texto queda con esa")
}

@Test @MainActor func mentionSelectorCursorFollowsItsRowTests() async {
    let contacts = FakeContacts(.notDetermined)
    contacts.book = [ana]
    contacts.requestDelay = .milliseconds(200)
    let moved = model(contacts)
    moved.update(draft: "@a")
    await pumpUntil("16m-7 review: fase 1") { moved.rows.count == 2 }
    _ = moved.press(.down)
    let title = moved.cursor.map { moved.rows[$0].title }
    await pumpUntil("16m-7 review: llegan los contactos") { moved.rows.count == 3 }
    expectEq(moved.cursor.map { moved.rows[$0].title }, title, "16m-7 review: una vez que ella movió el cursor, sigue en su fila aunque lleguen otras por encima")

    let still = FakeContacts(.notDetermined)
    still.book = [ana]
    still.requestDelay = .milliseconds(200)
    let untouched = model(still)
    untouched.update(draft: "@a")
    await pumpUntil("16m-7 review: fase 1 b") { untouched.rows.count == 2 }
    await pumpUntil("16m-7 review: llegan los contactos b") { untouched.rows.count == 3 }
    expectEq(untouched.cursor.map { untouched.rows[$0].title }, "Ana García", "16m-7 review: sin haberlo movido, el cursor sigue a la fila de arriba")
}

@Test @MainActor func mentionSelectorSourcesArriveIndependentlyTests() async {
    let slow = MentionSelectorModel(sources: MentionSources(
        contacts: nil, connectedApps: { [cand(.app, "Slack")] },
        recentFiles: {
            try? await Task.sleep(for: .milliseconds(400))
            return [cand(.file, "Plan.pdf", id: "/tmp/Plan.pdf")]
        }))
    slow.update(draft: "@")
    await pumpUntil("16m-7 review: las apps no esperan a Spotlight") { slow.rows.map(\.title) == ["Slack"] }
    await pumpUntil("16m-7 review: y los archivos llegan al terminar") { slow.rows.map(\.title) == ["Slack", "Plan.pdf"] }

    let contacts = FakeContacts(.granted)
    contacts.book = [ana]
    let people = MentionSelectorModel(sources: MentionSources(
        contacts: contacts, connectedApps: { [] },
        recentFiles: {
            try? await Task.sleep(for: .milliseconds(400))
            return [cand(.file, "Ana.pdf", id: "/tmp/Ana.pdf")]
        }))
    people.update(draft: "@an")
    await pumpUntil("16m-7 review: los contactos tampoco esperan a Spotlight") { people.rows.map(\.title) == ["Ana García"] }
}

@Test @MainActor func mentionSelectorPermissionRacesTests() async {
    let contacts = FakeContacts(.notDetermined)
    contacts.book = [ana]
    contacts.requestDelay = .milliseconds(200)
    let selector = model(contacts, apps: [], files: [])
    selector.update(draft: "@a")
    selector.update(draft: "@an")
    await pumpUntil("16m-7 review: tras conceder, los contactos aparecen para la última consulta") { selector.rows.map(\.title) == ["Ana García"] }
    expectEq(contacts.requests, 1, "16m-7 review: dos teclas durante el diálogo, un solo diálogo")

    let later = FakeContacts(.denied)
    later.book = [ana]
    let flipped = model(later, apps: [], files: [])
    flipped.update(draft: "@a")
    await settle(0.1)
    expect(!flipped.isOpen, "16m-7 review: denegado no ofrece contactos")
    flipped.update(draft: "hola")
    later.state = .granted
    flipped.update(draft: "@a")
    await pumpUntil("16m-7 review: concedido en Ajustes entre dos @, aparecen") { flipped.rows.map(\.title) == ["Ana García"] }
    expectEq(later.requests, 0, "16m-7 review: sin volver a preguntar")
}

@Test @MainActor func mentionSelectorStaleChooseTests() async {
    final class Calls: @unchecked Sendable { var n = 0 }
    let calls = Calls()
    let selector = MentionSelectorModel(sources: MentionSources(
        contacts: nil,
        connectedApps: {
            calls.n += 1
            if calls.n > 1 { try? await Task.sleep(for: .milliseconds(300)) }
            return [cand(.app, "Slack"), cand(.app, "Sage")]
        },
        recentFiles: { [] }))
    var picks: [MentionPick] = []
    selector.onPick = { picks.append($0) }
    selector.update(draft: "@s")
    await pumpUntil("16m-7 review: lista") { selector.rows.count == 2 }
    selector.update(draft: "@sl")
    selector.choose(0)
    expectEq(picks.count, 0, "16m-7 review: una fila de la consulta anterior no se elige mientras llega la nueva")
    await pumpUntil("16m-7 review: la nueva") { selector.rows.map(\.title) == ["Slack"] }
    selector.choose(0)
    expectEq(picks.count, 1, "16m-7 review: la nueva sí")
}

@Test @MainActor func mentionSelectorMidTextTests() async {
    // A book that answers everything, like a permissive system search.
    let greedy = FakeContacts(.granted)
    greedy.book = [ana]
    let selector = model(greedy, apps: [], files: [])
    selector.update(draft: "@Ana y luego")
    await settle(0.15)
    expect(!selector.isOpen, "16m-7 review: con texto escrito después del nombre nadie casa y no hay lista que se coma lo siguiente")
    selector.update(draft: "@an")
    await pumpUntil("16m-7 review: lista") { selector.isOpen }
    selector.update(draft: "an")
    expect(!selector.isOpen, "16m-7 review: borrar el @ cierra el selector")
}

@Test @MainActor func mentionPickFallsBackWhenAttachFailsTests() {
    let file = MentionCandidate(id: "/tmp/x.pdf", kind: .file, name: "x.pdf")!
    let pick = MentionPick(draft: "mira @x.pdf ", fallbackDraft: "mira ", mention: Mention(candidate: file), attach: URL(fileURLWithPath: "/tmp/x.pdf"))
    let failed = pick.applied(attach: { _ in false })
    expectEq(failed.draft, "mira ", "16m-7 review: si el archivo no se pudo adjuntar, el @nombre no se queda")
    expect(failed.mention == nil, "16m-7 review: ni se registra la mención")
    let worked = pick.applied(attach: { _ in true })
    expectEq(worked.draft, "mira @x.pdf ", "16m-7 review: si se adjuntó, todo queda")
    expectEq(worked.mention?.kind, .file, "16m-7 review: y la mención")
    let app = MentionPick(draft: "hola @Slack ", fallbackDraft: "hola ", mention: Mention(candidate: cand(.app, "Slack")), attach: nil)
    expectEq(app.applied(attach: { _ in false }).draft, "hola @Slack ", "16m-7 review: sin adjunto no hay nada que pueda fallar")
}
