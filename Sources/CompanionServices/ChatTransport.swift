import Foundation

public protocol ChatTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func lines(for request: URLRequest) async throws -> (
        status: Int, lines: AsyncThrowingStream<String, Error>
    )
}

public struct URLSessionChatTransport: ChatTransport, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        // If no delegate is configured, wrap with redirect validation.
        if session.delegate == nil || !(session.delegate is RedirectValidatingDelegate) {
            let delegate = RedirectValidatingDelegate()
            let config = URLSessionConfiguration.default
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        } else {
            self.session = session
        }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    public func lines(for request: URLRequest) async throws -> (
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
