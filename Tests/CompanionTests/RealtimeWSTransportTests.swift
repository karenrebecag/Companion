import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func realtimeWSTransportTests() {
    testOpenConnectsWithBearer()
    testSendForwardsJSON()
    testPumpParsesEvents()
    testCloseFinishesStream()
    testReceiveThrowMarksClosed()
    testConnectErrorMapping()
    testSendEdges()
    testReopenAndDefaultInit()
    testHandshakeStatusMap()
}

@MainActor func testOpenConnectsWithBearer() {
    let socket = FakeSocket()
    let connector = FakeConnector(socket)
    let transport = RealtimeWSTransport(connector: connector)
    let url = wsURL()
    runOk("open: connect") {
        try await transport.open(key: "sk-live", url: url)
        await transport.close()
    }
    expectEq(connector.urls, [url], "open: url al connector")
    expectEq(connector.bearers, ["Bearer sk-live"], "open: Authorization Bearer")

    let extra = FakeConnector(FakeSocket())
    runOk("open: key vacía y unicode") {
        let t = RealtimeWSTransport(connector: extra)
        try await t.open(key: "", url: url)
        await t.close()
        try await t.open(key: "sk-ñoño — café", url: url)
    }
    expectEq(extra.bearers, ["Bearer ", "Bearer sk-ñoño — café"],
             "open: key vacía y unicode exactas")
}

@MainActor func testSendForwardsJSON() {
    let socket = FakeSocket()
    let transport = RealtimeWSTransport(connector: FakeConnector(socket))
    let pcm = Data([0x00, 0xFF, 0x7F, 0x80])
    let append = RealtimeCodec.appendAudio(pcm)
    runOk("send: json") {
        let port: any VoiceTransport = transport
        try await port.open(key: "sk", url: wsURL())
        try await port.send(#"{"type":"session.update"}"#)
        try await port.send("")
        try await port.send("ñoño — café '; DROP")
        try await port.send(append)
        await port.close()
    }
    expectEq(socket.sent, [
        #"{"type":"session.update"}"#, "", "ñoño — café '; DROP", append,
    ], "send: json al socket; appendAudio es send(json)")
}

@MainActor func testPumpParsesEvents() {
    let socket = FakeSocket()
    let transport = RealtimeWSTransport(connector: FakeConnector(socket))
    let pcm = Data("hola".utf8)
    let b64 = pcm.base64EncodedString()
    runOk("pump: parse") {
        let probe = EventProbe(transport.events())
        try await transport.open(key: "sk", url: wsURL())
        socket.yield(#"{"type":"session.created"}"#)
        socket.yield(#"{"type":"session.updated"}"#)
        socket.yield(#"{"type":"input_audio_buffer.speech_started"}"#)
        socket.yield(#"{"type":"rate_limits.updated"}"#)
        socket.yield("basura sin json")
        socket.yield("")
        socket.yield("[]")
        socket.yield("{\"type\":\"response.output_audio.delta\",\"delta\":\"\(b64)\"}")
        socket.yield(
            #"{"type":"response.function_call_arguments.done","name":"delegate","arguments":"{}","call_id":"c1"}"#)
        let got = await probe.collected(9)
        await transport.close()
        expectEq(got, [
            .sessionCreated, .sessionUpdated, .speechStarted,
            .ignored, .ignored, .ignored, .ignored,
            .audioDelta(pcm),
            .functionCall(name: "delegate", arguments: "{}", callId: "c1"),
        ], "pump: RealtimeCodec.parse de cada frame")
    }
}

@MainActor func testCloseFinishesStream() {
    let socket = FakeSocket()
    let transport = RealtimeWSTransport(connector: FakeConnector(socket))
    runOk("close: stream") {
        let probe = EventProbe(transport.events())
        try await transport.open(key: "sk", url: wsURL())
        socket.yield(#"{"type":"session.created"}"#)
        _ = await probe.collected(1)
        await transport.close()
        socket.yield(#"{"type":"session.updated"}"#)
        expectEq(await probe.finishedItems(), [.sessionCreated],
                 "close: termina el stream y no cuela frames tardíos")
        expect(socket.wasClosed, "close: cierra el socket")
        await transport.close()
        expect(socket.wasClosed, "close: idempotente")
    }
}

@MainActor func testReceiveThrowMarksClosed() {
    let socket = FakeSocket()
    let transport = RealtimeWSTransport(connector: FakeConnector(socket))
    runOk("receive throw") {
        let probe = EventProbe(transport.events())
        try await transport.open(key: "sk", url: wsURL())
        socket.fail(URLError(.networkConnectionLost))
        _ = await probe.finishedItems()
        do {
            try await transport.send("x")
            expect(false, "drop: send debía tirar closed")
        } catch let error as VoiceTransportError {
            expectEq(error, .closed, "drop: send closed")
        } catch {
            expect(false, "drop: VoiceTransportError, no \(error)")
        }
    }
}

@MainActor func testConnectErrorMapping() {
    let url = wsURL()
    func expectOpen(_ error: Error, _ want: VoiceTransportError, _ label: String) {
        let connector = FakeConnector(FakeSocket())
        connector.error = error
        expectThrow(want, label) {
            try await RealtimeWSTransport(connector: connector)
                .open(key: "sk-bad", url: url)
        }
    }
    expectOpen(VoiceTransportError.unauthorized, .unauthorized, "open 401")
    expectOpen(VoiceTransportError.timeout, .timeout, "open timeout")
    expectOpen(VoiceTransportError.closed, .closed, "open closed")
    expectOpen(URLError(.cannotFindHost), .unreachable, "open host")
}

@MainActor func testSendEdges() {
    let url = wsURL()
    expectThrow(.closed, "send sin open") {
        try await RealtimeWSTransport(connector: FakeConnector())
            .send(#"{"type":"x"}"#)
    }

    let socket = FakeSocket()
    let transport = RealtimeWSTransport(connector: FakeConnector(socket))
    runOk("send after close") {
        try await transport.open(key: "sk", url: url)
        await transport.close()
        await expectClosed(transport, "send after close")
    }

    let failing = FakeSocket()
    failing.sendError = URLError(.networkConnectionLost)
    let broken = RealtimeWSTransport(connector: FakeConnector(failing))
    runOk("send error") {
        try await broken.open(key: "sk", url: url)
        await expectClosed(broken, "send fail → closed")
        await broken.close()
    }

    let large = String(repeating: "a", count: 10_000)
    let big = FakeSocket()
    runOk("send 10k") {
        let t = RealtimeWSTransport(connector: FakeConnector(big))
        try await t.open(key: "sk", url: url)
        try await t.send(large)
        await t.close()
    }
    expectEq(big.sent, [large], "send: 10k chars")
}

@MainActor func testReopenAndDefaultInit() {
    let first = FakeSocket()
    let second = FakeSocket()
    let connector = FakeConnector(queue: [first, second])
    let transport = RealtimeWSTransport(connector: connector)
    runOk("reopen") {
        try await transport.open(key: "a", url: wsURL())
        await transport.close()
        expect(first.wasClosed, "reopen: cierra el socket previo")
        try await transport.open(key: "b", url: wsURL())
        let probe = EventProbe(transport.events())
        second.yield(#"{"type":"response.done"}"#)
        expectEq(await probe.collected(1), [.responseDone],
                 "reopen: el stream nuevo recibe")
        try await transport.send("hi")
        await transport.close()
    }
    expectEq(connector.bearers, ["Bearer a", "Bearer b"], "reopen: dos connects")
    expectEq(second.sent, ["hi"], "reopen: send al socket nuevo")

    let port: any VoiceTransport = RealtimeWSTransport()
    _ = port.events()
    runOk("close sin open") { await port.close() }
    runOk("open no espera session.updated") {
        let socket = FakeSocket()
        let t = RealtimeWSTransport(connector: FakeConnector(socket))
        try await t.open(key: "sk", url: wsURL())
        try await t.send(#"{"type":"session.update"}"#)
        await t.close()
        expectEq(socket.sent, [#"{"type":"session.update"}"#],
                 "open: retorna al conectar, sin esperar eventos")
    }
}

@MainActor func testHandshakeStatusMap() {
    let map = URLSessionRealtimeConnector.mapFailure
    let net = URLError(.badServerResponse)
    expectEq(map(401, net), .unauthorized, "handshake: 401 → unauthorized")
    expectEq(map(500, net), .unreachable, "handshake: 500 → unreachable")
    expectEq(map(nil, VoiceTransportError.timeout), .timeout,
             "handshake: VoiceTransportError se propaga")
    expectEq(map(nil, URLError(.cannotFindHost)), .unreachable,
             "handshake: URLError → unreachable")
    expectEq(map(403, VoiceTransportError.unauthorized), .unauthorized,
             "handshake: no-401 no pisa VoiceTransportError")
}

func wsURL() -> URL {
    URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime")!
}

func expectClosed(_ transport: RealtimeWSTransport, _ label: String) async {
    do {
        try await transport.send("x")
        expect(false, "\(label): debía closed")
    } catch let error as VoiceTransportError {
        expectEq(error, .closed, label)
    } catch {
        expect(false, "\(label): VoiceTransportError, no \(error)")
    }
}

final class FakeSocket: RealtimeSocketing, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [String] = []
    private var queue: [Result<String, Error>] = []
    private var waiters: [CheckedContinuation<String, Error>] = []
    private var closed = false
    var sendError: Error?

    var sent: [String] { locked { _sent } }
    var wasClosed: Bool { locked { closed } }
    func send(text: String) async throws { try recordSend(text) }
    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { enqueue($0) }
    }
    func close() async {
        for waiter in failWaiters() {
            waiter.resume(throwing: VoiceTransportError.closed)
        }
    }

    func yield(_ text: String) { resume(.success(text)) }
    func fail(_ error: Error) { resume(.failure(error)) }
    private func recordSend(_ text: String) throws {
        try locked {
            if closed { throw VoiceTransportError.closed }
            if let sendError { throw sendError }
            _sent.append(text)
        }
    }

    private func enqueue(_ cont: CheckedContinuation<String, Error>) {
        lock.lock()
        if closed {
            lock.unlock()
            cont.resume(throwing: VoiceTransportError.closed)
            return
        }
        if !queue.isEmpty {
            let next = queue.removeFirst()
            lock.unlock()
            cont.resume(with: next)
            return
        }
        waiters.append(cont)
        lock.unlock()
    }

    private func failWaiters() -> [CheckedContinuation<String, Error>] {
        locked {
            closed = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
    }

    private func resume(_ result: Result<String, Error>) {
        lock.lock()
        if let waiter = waiters.first {
            waiters.removeFirst()
            lock.unlock()
            waiter.resume(with: result)
            return
        }
        queue.append(result)
        lock.unlock()
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

final class FakeConnector: RealtimeConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [FakeSocket]
    private var _urls: [URL] = []
    private var _bearers: [String] = []
    var error: Error?

    init(_ socket: FakeSocket = FakeSocket()) { queue = [socket] }
    init(queue: [FakeSocket]) { self.queue = queue }
    var urls: [URL] { locked { _urls } }
    var bearers: [String] { locked { _bearers } }

    func connect(url: URL, bearer: String) async throws -> any RealtimeSocketing {
        try take(url: url, bearer: bearer)
    }

    private func take(url: URL, bearer: String) throws -> any RealtimeSocketing {
        try locked {
            _urls.append(url)
            _bearers.append(bearer)
            if let error { throw error }
            return queue.isEmpty ? FakeSocket() : queue.removeFirst()
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

final class EventProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RealtimeEvent] = []
    private var waiter: (count: Int, cont: CheckedContinuation<[RealtimeEvent], Never>)?
    private var finished = false

    init(_ stream: AsyncStream<RealtimeEvent>) {
        Task { [weak self] in
            for await event in stream { self?.push(event) }
            self?.finish()
        }
    }

    func collected(_ count: Int) async -> [RealtimeEvent] {
        await withCheckedContinuation { arm(count: count, cont: $0) }
    }

    func finishedItems() async -> [RealtimeEvent] { await collected(.max) }

    private func arm(count: Int, cont: CheckedContinuation<[RealtimeEvent], Never>) {
        lock.lock()
        if items.count >= count || finished {
            let shot = items
            lock.unlock()
            cont.resume(returning: shot)
            return
        }
        waiter = (count, cont)
        lock.unlock()
    }

    private func push(_ event: RealtimeEvent) {
        lock.lock()
        items.append(event)
        resumeIfReady()
    }

    private func finish() {
        lock.lock()
        finished = true
        resumeIfReady()
    }

    private func resumeIfReady() {
        guard let waiter, items.count >= waiter.count || finished else {
            lock.unlock()
            return
        }
        let cont = waiter.cont
        self.waiter = nil
        let shot = items
        lock.unlock()
        cont.resume(returning: shot)
    }
}
