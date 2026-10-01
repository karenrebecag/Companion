import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

package struct ScriptedReply {
    package var status: Int
    package var lines: [String]
    package var body: Data
    package var error: Error?
    package var hangNanoseconds: UInt64
    package var lineHangNanoseconds: UInt64
    package var streamError: Error?

    package init(
        status: Int = 200,
        lines: [String] = [],
        body: Data = Data(),
        error: Error? = nil,
        hangNanoseconds: UInt64 = 0,
        lineHangNanoseconds: UInt64 = 0,
        streamError: Error? = nil
    ) {
        self.status = status
        self.lines = lines
        self.body = body
        self.error = error
        self.hangNanoseconds = hangNanoseconds
        self.lineHangNanoseconds = lineHangNanoseconds
        self.streamError = streamError
    }
}

/// Maps URL (exact, then contains) or call order to a canned HTTP/SSE reply.
package final class ScriptedTransport: ChatTransport, @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var byURL: [String: ScriptedReply] = [:]
    private var queue: [ScriptedReply] = []
    private var _requests: [URLRequest] = []

    package var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    package func stub(url: String, _ reply: ScriptedReply) {
        lock.lock()
        byURL[url] = reply
        lock.unlock()
    }

    package func stub(_ provider: ProviderDescriptor, _ reply: ScriptedReply) {
        stub(url: provider.endpoint?.absoluteString ?? "", reply)
    }

    package func stubModels(_ provider: ProviderDescriptor, status: Int, error: Error? = nil) {
        stub(
            url: provider.baseURL.absoluteString + "/models",
            ScriptedReply(status: status, error: error))
    }

    package func enqueue(_ reply: ScriptedReply) {
        lock.lock()
        queue.append(reply)
        lock.unlock()
    }

    package func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        remember(request)
        let reply = try resolve(request)
        try await hang(reply.hangNanoseconds)
        if let error = reply.error { throw error }
        return (reply.body, http(request, status: reply.status))
    }

    package func lines(for request: URLRequest) async throws -> (
        status: Int, lines: AsyncThrowingStream<String, Error>
    ) {
        remember(request)
        let reply = try resolve(request)
        try await hang(reply.hangNanoseconds)
        try Task.checkCancellation()
        if let error = reply.error { throw error }
        // Yield canned lines in the builder so returning the stream cannot
        // cancel a producer Task before the first line is buffered.
        let canned = reply.lines
        let lineHang = reply.lineHangNanoseconds
        let streamError = reply.streamError
        let stream = AsyncThrowingStream<String, Error> { continuation in
            if lineHang == 0 {
                for line in canned { continuation.yield(line) }
                if let streamError {
                    continuation.finish(throwing: streamError)
                } else {
                    continuation.finish()
                }
                return
            }
            let reader = Task {
                do {
                    for line in canned {
                        try await hang(lineHang)
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    if let streamError {
                        continuation.finish(throwing: streamError)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
        return (status: reply.status, lines: stream)
    }

    private func remember(_ request: URLRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    private func resolve(_ request: URLRequest) throws -> ScriptedReply {
        let url = request.url?.absoluteString ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let exact = byURL[url] { return exact }
        for (needle, reply) in byURL where !needle.isEmpty && url.contains(needle) {
            return reply
        }
        if !queue.isEmpty { return queue.removeFirst() }
        throw URLError(.badURL)
    }

    private func http(_ request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

private func hang(_ nanoseconds: UInt64) async throws {
    guard nanoseconds > 0 else { return }
    try await Task.sleep(nanoseconds: nanoseconds)
}
