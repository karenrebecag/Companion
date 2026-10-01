import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 16m-7: the address book. The permission is asked the first time she
// types `@` and never at launch; a search returns names, never the book;
// the ways to reach someone come only from opening that one contact.

private final class FakeBackend: ContactsBackend, @unchecked Sendable {
    private let lock = NSLock()
    var state: ContactsAccess
    var grantsOnRequest = true
    var records: [ContactRecord] = []
    var channelRecords: [String: [ChannelRecord]] = [:]
    var failure: Error?
    private(set) var requestCalls = 0
    private(set) var nameCalls: [String] = []
    private(set) var channelCalls: [String] = []

    init(_ state: ContactsAccess) { self.state = state }

    func status() -> ContactsAccess { lock.withLock { state } }

    func requestAccess() async throws -> Bool {
        try lock.withLock {
            requestCalls += 1
            if let failure { throw failure }
            state = grantsOnRequest ? .granted : .denied
            return grantsOnRequest
        }
    }

    func names(matching query: String) throws -> [ContactRecord] {
        try lock.withLock {
            nameCalls.append(query)
            if let failure { throw failure }
            return records
        }
    }

    func channels(ofContact id: String) throws -> [ChannelRecord] {
        try lock.withLock {
            channelCalls.append(id)
            if let failure { throw failure }
            return channelRecords[id] ?? []
        }
    }
}

private struct Boom: Error {}

private let book = [
    ContactRecord(id: "1", name: "Ana García"), ContactRecord(id: "2", name: "Ana Paula"),
    ContactRecord(id: "3", name: "Luis Ana"),
]

@Test func contactsPermissionTests() async {
    let fresh = FakeBackend(.notDetermined)
    let contacts = SystemContacts(backend: fresh)
    expectEq(contacts.access(), .notDetermined, "16m-7: el estado se lee sin preguntar")
    expectEq(fresh.requestCalls, 0, "16m-7: construir y leer el estado nunca muestra el diálogo")
    let found = await contacts.search("ana", limit: 8)
    expectEq(found, [], "16m-7: sin permiso decidido, buscar no devuelve nada")
    expectEq(fresh.requestCalls, 0, "16m-7: ni buscar pide el permiso: solo requestAccess() lo hace")
    expectEq(fresh.nameCalls.count, 0, "16m-7: ni toca la libreta")

    expect(await contacts.requestAccess(), "16m-7: concedido")
    expectEq(fresh.requestCalls, 1, "16m-7: un diálogo")
    expect(await contacts.requestAccess(), "16m-7: ya concedido se responde sin diálogo")
    expectEq(fresh.requestCalls, 1, "16m-7: no se repite")

    let denied = FakeBackend(.denied)
    let refused = SystemContacts(backend: denied)
    expect(!(await refused.requestAccess()), "16m-7: denegado sigue denegado")
    expectEq(denied.requestCalls, 0, "16m-7: tras negar no se vuelve a preguntar (el sistema tampoco lo mostraría)")
    expectEq(await refused.search("ana", limit: 8), [], "16m-7: denegado no lee")
    expectEq(denied.nameCalls.count + denied.channelCalls.count, 0, "16m-7: denegado no toca la libreta")
    expectEq(await refused.channels(ofContact: "1"), [], "16m-7: ni los medios de contacto")

    let no = FakeBackend(.notDetermined)
    no.grantsOnRequest = false
    expect(!(await SystemContacts(backend: no).requestAccess()), "16m-7: si ella dice que no, es que no")

    let broken = FakeBackend(.notDetermined)
    broken.failure = Boom()
    expect(!(await SystemContacts(backend: broken).requestAccess()), "16m-7: un fallo del sistema es un no, sin caer")
}

@Test func contactsSearchTests() async {
    let backend = FakeBackend(.granted)
    backend.records = book
    let contacts = SystemContacts(backend: backend)
    let found = await contacts.search("ana", limit: 2)
    expectEq(found.map(\.name), ["Ana García", "Ana Paula"], "16m-7: nombres, en el orden del sistema y con tope")
    expectEq(found.map(\.kind), [.contact, .contact], "16m-7: son contactos")
    expectEq(found.map(\.id), ["1", "2"], "16m-7: cada uno por su identificador")
    expectEq(backend.channelCalls.count, 0, "16m-7: buscar jamás lee correos ni teléfonos")
    expectEq(await contacts.search("", limit: 8), [], "16m-7: sin consulta no se lista la libreta")
    expectEq(await contacts.search("   \n", limit: 8), [], "16m-7: una consulta en blanco tampoco")
    expectEq(backend.nameCalls, ["ana"], "16m-7: solo la búsqueda con texto llegó a la libreta")
    expectEq(await contacts.search("ana", limit: 0).count, 1, "16m-7: el tope mínimo es 1")
    expectEq(await contacts.search("ana", limit: 10_000).count, min(book.count, MentionRanking.maxRows),
             "16m-7: el tope máximo es el del selector")
    backend.records = [ContactRecord(id: "9", name: "  "), ContactRecord(id: "8", name: "Eve\u{202E}")]
    expectEq(await contacts.search("e", limit: 8).map(\.name), ["Eve"], "16m-7: nombres vacíos se descartan y el resto se sanea")
}

@Test func contactsFailuresNeverLogTheQueryTests() async throws {
    let backend = FakeBackend(.granted)
    backend.failure = Boom()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("contacts-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: url) }
    let secret = "Maria-Secretisima"
    let found = await Log.capturing(to: url) { await SystemContacts(backend: backend).search(secret, limit: 8) }
    let channels = await Log.capturing(to: url) { await SystemContacts(backend: backend).channels(ofContact: "secret-id") }
    expectEq(found, [], "16m-7: un fallo de la libreta es una lista vacía")
    expectEq(channels, [], "16m-7: y sin medios")
    let logged = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    expect(logged.contains("contacts"), "16m-7: el fallo deja una línea")
    expect(!logged.contains(secret) && !logged.contains("secret-id"), "16m-7: la línea no lleva lo buscado ni el identificador")
}

@Test func contactsChannelsTests() async {
    let backend = FakeBackend(.granted)
    backend.channelRecords["1"] = [
        ChannelRecord(kind: .email, label: "work", value: "ana@example.com"),
        ChannelRecord(kind: .phone, label: nil, value: "+52 55 1234 5678"),
        ChannelRecord(kind: .email, label: "home", value: "  "),
    ]
    let contacts = SystemContacts(backend: backend)
    let channels = await contacts.channels(ofContact: "1")
    expectEq(channels.map(\.value), ["ana@example.com", "+52 55 1234 5678"], "16m-7: correos y teléfonos, sin vacíos")
    expectEq(channels.map(\.kind), [.email, .phone], "16m-7: con su tipo")
    expectEq(backend.channelCalls, ["1"], "16m-7: solo el contacto que ella abrió")
    backend.channelRecords["2"] = (0 ..< 40).map { ChannelRecord(kind: .email, label: nil, value: "a\($0)@x.com") }
    expectEq(await contacts.channels(ofContact: "2").count, SystemContacts.maxChannels, "16m-7: tope de medios por contacto")
}

@Test func contactsFetchOnlyAsksForWhatItNeedsTests() throws {
    guard let root = Conformance.repoRoot() else { return }
    let source = try String(contentsOf: root.appendingPathComponent("Sources/CompanionServices/Perception/Contacts.swift"), encoding: .utf8)
    for forbidden in ["NoteKey", "BirthdayKey", "PostalAddresses", "ImageData", "ThumbnailImage", "SocialProfiles",
                      "InstantMessage", "ContactRelations", "DatesKey", "UrlAddresses", "JobTitle", "OrganizationName",
                      "enumerateContacts", "containers(matching"] {
        expect(!source.contains(forbidden), "16m-7: la libreta no se lee con \(forbidden)")
    }
    expect(source.contains("CNContactEmailAddressesKey") && source.contains("CNContactPhoneNumbersKey"),
           "16m-7: los medios de contacto se piden por su nombre")
}

@Test func contactsGuardsHoldWithDataPresentTests() async {
    // A book full of data behind a closed door: the state alone must stop
    // every read, or a mutation that drops the guard would go unnoticed.
    for state in [ContactsAccess.denied, .notDetermined] {
        let backend = FakeBackend(state)
        backend.records = book
        backend.channelRecords["1"] = [ChannelRecord(kind: .email, label: nil, value: "ana@example.com")]
        let contacts = SystemContacts(backend: backend)
        expectEq(await contacts.channels(ofContact: "1"), [], "16m-7 review: sin permiso (\(state)) no hay medios de contacto")
        expectEq(backend.channelCalls.count, 0, "16m-7 review: y ni se le pregunta a la libreta (\(state))")
        expectEq(await contacts.search("ana", limit: 8), [], "16m-7 review: sin permiso (\(state)) no hay nombres")
        expectEq(backend.nameCalls.count, 0, "16m-7 review: ni se busca (\(state))")
    }
}
