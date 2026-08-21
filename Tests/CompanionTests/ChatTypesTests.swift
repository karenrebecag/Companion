import CompanionCore
import Foundation
import Testing

@Test @MainActor func chatTypesTests() {
    testChatDeltaEquatable()
    testChatErrorEquatable()
    testPortErrorsEquatable()
    testConversationRecords()
    testMemorySecretStore()
    testPortFakes()
}

@MainActor func testChatDeltaEquatable() {
    expectEq(ChatDelta.text("hola"), ChatDelta.text("hola"),
             "delta: el mismo texto es igual")
    expect(ChatDelta.text("hola") != ChatDelta.text("adiós"),
           "delta: textos distintos no son iguales")
    expectEq(ChatDelta.text(""), ChatDelta.text(""),
             "delta: texto vacío es un valor, no un ausente")
    expect(ChatDelta.text("hola") != ChatDelta.text("Hola"),
           "delta: la igualdad de texto es exacta")

    let handoff = Handoff(goal: "leer notas", context: "solo png")
    expectEq(ChatDelta.handoff(handoff), ChatDelta.handoff(handoff),
             "delta: el mismo handoff es igual")
    expect(ChatDelta.text("leer notas") != ChatDelta.handoff(handoff),
           "delta: texto y handoff no se confunden")
    expect(
        ChatDelta.handoff(Handoff(goal: "a", context: ""))
            != ChatDelta.handoff(Handoff(goal: "b", context: "")),
        "delta: handoffs con goal distinto no son iguales")
    expect(
        ChatDelta.handoff(Handoff(goal: "a", context: "x"))
            != ChatDelta.handoff(Handoff(goal: "a", context: "y")),
        "delta: handoffs con context distinto no son iguales")

    let unicode = ChatDelta.text("ñoño — café")
    expectEq(unicode, ChatDelta.text("ñoño — café"),
             "delta: unicode viaja intacto")
}

@MainActor func testChatErrorEquatable() {
    expectEq(ChatError.unauthorized, .unauthorized, "error: unauthorized")
    expectEq(ChatError.forbidden, .forbidden, "error: forbidden")
    expectEq(ChatError.rateLimited, .rateLimited, "error: rateLimited")
    expectEq(ChatError.timeout, .timeout, "error: timeout")
    expectEq(ChatError.unreachable, .unreachable, "error: unreachable")
    expectEq(ChatError.empty, .empty, "error: empty")
    expectEq(ChatError.noProvider, .noProvider, "error: noProvider")
    expectEq(ChatError.invalidKey, .invalidKey, "error: invalidKey")
    expectEq(ChatError.httpStatus(429), .httpStatus(429),
             "error: httpStatus conserva el código")

    expect(ChatError.unauthorized != .forbidden, "error: 401 ≠ 403")
    expect(ChatError.httpStatus(429) != .rateLimited,
           "error: 429 crudo no se colapsa a rateLimited")
    expect(ChatError.httpStatus(401) != .unauthorized,
           "error: 401 crudo no se colapsa a unauthorized")
    expect(ChatError.httpStatus(500) != ChatError.httpStatus(502),
           "error: códigos distintos no son iguales")
    expect(ChatError.empty != .noProvider, "error: empty ≠ noProvider")
    expect(ChatError.invalidKey != .unauthorized, "error: invalidKey ≠ 401")
    expect(ChatError.timeout != .unreachable, "error: timeout ≠ unreachable")
}

@MainActor func testPortErrorsEquatable() {
    expectEq(SecretStoreError.emptyValue, .emptyValue, "secret: emptyValue")
    expectEq(SecretStoreError.denied, .denied, "secret: denied")
    expectEq(SecretStoreError.notAvailable, .notAvailable, "secret: notAvailable")
    expectEq(SecretStoreError.unexpected(42), .unexpected(42),
             "secret: unexpected conserva el código")
    expect(SecretStoreError.emptyValue != .denied, "secret: empty ≠ denied")
    expect(SecretStoreError.unexpected(1) != .unexpected(2),
           "secret: códigos unexpected distintos")
    expect(SecretStoreError.denied != .notAvailable,
           "secret: denied ≠ notAvailable")

    expectEq(PersistenceError.encoding, .encoding, "persist: encoding")
    expectEq(PersistenceError.decoding, .decoding, "persist: decoding")
    expectEq(PersistenceError.io, .io, "persist: io")
    expect(PersistenceError.encoding != .decoding, "persist: encoding ≠ decoding")
    expect(PersistenceError.decoding != .io, "persist: decoding ≠ io")
}

@MainActor func testConversationRecords() {
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    let meta = ConversationMeta(id: "c1", title: "Notas", updatedAt: stamp)
    expectEq(meta.id, "c1", "meta: id es el Identifiable")
    expectEq(meta.title, "Notas", "meta: título")
    expectEq(meta.updatedAt, stamp, "meta: updatedAt")
    expectEq(meta, ConversationMeta(id: "c1", title: "Notas", updatedAt: stamp),
             "meta: Equatable por valor")
    expect(meta != ConversationMeta(id: "c2", title: "Notas", updatedAt: stamp),
           "meta: id distinto no es igual")

    let emptyMsg = ConversationMessage(role: "user", text: "")
    expectEq(emptyMsg.role, "user", "mensaje: role es String, no TurnRole")
    expectEq(emptyMsg.text, "", "mensaje: texto vacío se conserva")
    expectEq(emptyMsg.attachmentPaths, [],
             "mensaje: sin adjuntos el default es []")

    let withFiles = ConversationMessage(
        role: "assistant",
        text: "aquí está",
        attachmentPaths: ["/tmp/a png.png", "/tmp/ñoño.txt"])
    expectEq(withFiles.attachmentPaths.count, 2, "mensaje: adjuntos viajan")
    expectEq(withFiles.attachmentPaths[1], "/tmp/ñoño.txt",
             "mensaje: unicode en path")

    let record = ConversationRecord(
        id: "c1", title: "Notas", updatedAt: stamp,
        messages: [emptyMsg, withFiles])
    expectEq(record.id, "c1", "record: id es el Identifiable")
    expectEq(record.messages.count, 2, "record: conserva el hilo")
    expectEq(record.messages[0].text, "", "record: primer mensaje vacío")
    expectEq(record.messages[1].attachmentPaths, withFiles.attachmentPaths,
             "record: adjuntos del segundo mensaje")
    expectEq(
        record,
        ConversationRecord(
            id: "c1", title: "Notas", updatedAt: stamp,
            messages: [emptyMsg, withFiles]),
        "record: Equatable por valor")

    let blank = ConversationRecord(
        id: "", title: "", updatedAt: Date(timeIntervalSince1970: 0),
        messages: [])
    expectEq(blank.messages, [], "record: hilo vacío es válido en Core")
    expectEq(blank.id, "", "record: id vacío no se rechaza aquí")

    let many = ConversationRecord(
        id: "big", title: "largo", updatedAt: stamp,
        messages: (0..<200).map {
            ConversationMessage(role: "user", text: "m\($0)")
        })
    expectEq(many.messages.count, 200, "record: 200 mensajes caben")
    expectEq(many.messages[199].text, "m199", "record: el último no se recorta")
}

/// In-memory SecretStore for the harness. Production lives in Services.
final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]

    func read(_ key: SecretKey) throws -> String? {
        values[key.rawValue]
    }

    func write(_ key: SecretKey, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SecretStoreError.emptyValue }
        values[key.rawValue] = trimmed
    }

    func delete(_ key: SecretKey) throws {
        values.removeValue(forKey: key.rawValue)
    }
}

@MainActor func testMemorySecretStore() {
    let store: any SecretStore = MemorySecretStore()

    do {
        expect(try store.read(.openAI) == nil,
               "secret: leer una clave ausente devuelve nil")
    } catch {
        expect(false, "secret: leer ausente no debía tirar \(error)")
    }

    do {
        try store.write(.openAI, value: "")
        expect(false, "secret: vacío debía tirar emptyValue")
    } catch let error as SecretStoreError {
        expectEq(error, .emptyValue, "secret: vacío tira emptyValue")
    } catch {
        expect(false, "secret: vacío debía ser SecretStoreError, no \(error)")
    }

    do {
        try store.write(.groq, value: "   \n\t  ")
        expect(false, "secret: solo espacios debía tirar emptyValue")
    } catch let error as SecretStoreError {
        expectEq(error, .emptyValue, "secret: recortado vacío tira emptyValue")
    } catch {
        expect(false, "secret: espacios debía ser SecretStoreError, no \(error)")
    }

    do {
        try store.write(.openAI, value: "  sk-live  \n")
        expectEq(try store.read(.openAI), "sk-live",
                 "secret: escribe, recorta y lee")
        expect(try store.read(.groq) == nil,
               "secret: una clave no pisa la otra")

        try store.write(.openAI, value: "sk-nueva")
        expectEq(try store.read(.openAI), "sk-nueva",
                 "secret: el segundo write pisa")

        try store.write(.openRouter, value: "ñoño-key")
        expectEq(try store.read(.openRouter), "ñoño-key",
                 "secret: unicode en el valor")

        let large = String(repeating: "a", count: 10_000)
        try store.write(.groq, value: large)
        expectEq(try store.read(.groq)?.count ?? -1, 10_000,
                 "secret: 10k caracteres caben")

        try store.delete(.openAI)
        expect(try store.read(.openAI) == nil,
               "secret: delete deja nil")
        expectEq(try store.read(.openRouter), "ñoño-key",
                 "secret: delete no toca otras claves")

        try store.delete(.openAI)
        expect(try store.read(.openAI) == nil,
               "secret: delete de ausente no truena")
    } catch {
        expect(false, "secret: el camino feliz no debía tirar \(error)")
    }
}

struct MemoryProbe: CapabilityProbe {
    var availableIDs: Set<String>

    func isAvailable(_ provider: ProviderDescriptor) async -> Bool {
        availableIDs.contains(provider.id)
    }
}

struct MemoryChatProvider: ChatProvider {
    var deltas: [ChatDelta]
    var verifyError: ChatError?

    func stream(
        _: [Turn], tools _: [ToolSpec]
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        let deltas = self.deltas
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {
        if let verifyError { throw verifyError }
        _ = (key, provider)
    }
}

/// File-scoped: Swift 6 rejects a nested type inside a generic function
/// (TestKit.runAsync's Box), so the harness box lives here.
/// Detached: an inherited MainActor Task would deadlock on the semaphore.
private final class WaitBox<T: Sendable>: @unchecked Sendable {
    var result: Result<T, Error>?
}

func waitAsync<T: Sendable>(
    _ body: @escaping @Sendable () async throws -> T
) throws -> T {
    let box = WaitBox<T>()
    let lock = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await body()) }
        catch { box.result = .failure(error) }
        lock.signal()
    }
    if lock.wait(timeout: .now() + 5) == .timedOut {
        throw CancellationError()
    }
    switch box.result {
    case .success(let value): return value
    case .failure(let error): throw error
    case nil: throw CancellationError()
    }
}

final class MemoryConversationStore: ConversationStoring, @unchecked Sendable {
    private var records: [String: ConversationRecord] = [:]

    func list() throws -> [ConversationMeta] {
        records.values.map {
            ConversationMeta(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
        }
    }

    func save(_ record: ConversationRecord) throws {
        records[record.id] = record
    }

    func load(_ id: String) throws -> ConversationRecord? {
        records[id]
    }
}

@MainActor func testPortFakes() {
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    let store: any ConversationStoring = MemoryConversationStore()
    do {
        expect(try store.load("missing") == nil,
               "store: load ausente es nil")
        expect(try store.list().isEmpty, "store: list vacío")
    } catch {
        expect(false, "store: list/load vacíos no debían tirar \(error)")
    }

    let record = ConversationRecord(
        id: "c1", title: "Hola", updatedAt: stamp,
        messages: [ConversationMessage(role: "user", text: "hey")])
    do {
        try store.save(record)
        expectEq(try store.load("c1"), record, "store: save luego load")
        let listed = try store.list()
        expectEq(listed.count, 1, "store: list ve el guardado")
        expectEq(listed.first?.id, "c1", "store: meta.id")
        expectEq(listed.first?.title, "Hola", "store: meta.title")
    } catch {
        expect(false, "store: no debía tirar \(error)")
    }

    let probe: any CapabilityProbe = MemoryProbe(
        availableIDs: [ProviderDescriptor.ollama.id])
    do {
        let ollama = try waitAsync {
            await probe.isAvailable(.ollama)
        }
        let openai = try waitAsync {
            await probe.isAvailable(.openAI)
        }
        expect(ollama, "probe: Ollama marcado disponible")
        expect(!openai, "probe: OpenAI no listado es false")
    } catch {
        expect(false, "probe: isAvailable no debía tirar \(error)")
    }

    let provider: any ChatProvider = MemoryChatProvider(
        deltas: [
            .text("Hola"),
            .handoff(Handoff(goal: "leer", context: "")),
        ],
        verifyError: nil)
    do {
        let history = [Turn(role: .user, content: "hola")]
        let tools: [ToolSpec] = [.delegate]
        let got = try waitAsync { () async throws -> [ChatDelta] in
            var out: [ChatDelta] = []
            for try await delta in provider.stream(history, tools: tools) {
                out.append(delta)
            }
            return out
        }
        expectEq(got, [
            .text("Hola"),
            .handoff(Handoff(goal: "leer", context: "")),
        ], "provider: stream emite los deltas")
        try waitAsync { () async throws -> Void in
            try await provider.verify("sk-x", provider: .openAI)
        }
        expect(true, "provider: verify feliz no tira")
    } catch {
        expect(false, "provider: fake no debía tirar \(error)")
    }

    let failing: any ChatProvider = MemoryChatProvider(
        deltas: [], verifyError: .unauthorized)
    do {
        try waitAsync { () async throws -> Void in
            try await failing.verify("", provider: .groq)
        }
        expect(false, "provider: verify debía tirar unauthorized")
    } catch let error as ChatError {
        expectEq(error, .unauthorized, "provider: verify propaga ChatError")
    } catch {
        expect(false, "provider: verify debía ser ChatError, no \(error)")
    }
}
