import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Security review 2026-09-25, CRITICAL-1. The default URLSession disk cache
// kept API keys (`xi-api-key`, `Authorization`) and request bodies with the
// user's screen/clipboard context in ~/Library/Caches/<bundle>/Cache.db.
// Nothing the app sends or receives may land in a URL cache, and the legacy
// file left by older builds is removed at launch.

@Test @MainActor func urlCacheHygieneTests() async {
    testTransportSessionHasNoCacheAndNoStores()
    testNoStoreConfigurationIsSharedByEveryPath()
    await testAServedResponseNeverReachesAnyURLCache()
    testPurgeRemovesOnlyTheLegacyCacheFilesOfThisBundle()
    testPurgeIsIdempotent()
    testPurgeRefusesABundleIDThatEscapesTheCachesFolder()
    testPurgeNeverFollowsASymlinkedBundleFolder()
}

@MainActor func testTransportSessionHasNoCacheAndNoStores() {
    let config = URLSessionChatTransport().session.configuration
    expect(config.urlCache == nil, "C1: el transporte no tiene URLCache")
    expectEq(config.requestCachePolicy, .reloadIgnoringLocalCacheData,
             "C1: politica de cache ignora lo local")
    expect(config.urlCredentialStorage == nil, "C1: sin credential storage")
    expect(config.httpCookieStorage == nil, "C1: sin cookie storage")
    let custom = URLSessionChatTransport(session: .shared).session.configuration
    expect(custom.urlCache == nil, "C1: pasar .shared no reintroduce la cache")
}

@MainActor func testNoStoreConfigurationIsSharedByEveryPath() {
    let config = NoStoreSession.configuration()
    expect(config.urlCache == nil, "C1: la config comun no tiene URLCache")
    expectEq(config.requestCachePolicy, .reloadIgnoringLocalCacheData,
             "C1: la config comun ignora la cache local")
    let shared = NoStoreSession.shared.configuration
    expect(shared.urlCache == nil, "C1: la sesion de websockets/web_fetch no cachea")
    expect(shared.urlCredentialStorage == nil, "C1: la sesion comun sin credenciales")
}

/// Serves every request with a response that explicitly allows caching, so
/// only the session configuration can keep it out of a cache.
final class CacheableStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Cache-Control": "public, max-age=3600",
                               "Content-Type": "application/json"])
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor func testAServedResponseNeverReachesAnyURLCache() async {
    let transport = URLSessionChatTransport(protocolClasses: [CacheableStubProtocol.self])
    guard let url = URL(string: "https://api.elevenlabs.io/v1/c1-\(UUID().uuidString)")
    else { return expect(false, "C1: url de prueba") }
    var request = URLRequest(url: url)
    request.setValue("sk_\(String(repeating: "a", count: 24))",
                     forHTTPHeaderField: "xi-api-key")
    do {
        let (_, response) = try await transport.data(for: request)
        expectEq(response.statusCode, 200, "C1: el stub respondio")
    } catch {
        return expect(false, "C1: la peticion no debia fallar: \(error)")
    }
    // URLCache writes are asynchronous; give a would-be write time to land.
    await settle(0.3)
    expect(URLCache.shared.cachedResponse(for: request) == nil,
           "C1: URLCache.shared no guarda la respuesta")
    let own = transport.session.configuration.urlCache
    expect(own?.cachedResponse(for: request) == nil,
           "C1: la cache propia de la sesion (si existiera) tampoco")
}

private func makeCaches() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-caches-\(UUID().uuidString)")
}

private func touch(_ url: URL) {
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    } catch {
        expect(false, "C1: no se pudo preparar \(url.lastPathComponent): \(error)")
    }
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

@MainActor func testPurgeRemovesOnlyTheLegacyCacheFilesOfThisBundle() {
    let caches = makeCaches()
    defer { removeQuietly(caches) }
    let own = caches.appendingPathComponent("com.test.companion")
    let legacy = ["Cache.db", "Cache.db-wal", "Cache.db-shm"].map {
        own.appendingPathComponent($0)
    }
    legacy.forEach(touch)
    touch(own.appendingPathComponent("fsCachedData/ABC"))
    let keep = own.appendingPathComponent("tts/phrase.pcm")
    touch(keep)
    let neighbour = caches.appendingPathComponent("com.other.app/Cache.db")
    touch(neighbour)

    let removed = runPurge(caches: caches, bundleID: "com.test.companion")

    expectEq(removed, 4, "C1: borra Cache.db, -wal, -shm y fsCachedData")
    expect(legacy.allSatisfy { !exists($0) }, "C1: no queda ningun Cache.db*")
    expect(!exists(own.appendingPathComponent("fsCachedData")),
           "C1: fsCachedData borrado")
    expect(exists(keep), "C1: el resto de la carpeta del bundle sobrevive")
    expect(exists(neighbour), "C1: la cache de otra app jamas se toca")
}

@MainActor func testPurgeIsIdempotent() {
    let caches = makeCaches()
    defer { removeQuietly(caches) }
    touch(caches.appendingPathComponent("com.test.companion/Cache.db"))
    expectEq(runPurge(caches: caches, bundleID: "com.test.companion"), 1,
             "C1: primera pasada borra")
    expectEq(runPurge(caches: caches, bundleID: "com.test.companion"), 0,
             "C1: segunda pasada no encuentra nada")
    let empty = makeCaches()
    expectEq(runPurge(caches: empty, bundleID: "com.test.companion"), 0,
             "C1: sin carpeta del bundle no hay nada que hacer")
}

@MainActor func testPurgeRefusesABundleIDThatEscapesTheCachesFolder() {
    let caches = makeCaches()
    defer { removeQuietly(caches) }
    let outside = caches.appendingPathComponent("Cache.db")
    touch(outside)
    for bad in ["", ".", "..", "../x", "a/b", "com.x/.."] {
        do {
            _ = try LegacyURLCachePurge.purge(cachesDirectory: caches, bundleID: bad)
            expect(false, "C1: bundle id '\(bad)' debia rechazarse")
        } catch {
            expect(error is LegacyURLCachePurge.Refusal,
                   "C1: '\(bad)' se rechaza con Refusal")
        }
    }
    expect(exists(outside), "C1: nada fuera de la carpeta del bundle se borra")
}

@MainActor func testPurgeNeverFollowsASymlinkedBundleFolder() {
    let caches = makeCaches()
    let elsewhere = makeCaches()
    defer { removeQuietly(caches); removeQuietly(elsewhere) }
    let target = elsewhere.appendingPathComponent("Cache.db")
    touch(target)
    do {
        try FileManager.default.createDirectory(
            at: caches, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: caches.appendingPathComponent("com.test.companion"),
            withDestinationURL: elsewhere)
    } catch {
        return expect(false, "C1: no se pudo crear el symlink: \(error)")
    }
    expectEq(runPurge(caches: caches, bundleID: "com.test.companion"), 0,
             "C1: una carpeta de bundle que es symlink no se recorre")
    expect(exists(target), "C1: el destino del symlink sobrevive")
}

private func runPurge(caches: URL, bundleID: String) -> Int {
    do {
        return try LegacyURLCachePurge.purge(cachesDirectory: caches, bundleID: bundleID)
    } catch {
        expect(false, "C1: purge no debia fallar: \(error)")
        return -1
    }
}

private func removeQuietly(_ url: URL) {
    do { try FileManager.default.removeItem(at: url) } catch {
        // Temp dir cleanup; a leftover is harmless to the assertion above.
    }
}
