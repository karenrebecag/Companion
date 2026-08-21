import CompanionCore
import Foundation

public protocol RealtimeSocketing: Sendable {
    func send(text: String) async throws
    func receive() async throws -> String
    func close() async
}

public protocol RealtimeConnecting: Sendable {
    func connect(url: URL, bearer: String) async throws -> any RealtimeSocketing
}

public actor RealtimeWSTransport: VoiceTransport {
    private let connector: any RealtimeConnecting
    nonisolated private let pipe = EventPipe()
    private var socket: (any RealtimeSocketing)?
    private var pump: Task<Void, Never>?
    private var closingExplicitly = false

    public init(connector: any RealtimeConnecting = URLSessionRealtimeConnector()) {
        self.connector = connector
    }

    nonisolated public func events() -> AsyncStream<RealtimeEvent> {
        pipe.stream
    }

    /// Handshake only — VoiceSession owns the 6s timeout, not this type.
    public func open(key: String, url: URL) async throws {
        // Validate URL scheme: only wss (always) and ws (localhost only)
        guard let scheme = url.scheme?.lowercased(), ["wss", "ws"].contains(scheme) else {
            throw VoiceTransportError.unreachable
        }
        if scheme == "ws" {
            guard let host = url.host?.lowercased(),
                  host == "localhost" || host == "127.0.0.1" || host == "::1" else {
                throw VoiceTransportError.unreachable
            }
        }

        closingExplicitly = false
        await teardown(finishStream: false)
        if pipe.isFinished { pipe.reset() }
        let connected: any RealtimeSocketing
        do {
            connected = try await connector.connect(
                url: url, bearer: "Bearer \(key)")
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VoiceTransportError {
            throw error
        } catch {
            throw VoiceTransportError.unreachable
        }
        do {
            try Task.checkCancellation()
        } catch {
            await connected.close()
            throw CancellationError()
        }
        socket = connected
        let pipe = self.pipe
        pump = Task { await self.runPump(on: connected, pipe: pipe) }
    }

    public func send(_ json: String) async throws {
        guard let socket else { throw VoiceTransportError.closed }
        do {
            try await socket.send(text: json)
        } catch let error as VoiceTransportError {
            throw error
        } catch {
            throw VoiceTransportError.closed
        }
    }

    public func close() async {
        await teardown(finishStream: true)
    }

    private func runPump(on socket: any RealtimeSocketing, pipe: EventPipe) async {
        while !Task.isCancelled {
            let text: String
            do {
                text = try await socket.receive()
            } catch is CancellationError {
                return
            } catch {
                await receiveFailed()
                return
            }
            pipe.yield(RealtimeCodec.parse(text))
        }
    }

    private func receiveFailed() async {
        pump = nil
        let old = socket
        socket = nil
        // FIX 1: Emit server error event before finishing stream so session can detect failure.
        // But only if this was an unexpected failure, not an explicit close().
        if !closingExplicitly {
            pipe.yield(.serverError("connection lost"))
        }
        pipe.finish()
        await old?.close()
    }

    private func teardown(finishStream: Bool) async {
        closingExplicitly = true
        pump?.cancel()
        let oldPump = pump
        pump = nil
        let old = socket
        socket = nil
        await old?.close()
        _ = await oldPump?.value
        if finishStream { pipe.finish() }
    }
}

public struct URLSessionRealtimeConnector: RealtimeConnecting, Sendable {
    public init() {}

    public static func mapFailure(httpStatus: Int?, error: Error) -> VoiceTransportError {
        if httpStatus == 401 { return .unauthorized }
        if let mapped = error as? VoiceTransportError { return mapped }
        return .unreachable
    }

    public func connect(url: URL, bearer: String) async throws -> any RealtimeSocketing {
        var request = URLRequest(url: url)
        request.setValue(bearer, forHTTPHeaderField: "Authorization")
        let handshake = WebSocketHandshake()
        let session = URLSession(
            configuration: .default, delegate: handshake, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        let socket = URLSessionRealtimeSocket(task: task, session: session)
        task.resume()
        do {
            try await handshake.waitUntilOpen()
        } catch is CancellationError {
            await socket.close()
            throw CancellationError()
        } catch let error as VoiceTransportError {
            await socket.close()
            throw error
        } catch {
            await socket.close()
            throw Self.mapFailure(
                httpStatus: (task.response as? HTTPURLResponse)?.statusCode,
                error: error)
        }
        return socket
    }
}

private final class URLSessionRealtimeSocket: RealtimeSocketing, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let session: URLSession

    init(task: URLSessionWebSocketTask, session: URLSession) {
        self.task = task
        self.session = session
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            if let http = task.response as? HTTPURLResponse, http.statusCode == 401 {
                throw VoiceTransportError.unauthorized
            }
            throw error
        }
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw VoiceTransportError.closed
            }
            return text
        @unknown default:
            throw VoiceTransportError.closed
        }
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
        session.finishTasksAndInvalidate()
    }
}

private final class WebSocketHandshake: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled: Result<Void, Error>?

    func waitUntilOpen() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.arm(cont)
            }
        } onCancel: {
            self.settle(.failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocolString: String?
    ) {
        settle(.success(()))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        if status == 401 {
            settle(.failure(VoiceTransportError.unauthorized))
            return
        }
        if let error {
            settle(.failure(error))
        }
    }

    private func arm(_ cont: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let settled {
            lock.unlock()
            cont.resume(with: settled)
            return
        }
        continuation = cont
        lock.unlock()
    }

    func settle(_ result: Result<Void, Error>) {
        lock.lock()
        if settled != nil {
            lock.unlock()
            return
        }
        settled = result
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }
}

private final class EventPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var _stream: AsyncStream<RealtimeEvent>
    private var continuation: AsyncStream<RealtimeEvent>.Continuation
    private var finished = false

    init() {
        let pair = AsyncStream.makeStream(of: RealtimeEvent.self)
        _stream = pair.stream
        continuation = pair.continuation
    }

    var stream: AsyncStream<RealtimeEvent> {
        lock.lock(); defer { lock.unlock() }
        return _stream
    }

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    func yield(_ event: RealtimeEvent) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont.yield(event)
    }

    func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let cont = continuation
        lock.unlock()
        cont.finish()
    }

    func reset() {
        lock.lock()
        if !finished { continuation.finish() }
        let pair = AsyncStream.makeStream(of: RealtimeEvent.self)
        _stream = pair.stream
        continuation = pair.continuation
        finished = false
        lock.unlock()
    }
}
