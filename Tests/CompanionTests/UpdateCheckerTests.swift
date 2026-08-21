import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test @MainActor func updateCheckerTests() async {
    testSemver()
    testParseFixtures()
    await testDayCacheSkipsNetwork()
    await testHostileAPIIsSilent()
    await testExplicitCheckBypassesCache()
}

@MainActor func testSemver() {
    expect(SemanticVersion("0.8.0")! > SemanticVersion("0.7.0")!,
           "semver: mayor gana")
    expect(SemanticVersion("v1.0.0")! > SemanticVersion("0.9.9")!,
           "semver: acepta el prefijo v")
    expect(!(SemanticVersion("0.7.0")! > SemanticVersion("0.7.0")!),
           "semver: igual no es mayor")
    expect(SemanticVersion("0.8.0-beta") == nil,
           "semver: los prerelease jamás se ofrecen")
    expect(SemanticVersion("garbage") == nil, "semver: basura es nil")
    expect(SemanticVersion("1.2") == nil, "semver: incompleta es nil")
}

@MainActor func testParseFixtures() {
    func fixture(tag: String, url: String = "https://github.com/x/releases/1") -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url])
    }
    expectEq(UpdateChecker.parse(fixture(tag: "v0.8.0"), current: "0.7.0")?.tag,
             "v0.8.0", "parse: hay nueva ⇒ la ofrece")
    expect(UpdateChecker.parse(fixture(tag: "0.7.0"), current: "0.7.0") == nil,
           "parse: al día ⇒ nada")
    expect(UpdateChecker.parse(fixture(tag: "0.6.0"), current: "0.7.0") == nil,
           "parse: remota vieja ⇒ nada")
    expect(UpdateChecker.parse(fixture(tag: "0.8.0-rc1"), current: "0.7.0") == nil,
           "parse: prerelease ⇒ nada")
    expect(UpdateChecker.parse(
        fixture(tag: "0.8.0", url: "http://evil.example/x"), current: "0.7.0") == nil,
           "parse: página sin https ⇒ nada")
    expect(UpdateChecker.parse(Data("no json".utf8), current: "0.7.0") == nil,
           "parse: payload roto ⇒ silencio")
}

@MainActor func testDayCacheSkipsNetwork() async {
    let transport = CountingTransport(tag: "9.9.9")
    let clockDay = Date(timeIntervalSince1970: 1_000_000)
    let store = DateBox()
    let checker = UpdateChecker(
        transport: transport, currentVersion: "0.7.0",
        now: { clockDay },
        lastCheck: { store.value }, recordCheck: { store.value = $0 })
    _ = await checker.checkIfDue()
    _ = await checker.checkIfDue()
    expectEq(transport.calls, 1, "cache: una sola consulta por día")
}

@MainActor func testHostileAPIIsSilent() async {
    let checker = UpdateChecker(
        transport: FailingTransport(), currentVersion: "0.7.0",
        now: { Date(timeIntervalSince1970: 0) },
        lastCheck: { nil }, recordCheck: { _ in })
    let result = await checker.checkNow()
    expect(result == nil, "sin red: silencio absoluto, jamás un error")
}

@MainActor func testExplicitCheckBypassesCache() async {
    let transport = CountingTransport(tag: "9.9.9")
    let today = Date(timeIntervalSince1970: 2_000_000)
    let store = DateBox()
    store.value = today
    let checker = UpdateChecker(
        transport: transport, currentVersion: "0.7.0",
        now: { today },
        lastCheck: { store.value }, recordCheck: { store.value = $0 })
    let result = await checker.checkNow()
    expectEq(transport.calls, 1, "a demanda: ignora el cache del día")
    expectEq(result?.tag, "9.9.9", "a demanda: entrega la nueva")
}

// MARK: - Fakes

private final class CountingTransport: ChatTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let tag: String
    private var count = 0
    var calls: Int { lock.withLock { count } }

    init(tag: String) { self.tag = tag }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { count += 1 }
        let body = try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "html_url": "https://github.com/x/releases/1",
        ])
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    func lines(for request: URLRequest) async throws
        -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        throw ChatError.unreachable
    }
}

private struct FailingTransport: ChatTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ChatError.unreachable
    }
    func lines(for request: URLRequest) async throws
        -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        throw ChatError.unreachable
    }
}

private final class DateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date?
    var value: Date? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
