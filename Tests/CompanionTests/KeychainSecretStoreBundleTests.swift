import CompanionCore
@testable import CompanionServices
import Foundation
import Security
import Testing

@Test @MainActor func keychainSecretStoreBundleTests() {
    testRoundTripInOneItem()
    testTwoKeysProduceOneStoredItem()
    testMigrationMovesLegacyItemsAndDeletesThemAfterBundleWrite()
    testMigrationKeepsLegacyItemsWhenBundleWriteFails()
    testLegacyReadFailureOtherThanNotFoundPropagates()
    testCorruptBundleThrowsAndIsNotOverwritten()
    testSecondReadInSameInstanceDoesNotHitTheKeychain()
    testConcurrentWritesToDifferentKeysDoNotDropEachOther()
    testMigrationDeleteFailureForOneLegacyItemDoesNotStopTheRestOrThrow()
    testAGroqKeyInTheBundleIsPurgedOnLoad()
    testALegacyGroqItemIsDeletedNeverMigrated()
    testALegacyGroqItemBesideABundleIsDeletedOnLoad()
}

/// L1 (security review 2026-09-24): the standalone legacy Groq item was
/// only purged when no bundle existed. Beside an existing bundle it stayed
/// in the Keychain for good.
@MainActor func testALegacyGroqItemBesideABundleIsDeletedOnLoad() {
    let fake = FakeKeychainOperations()
    let seeded = try! JSONEncoder().encode([SecretKey.openAI.rawValue: "sk-live"])
    fake.seedRaw(account: bundleAccount, data: seeded)
    fake.seed(account: SecretKey.groq.rawValue, value: "legacy-groq")
    let store = KeychainSecretStore(backend: fake)
    do {
        expectEq(try store.read(.openAI), "sk-live", "L1: el bundle se sirve igual")
    } catch {
        expect(false, "L1: no debia tirar \(error)")
    }
    expect(!fake.hasItem(account: SecretKey.groq.rawValue),
           "L1: el item legacy de Groq se borra aunque exista el bundle")
    expectEq(fake.storedItemCount, 1, "L1: solo queda el bundle")
}

/// 15e-2: Groq is gone from the app and Ajustes has no row to delete its
/// key, so a key saved before 15e would sit in the Keychain forever. The
/// first load drops it from the bundle and persists the result.
@MainActor func testAGroqKeyInTheBundleIsPurgedOnLoad() {
    let fake = FakeKeychainOperations()
    let seeded = try! JSONEncoder().encode([
        SecretKey.openAI.rawValue: "sk-live", SecretKey.groq.rawValue: "gsk-old",
    ])
    fake.seedRaw(account: bundleAccount, data: seeded)
    let store = KeychainSecretStore(backend: fake)

    do {
        expectEq(try store.read(.openAI), "sk-live", "purga: las demás claves siguen")
        expectEq(try store.read(.groq), nil, "purga: la clave de Groq ya no se lee")
    } catch {
        expect(false, "purga: no debia tirar \(error)")
    }
    let stored = fake.rawData(account: bundleAccount).flatMap {
        try? JSONDecoder().decode([String: String].self, from: $0)
    } ?? [:]
    expectEq(stored, [SecretKey.openAI.rawValue: "sk-live"],
             "purga: el bundle guardado ya no contiene Groq")
}

/// 15e-2: an install old enough to still hold per-key items must not carry
/// the Groq key into the bundle; its item is deleted all the same.
@MainActor func testALegacyGroqItemIsDeletedNeverMigrated() {
    let fake = FakeKeychainOperations()
    fake.seed(account: SecretKey.openAI.rawValue, value: "legacy-openai")
    fake.seed(account: SecretKey.groq.rawValue, value: "legacy-groq")
    let store = KeychainSecretStore(backend: fake)
    do {
        expectEq(try store.read(.openAI), "legacy-openai", "legacy: OpenAI migra")
        expectEq(try store.read(.groq), nil, "legacy: Groq no migra")
    } catch {
        expect(false, "legacy: no debia tirar \(error)")
    }
    expect(!fake.hasItem(account: SecretKey.groq.rawValue), "legacy: el item de Groq se borro")
    let stored = fake.rawData(account: bundleAccount).flatMap {
        try? JSONDecoder().decode([String: String].self, from: $0)
    } ?? [:]
    expect(stored[SecretKey.groq.rawValue] == nil, "legacy: el bundle nunca ve Groq")

    let onlyGroq = FakeKeychainOperations()
    onlyGroq.seed(account: SecretKey.groq.rawValue, value: "legacy-groq")
    do {
        expectEq(try KeychainSecretStore(backend: onlyGroq).read(.groq), nil,
                 "solo groq: nada que leer")
    } catch {
        expect(false, "solo groq: no debia tirar \(error)")
    }
    expectEq(onlyGroq.storedItemCount, 0, "solo groq: el llavero queda vacio")
}

/// In-memory stand-in for the login keychain. Keyed by "service|account" —
/// the same two attributes `KeychainSecretStore` queries on — so the fake
/// tells one account's item from another exactly like `SecItem*` would.
final class FakeKeychainOperations: KeychainOperations, @unchecked Sendable {
    // The real SecItem* calls are serialized by the OS; this fake needs its
    // own lock so concurrency tests race `KeychainSecretStore`'s logic
    // instead of tripping over an unsynchronized dictionary in the double.
    private let itemsLock = NSLock()
    private var items: [String: Data] = [:]
    private var _copyCalls = 0
    var copyCalls: Int { itemsLock.lock(); defer { itemsLock.unlock() }; return _copyCalls }

    /// Forces the next `addItem` to fail — the only way `write` on a bundle
    /// that has never existed can fail.
    var addError: OSStatus?
    /// Forces the next `updateItem` to fail.
    var updateError: OSStatus?
    /// Forces `copyItemData` for one specific account to fail with a given
    /// status instead of returning whatever is (or isn't) stored.
    var copyErrorAccount: String?
    var copyErrorStatus: OSStatus?
    /// Forces `deleteItem` for one specific account to fail with a given
    /// status, to exercise "one legacy delete fails, the rest still run".
    var deleteErrorAccount: String?
    var deleteErrorStatus: OSStatus?
    /// Blocks inside `addItem`/`updateItem` before touching storage, widening
    /// the window between a writer's load and its persist so concurrent
    /// writers to different keys deterministically overlap instead of
    /// racing on a matter of microseconds. Zero by default: every other test
    /// keeps its original timing.
    var operationDelay: TimeInterval = 0

    private func key(_ dict: [String: Any]) -> String {
        let service = dict[kSecAttrService as String] as? String ?? ""
        let account = dict[kSecAttrAccount as String] as? String ?? ""
        return "\(service)|\(account)"
    }

    func copyItemData(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        itemsLock.lock()
        defer { itemsLock.unlock() }
        _copyCalls += 1
        let account = query[kSecAttrAccount as String] as? String
        if let copyErrorAccount, account == copyErrorAccount, let copyErrorStatus {
            return (copyErrorStatus, nil)
        }
        guard let data = items[key(query)] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func addItem(attributes: [String: Any]) -> OSStatus {
        if operationDelay > 0 { Thread.sleep(forTimeInterval: operationDelay) }
        itemsLock.lock()
        defer { itemsLock.unlock() }
        if let addError { return addError }
        items[key(attributes)] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func updateItem(query: [String: Any], attributesToUpdate: [String: Any]) -> OSStatus {
        if operationDelay > 0 { Thread.sleep(forTimeInterval: operationDelay) }
        itemsLock.lock()
        defer { itemsLock.unlock() }
        if let updateError { return updateError }
        let storageKey = key(query)
        guard items[storageKey] != nil else { return errSecItemNotFound }
        items[storageKey] = attributesToUpdate[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func deleteItem(query: [String: Any]) -> OSStatus {
        itemsLock.lock()
        defer { itemsLock.unlock() }
        let account = query[kSecAttrAccount as String] as? String
        if let deleteErrorAccount, account == deleteErrorAccount, let deleteErrorStatus {
            return deleteErrorStatus
        }
        guard items.removeValue(forKey: key(query)) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }

    // MARK: - Test setup / assertions

    func seed(account: String, value: String) {
        itemsLock.lock(); defer { itemsLock.unlock() }
        items["Companion|\(account)"] = Data(value.utf8)
    }

    func seedRaw(account: String, data: Data) {
        itemsLock.lock(); defer { itemsLock.unlock() }
        items["Companion|\(account)"] = data
    }

    func hasItem(account: String) -> Bool {
        itemsLock.lock(); defer { itemsLock.unlock() }
        return items["Companion|\(account)"] != nil
    }

    func rawData(account: String) -> Data? {
        itemsLock.lock(); defer { itemsLock.unlock() }
        return items["Companion|\(account)"]
    }

    var storedItemCount: Int { itemsLock.lock(); defer { itemsLock.unlock() }; return items.count }
}

private let bundleAccount = "secrets.v1"

@MainActor func testRoundTripInOneItem() {
    let fake = FakeKeychainOperations()
    let store = KeychainSecretStore(backend: fake)

    do {
        try store.write(.openAI, value: "sk-live")
        expectEq(try store.read(.openAI), "sk-live", "bundle: escribe y lee")

        try store.delete(.openAI)
        expect(try store.read(.openAI) == nil, "bundle: delete deja nil")
        expect(fake.hasItem(account: bundleAccount),
               "bundle: delete no borra el item, solo la clave adentro")
    } catch {
        expect(false, "bundle: round trip no debia tirar \(error)")
    }
}

@MainActor func testTwoKeysProduceOneStoredItem() {
    let fake = FakeKeychainOperations()
    let store = KeychainSecretStore(backend: fake)

    do {
        try store.write(.openAI, value: "a")
        try store.write(.openRouter, value: "b")
        expectEq(try store.read(.openAI), "a", "bundle: primera clave")
        expectEq(try store.read(.openRouter), "b", "bundle: segunda clave")
    } catch {
        expect(false, "bundle: dos claves no debia tirar \(error)")
    }
    expectEq(fake.storedItemCount, 1,
             "bundle: dos claves, un solo item en el llavero")
}

@MainActor func testMigrationMovesLegacyItemsAndDeletesThemAfterBundleWrite() {
    let fake = FakeKeychainOperations()
    fake.seed(account: SecretKey.openAI.rawValue, value: "legacy-openai")
    fake.seed(account: SecretKey.openRouter.rawValue, value: "legacy-openrouter")
    let store = KeychainSecretStore(backend: fake)

    do {
        expectEq(try store.read(.openAI), "legacy-openai",
                 "migracion: la clave legacy aparece bajo el bundle")
        expectEq(try store.read(.openRouter), "legacy-openrouter",
                 "migracion: la segunda clave legacy tambien")
    } catch {
        expect(false, "migracion: no debia tirar \(error)")
    }

    expect(fake.hasItem(account: bundleAccount), "migracion: el bundle quedo escrito")
    expect(!fake.hasItem(account: SecretKey.openAI.rawValue),
           "migracion: el item legacy de openai se borro")
    expect(!fake.hasItem(account: SecretKey.openRouter.rawValue),
           "migracion: el item legacy de openrouter se borro")
    expectEq(fake.storedItemCount, 1, "migracion: solo queda el bundle")
}

@MainActor func testMigrationKeepsLegacyItemsWhenBundleWriteFails() {
    let fake = FakeKeychainOperations()
    fake.seed(account: SecretKey.openAI.rawValue, value: "legacy-openai")
    // Bundle item never existed: update fails not-found, so write falls
    // through to add — which is the call this test makes fail.
    fake.addError = errSecInteractionNotAllowed
    let store = KeychainSecretStore(backend: fake)

    do {
        _ = try store.read(.openAI)
        expect(false, "migracion: el bundle que no se pudo escribir debia tirar")
    } catch {
        // expected — the bundle write failed, migration must not have
        // deleted the source of truth.
    }

    expect(fake.hasItem(account: SecretKey.openAI.rawValue),
           "migracion: si el bundle no se escribio, el legacy sigue ahi")
    expect(!fake.hasItem(account: bundleAccount),
           "migracion: sin bundle escrito, no debe aparecer a medias")
}

@MainActor func testLegacyReadFailureOtherThanNotFoundPropagates() {
    let fake = FakeKeychainOperations()
    fake.seed(account: SecretKey.openAI.rawValue, value: "legacy-openai")
    fake.copyErrorAccount = SecretKey.openRouter.rawValue
    fake.copyErrorStatus = errSecAuthFailed
    let store = KeychainSecretStore(backend: fake)

    do {
        _ = try store.read(.openAI)
        expect(false,
               "migracion: un error real leyendo una clave legacy debe propagarse, nunca perderse en silencio")
    } catch let error as SecretStoreError {
        expectEq(error, .denied, "migracion: errSecAuthFailed se traduce a denied")
    } catch {
        expect(false, "migracion: error inesperado \(error)")
    }
}

@MainActor func testCorruptBundleThrowsAndIsNotOverwritten() {
    let fake = FakeKeychainOperations()
    let garbage = Data("not json at all".utf8)
    fake.seedRaw(account: bundleAccount, data: garbage)
    let store = KeychainSecretStore(backend: fake)

    do {
        _ = try store.read(.openAI)
        expect(false, "bundle corrupto: leer debia tirar, no devolver datos a medias")
    } catch {
        // expected
    }

    expectEq(fake.rawData(account: bundleAccount), garbage,
             "bundle corrupto: nunca se sobreescribe, se preserva para diagnostico")
}

@MainActor func testSecondReadInSameInstanceDoesNotHitTheKeychain() {
    let fake = FakeKeychainOperations()
    let store = KeychainSecretStore(backend: fake)

    do {
        try store.write(.openAI, value: "sk-live")
    } catch {
        expect(false, "cache: el write inicial no debia tirar \(error)")
    }

    let callsAfterWrite = fake.copyCalls
    do {
        expectEq(try store.read(.openAI), "sk-live", "cache: primera lectura")
        expectEq(try store.read(.openAI), "sk-live", "cache: segunda lectura")
        expectEq(try store.read(.openRouter), nil, "cache: tercera lectura, otra clave")
    } catch {
        expect(false, "cache: no debia tirar \(error)")
    }
    expectEq(fake.copyCalls, callsAfterWrite,
             "cache: leer despues de escribir no vuelve a tocar el llavero")
}

/// Reproduces the load -> mutate-a-local-copy -> persist race: each `write`
/// only takes the lock around the cache check and around the cache update,
/// never around the whole sequence, so two writers to DIFFERENT keys can
/// both snapshot the same stale bundle and the later persist silently
/// overwrites the earlier writer's key with a bundle that never saw it.
/// `operationDelay` widens the window between snapshot and persist so all
/// four writers are guaranteed to read the same primed, still-empty cache
/// before any of them commits — no luck involved.
@MainActor func testConcurrentWritesToDifferentKeysDoNotDropEachOther() {
    let fake = FakeKeychainOperations()
    fake.operationDelay = 0.05
    let store = KeychainSecretStore(backend: fake)

    // Prime the cache first so every writer starts from the same known,
    // already-loaded bundle instead of also racing the first-load/migration
    // path — that is a separate concern from the one under test here.
    do {
        _ = try store.read(.openAI)
    } catch {
        expect(false, "concurrencia: el priming no debia tirar \(error)")
    }

    let keys: [SecretKey] = [.openAI, .cerebras, .openRouter, .brave]
    let group = DispatchGroup()
    for key in keys {
        group.enter()
        DispatchQueue.global().async {
            do { try store.write(key, value: "value-\(key.rawValue)") }
            catch { /* asserted via the reads below */ }
            group.leave()
        }
    }
    _ = group.wait(timeout: .now() + 5)

    for key in keys {
        do {
            expectEq(try store.read(key), "value-\(key.rawValue)",
                     "concurrencia: cada clave debe sobrevivir escrituras concurrentes a otras claves")
        } catch {
            expect(false, "concurrencia: leer \(key) no debia tirar \(error)")
        }
    }
    expectEq(fake.storedItemCount, 1,
             "concurrencia: las cuatro claves siguen en un solo item de llavero")
}

/// LOW finding: once the bundle write succeeds it is the source of truth,
/// so a single legacy item that refuses to delete must not stop the rest
/// from being cleaned up, nor turn a successful migration into a thrown
/// error.
@MainActor func testMigrationDeleteFailureForOneLegacyItemDoesNotStopTheRestOrThrow() {
    let fake = FakeKeychainOperations()
    fake.seed(account: SecretKey.openAI.rawValue, value: "legacy-openai")
    fake.seed(account: SecretKey.openRouter.rawValue, value: "legacy-openrouter")
    fake.deleteErrorAccount = SecretKey.openAI.rawValue
    fake.deleteErrorStatus = errSecInteractionNotAllowed
    let store = KeychainSecretStore(backend: fake)

    do {
        expectEq(try store.read(.openAI), "legacy-openai",
                 "migracion: el bundle ya es la fuente de verdad aunque el delete legacy falle")
        expectEq(try store.read(.openRouter), "legacy-openrouter",
                 "migracion: la otra clave tambien migro")
    } catch {
        expect(false,
               "migracion: un delete legacy fallido no debe tirar \(error)")
    }

    expect(fake.hasItem(account: bundleAccount), "migracion: el bundle quedo escrito")
    expect(fake.hasItem(account: SecretKey.openAI.rawValue),
           "migracion: el item legacy que no se pudo borrar sigue ahi, pero no bloquea nada")
    expect(!fake.hasItem(account: SecretKey.openRouter.rawValue),
           "migracion: el resto de los items legacy si se borraron")
}
