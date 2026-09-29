import Foundation

/// What the isolated page hands back: a picture, never markup. PDF keeps the
/// text crisp at any scale; the UI only needs bytes an image can read. The
/// two PNGs are the exports (Incredible's copy and download, 2x, with the
/// popup's background or without it); empty means the page could not make one.
public struct DiagramImage: Sendable, Equatable {
    public let data: Data
    public let width: Double
    public let height: Double
    public let png: Data
    public let pngTransparent: Data

    public init(data: Data, width: Double, height: Double, png: Data = Data(), pngTransparent: Data = Data()) {
        self.data = data
        self.width = width
        self.height = height
        self.png = png
        self.pngTransparent = pngTransparent
    }
}

public enum DiagramFailure: Sendable, Equatable {
    /// Mermaid refused the text (syntax, an unknown diagram type).
    case invalid
    case timeout
    /// No renderer, or the page could not be built or trusted.
    case unavailable
}

/// How a PNG save ended: cancelling the panel is her choice, a failed write
/// is something to tell her.
public enum DiagramSaveResult: Sendable, Equatable {
    case saved, cancelled, failed
}

public enum DiagramOutcome: Sendable, Equatable {
    case image(DiagramImage)
    case failed(DiagramFailure)
}

/// The UI's only door to the web view. WebKit lives behind it in Services;
/// the UI never imports it (gates.sh) and Core stays pure.
@MainActor
public protocol DiagramRendering: AnyObject {
    /// Never throws: every failure is an outcome the popup shows as code.
    func render(_ block: DiagramBlock, width: Double) async -> DiagramOutcome
}

/// A bounded wait on work that cannot be cancelled: a page stuck in a
/// script loop ignores `Task.cancel`, so the caller stops waiting instead.
/// The caller's own cancellation ends the wait the same way.
@MainActor
public enum DiagramTimeout {
    @MainActor private final class Race {
        var fired = false
        var continuation: CheckedContinuation<Void, Never>?
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?
        var value: (any Sendable)?

        /// The first to arrive wins; a late result is dropped, never delivered.
        func finish(_ result: (any Sendable)?) {
            guard !fired else { return }
            fired = true
            value = result
            timer?.cancel()
            if result == nil { work?.cancel() }
            continuation?.resume()
            continuation = nil
        }
    }

    /// Nil when `limit` passed first, or the caller was cancelled.
    public static func run<T: Sendable>(
        after limit: Duration, _ operation: @escaping @MainActor () async -> T
    ) async -> T? {
        let race = Race()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                race.continuation = continuation
                race.work = Task { @MainActor in
                    let value = await operation()
                    race.finish(value)
                }
                race.timer = Task { @MainActor in
                    do { try await Task.sleep(for: limit) } catch { return }
                    race.finish(nil)
                }
            }
        } onCancel: {
            Task { @MainActor in race.finish(nil) }
        }
        return race.value as? T
    }
}
