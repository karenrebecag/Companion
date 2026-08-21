import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func secretStoreTests() {
    testKeychainConstants()
    testKeychainConformanceAndEmptyWrite()
    testMemorySecretStoreInServicesSuite()
}

@MainActor func testKeychainConstants() {
    expectEq(KeychainSecretStore.service, "Companion",
             "keychain: el servicio es Companion, no el bundle id")
    expectEq(SecretKey.openAI.rawValue, "OPENAI_API_KEY",
             "keychain: account OpenAI = OPENAI_API_KEY")
    expectEq(SecretKey.groq.rawValue, "GROQ_API_KEY",
             "keychain: account Groq = GROQ_API_KEY")
    expectEq(SecretKey.openRouter.rawValue, "OPENROUTER_API_KEY",
             "keychain: account OpenRouter = OPENROUTER_API_KEY")
}

@MainActor func testKeychainConformanceAndEmptyWrite() {
    let store: any SecretStore = KeychainSecretStore()
    _ = store

    do {
        try KeychainSecretStore().write(.openAI, value: "")
        expect(false, "keychain: vacío debía tirar emptyValue")
    } catch let error as SecretStoreError {
        expectEq(error, .emptyValue, "keychain: vacío tira emptyValue")
    } catch {
        expect(false, "keychain: vacío debía ser SecretStoreError, no \(error)")
    }

    do {
        try KeychainSecretStore().write(.groq, value: "  \n\t  ")
        expect(false, "keychain: solo espacios debía tirar emptyValue")
    } catch let error as SecretStoreError {
        expectEq(error, .emptyValue, "keychain: recortado vacío tira emptyValue")
    } catch {
        expect(false, "keychain: espacios debía ser SecretStoreError, no \(error)")
    }
}

/// CI stand-in: never call SecItem. MemorySecretStore lives in ChatTypesTests.
@MainActor func testMemorySecretStoreInServicesSuite() {
    let store: any SecretStore = MemorySecretStore()

    do {
        expect(try store.read(.openAI) == nil,
               "memory: ausente es nil, no error")
    } catch {
        expect(false, "memory: leer ausente no debía tirar \(error)")
    }

    do {
        try store.write(.openAI, value: "  sk-live  \n")
        expectEq(try store.read(.openAI), "sk-live",
                 "memory: escribe, recorta y lee")
        expect(try store.read(.groq) == nil,
               "memory: una clave no pisa la otra")

        try store.write(.openAI, value: "sk-nueva")
        expectEq(try store.read(.openAI), "sk-nueva",
                 "memory: el segundo write pisa")

        try store.write(.openRouter, value: "ñoño-key")
        expectEq(try store.read(.openRouter), "ñoño-key",
                 "memory: unicode en el valor")

        try store.delete(.openAI)
        expect(try store.read(.openAI) == nil, "memory: delete deja nil")
        expectEq(try store.read(.openRouter), "ñoño-key",
                 "memory: delete no toca otras claves")

        try store.delete(.openAI)
        expect(try store.read(.openAI) == nil,
               "memory: delete de ausente no truena")
    } catch {
        expect(false, "memory: el camino feliz no debía tirar \(error)")
    }

    do {
        try store.write(.groq, value: "")
        expect(false, "memory: vacío debía tirar emptyValue")
    } catch let error as SecretStoreError {
        expectEq(error, .emptyValue, "memory: vacío tira emptyValue")
    } catch {
        expect(false, "memory: vacío debía ser SecretStoreError, no \(error)")
    }
}
