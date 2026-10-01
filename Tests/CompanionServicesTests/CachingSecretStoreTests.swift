import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func cachingSecretStoreTests() {
    testRepeatedReadsHitTheKeychainOnce()
    testAbsenceIsCachedToo()
    testWriteInvalidates()
    testDeleteInvalidates()
    testFailuresAreNotCached()
    testKeysAreCachedIndependently()
    testATurnCostsOneReadPerKey()
}

final class CountingSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretKey: String]
    private var _reads = 0
    var failure: Error?

    init(_ values: [SecretKey: String] = [:]) { self.values = values }

    var reads: Int { lock.lock(); defer { lock.unlock() }; return _reads }

    func read(_ key: SecretKey) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        _reads += 1
        if let failure { throw failure }
        return values[key]
    }

    func write(_ key: SecretKey, value: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func delete(_ key: SecretKey) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

@MainActor private func read(_ store: CachingSecretStore, _ key: SecretKey)
    -> String?
{
    do { return try store.read(key) } catch { return nil }
}

@MainActor func testRepeatedReadsHitTheKeychainOnce() {
    // Cada lectura del llavero puede ser un dialogo de contrasena cuando el
    // ACL del item no reconoce a la app. Tres por mensaje eran tres dialogos.
    let inner = CountingSecretStore([.openAI: "sk-test"])
    let store = CachingSecretStore(inner)
    expectEq(read(store, .openAI), "sk-test", "primera lectura")
    expectEq(read(store, .openAI), "sk-test", "segunda")
    expectEq(read(store, .openAI), "sk-test", "tercera")
    expectEq(inner.reads, 1, "el llavero se toca una sola vez")
}

@MainActor func testAbsenceIsCachedToo() {
    // El caso de la base local: NO hay clave, y preguntarlo repetidamente
    // cuesta lo mismo que preguntarlo teniendola.
    let inner = CountingSecretStore()
    let store = CachingSecretStore(inner)
    expect(read(store, .openAI) == nil, "no hay clave")
    expect(read(store, .openAI) == nil, "sigue sin haberla")
    expectEq(inner.reads, 1, "y la ausencia tambien se recuerda")
}

@MainActor func testWriteInvalidates() {
    let inner = CountingSecretStore([.openAI: "vieja"])
    let store = CachingSecretStore(inner)
    expectEq(read(store, .openAI), "vieja", "lee la vieja")
    do {
        try store.write(.openAI, value: "nueva")
    } catch {
        expect(false, "write no debia tirar: \(error)")
    }
    expectEq(read(store, .openAI), "nueva",
             "tras escribir, la cache no puede seguir sirviendo la vieja")
}

@MainActor func testDeleteInvalidates() {
    let inner = CountingSecretStore([.openAI: "sk-test"])
    let store = CachingSecretStore(inner)
    expectEq(read(store, .openAI), "sk-test", "estaba")
    do {
        try store.delete(.openAI)
    } catch {
        expect(false, "delete no debia tirar: \(error)")
    }
    expect(read(store, .openAI) == nil, "borrar de verdad borra")
}

@MainActor func testFailuresAreNotCached() {
    // Un llavero que dice que no puede ser temporal (bloqueado, permiso
    // denegado). Recordar el fallo condenaria la sesion entera.
    let inner = CountingSecretStore([.openAI: "sk-test"])
    inner.failure = SecretStoreError.denied
    let store = CachingSecretStore(inner)
    expect(read(store, .openAI) == nil, "primer intento falla")
    inner.failure = nil
    expectEq(read(store, .openAI), "sk-test", "y el siguiente vuelve a intentar")
}

@MainActor func testKeysAreCachedIndependently() {
    let inner = CountingSecretStore([.openAI: "a", .cerebras: "b"])
    let store = CachingSecretStore(inner)
    expectEq(read(store, .openAI), "a", "openai")
    expectEq(read(store, .cerebras), "b", "cerebras")
    expectEq(read(store, .openAI), "a", "openai otra vez")
    expectEq(inner.reads, 2, "una lectura por clave, no una por llamada")
}

@MainActor func testATurnCostsOneReadPerKey() {
    // La forma real del bucle de routing: por proveedor con clave se lee en el
    // guardia y otra vez al pasarla al intento. Con el decorador, un turno
    // completo cuesta una lectura por clave y no cinco.
    let inner = CountingSecretStore([.openAI: "a", .cerebras: "b"])
    let store = CachingSecretStore(inner)
    for _ in 0 ..< 3 {
        _ = read(store, .openAI)
        _ = read(store, .openAI)
        _ = read(store, .cerebras)
    }
    expectEq(inner.reads, 2, "un turno entero: dos lecturas del llavero")
}
