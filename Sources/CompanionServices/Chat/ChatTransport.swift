import Foundation

package protocol ChatTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func lines(for request: URLRequest) async throws -> (
        status: Int, lines: AsyncThrowingStream<String, Error>
    )
    /// Wave 15c-5: the response body as it arrives, in raw byte chunks —
    /// `lines` decodes UTF8 text and splits on newlines, which corrupts
    /// binary PCM.
    func bytes(for request: URLRequest) async throws -> (
        status: Int, bytes: AsyncThrowingStream<Data, Error>
    )
}

extension ChatTransport {
    /// Default: the whole body as a single chunk. Correct for every fake
    /// transport in the test suite; only `URLSessionChatTransport` needs the
    /// real per-packet granularity, so it is the only conformer that
    /// overrides this.
    package func bytes(for request: URLRequest) async throws -> (
        status: Int, bytes: AsyncThrowingStream<Data, Error>
    ) {
        let (data, response) = try await self.data(for: request)
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(data)
            continuation.finish()
        }
        return (status: response.statusCode, bytes: stream)
    }
}

package struct URLSessionChatTransport: ChatTransport, Sendable {
    let session: URLSession

    /// Security review 2026-09-25 (CRITICAL-1): the session is always built
    /// here from `NoStoreSession.configuration()`; a caller-supplied session
    /// (e.g. `.shared`) would bring the default disk cache back, so the
    /// parameter only exists for source compatibility and is ignored.
    package init(session: URLSession = .shared) {
        self.init(protocolClasses: nil)
    }

    /// Test seam: stubs are prepended so the no-store settings are exercised
    /// exactly as in production.
    init(protocolClasses: [AnyClass]?) {
        let config = NoStoreSession.configuration()
        if let protocolClasses {
            config.protocolClasses = protocolClasses + (config.protocolClasses ?? [])
        }
        self.session = URLSession(
            configuration: config, delegate: RedirectValidatingDelegate(), delegateQueue: nil)
    }

    package func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    package func lines(for request: URLRequest) async throws -> (
        status: Int, lines: AsyncThrowingStream<String, Error>
    ) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let reader = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
        return (status: http.statusCode, lines: stream)
    }

    /// Wave 15c-5: same shape as `lines(for:)` above — forward the session's
    /// own byte-by-byte stream into an `AsyncThrowingStream`, batched into
    /// fixed-size chunks so the mouth can start scheduling audio before the
    /// whole sentence has downloaded.
    // HACK: a fixed 4 KB batch, not real packet boundaries — good enough to
    // start playback well under the wave's latency budget (wave-15c-tubo-
    // rapido.md §3). Move to a URLSessionDataDelegate reporting each
    // `didReceive data:` if 4 KB ever proves coarser than perceived.
    package func bytes(for request: URLRequest) async throws -> (
        status: Int, bytes: AsyncThrowingStream<Data, Error>
    ) {
        let (byteStream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let chunkSize = 4096
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let reader = Task {
                do {
                    var buffer = Data()
                    buffer.reserveCapacity(chunkSize)
                    for try await byte in byteStream {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
        return (status: http.statusCode, bytes: stream)
    }
}

// Delegate that validates redirects using RedirectPolicy.
private class RedirectValidatingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let fromURL = task.originalRequest?.url,
              let toURL = request.url else {
            completionHandler(nil)
            return
        }

        // Only allow redirects that pass policy validation.
        if RedirectPolicy.allows(from: fromURL, to: toURL) {
            completionHandler(request)
        } else {
            // Reject the redirect by returning nil.
            completionHandler(nil)
        }
    }
}

/// Security review 2026-09-25 (CRITICAL-1): every request this app makes
/// carries a key header and often the user's screen/clipboard context, and
/// the default configuration persisted both to ~/Library/Caches/<bundle>/
/// Cache.db. Every URLSession in Sources is built from this configuration;
/// scripts/gates.sh fails on any other.
package enum NoStoreSession {
    package static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return config
    }

    /// For the paths that need no per-session delegate (the transcriber
    /// websocket, `web_fetch`).
    package static let shared = URLSession(configuration: configuration())
}
