import CompanionCore
import Foundation
@testable import CompanionServices
import Network
import Testing
import WebKit

// Shared by the 16m-5b suites: a loopback listener that counts connections
// (the proof that a request did or did not leave a web view), the script a
// hostile page would run, and a stand-in for the script the renderer loads.

final class Beacon: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.lock.withLock { self?.connections += 1 }
            connection.cancel()
        }
    }

    var hits: Int { lock.withLock { connections } }

    func start() async -> UInt16? {
        await withCheckedContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                if case .ready = state { continuation.resume(returning: listener.port?.rawValue) }
                if case .failed = state { continuation.resume(returning: nil) }
            }
            listener.start(queue: .global())
        }
    }

    func stop() { listener.cancel() }

    /// Seconds until the first connection, or nil if none came before the deadline. A loaded
    /// machine (the CI runner) takes longer than any fixed sleep to reach even an open page.
    func firstHit(within seconds: Double) async -> Double? {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            if hits > 0 { return Date().timeIntervalSince(start) }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return nil }
        }
        return nil
    }
}

/// How long a blocked page gets to prove it stays silent: at least a second, and three times
/// what the open control needed, so a slow machine cannot turn "no hits yet" into a pass.
// HACK: capped at 12 s so the layers test fits its 60 s watchdog; past a 4 s control the
// window drops under 3x. Raise the watchdog with the cap if the CI control ever takes > 4 s.
func silenceWindow(controlTook seconds: Double) -> Duration {
    .milliseconds(Int(min(12.0, max(1.0, seconds * 3)) * 1000))
}

/// Whether the leak script ran in this view. Reading it also keeps the view alive through the
/// silence window, so an early release cannot stop the load and fake a silent port.
@MainActor
func leakScriptRan(in view: WKWebView) async -> Bool {
    do {
        return try await view.evaluateJavaScript("window.__leakRan === true") as? Bool ?? false
    } catch {
        return false
    }
}

/// Every way a page can reach a port, as one script. It marks `window.__leakRan` first, so a
/// silent port can be told apart from a page whose script never ran.
func leakScript(port: UInt16) -> String {
    let url = "http://127.0.0.1:\(port)/leak"
    return """
    window.__leakRan = true;
    try { fetch("\(url)/fetch").catch(() => {}); } catch (e) {}
    try { const x = new XMLHttpRequest(); x.open("GET", "\(url)/xhr"); x.send(); } catch (e) {}
    try { new Image().src = "\(url)/img"; } catch (e) {}
    try { const i = document.createElement("img"); i.src = "\(url)/dom"; document.body.appendChild(i); } catch (e) {}
    try { const s = document.createElement("script"); s.src = "\(url)/script.js"; document.head.appendChild(s); } catch (e) {}
    try { const l = document.createElement("link"); l.rel = "stylesheet"; l.href = "\(url)/css"; document.head.appendChild(l); } catch (e) {}
    try { navigator.sendBeacon("\(url)/beacon", "x"); } catch (e) {}
    try { new WebSocket("ws://127.0.0.1:\(port)/ws"); } catch (e) {}
    try { const f = document.createElement("iframe"); f.src = "\(url)/frame"; document.body.appendChild(f); } catch (e) {}
    """
}

/// What the renderer loads in place of Mermaid: same entry point
/// (`window.renderDiagram`), no 3.6 MB parse, and a behavior per source.
func fakeMermaid(height: Double = 40, leaking port: UInt16? = nil) -> String {
    """
    \(port.map(leakScript(port:)) ?? "")
    window.renderDiagram = async function (source) {
      if (source.includes("hang")) { return await new Promise(() => {}); }
      document.getElementById("out").innerHTML = "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'></svg>";
      return { height: \(height) };
    };
    """
}

/// A page with no CSP and none of the bootstrap: only the content rules
/// stand between it and the network.
func pageWithoutCSP(_ script: String) -> String {
    "<!DOCTYPE html><html><body><div id=\"out\"></div><script>\(script)</script></body></html>"
}

final class FakeNavigationAction: WKNavigationAction, @unchecked Sendable {
    private let target: URL
    init(_ url: URL) {
        target = url
        super.init()
    }
    override var request: URLRequest { URLRequest(url: target) }
}

/// Runs a test body against a deadline of its own. A regression that makes
/// the code under test wait forever must end as a red test with a name in
/// seconds, not as a hung `swift test` (`.timeLimit` does not abort it).
@MainActor
func watched(_ seconds: Double = 60, _ name: String, _ body: @escaping @MainActor () async -> Void) async {
    final class Gate { var done = false; var continuation: CheckedContinuation<Void, Never>?; var timer: Task<Void, Never>? }
    let gate = Gate()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        gate.continuation = continuation
        Task { @MainActor in
            await body()
            guard !gate.done else { return }
            gate.done = true
            gate.timer?.cancel()
            gate.continuation?.resume()
        }
        WatchdogStats.live[name, default: 0] += 1
        gate.timer = Task { @MainActor in
            defer { WatchdogStats.live[name, default: 0] -= 1 }
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard !gate.done else { return }
            gate.done = true
            Issue.record("\(name): no terminó en \(seconds) s (espera sin fin)")
            gate.continuation?.resume()
        }
    }
}

/// A renderer over the stand-in script with a deadline the busy full suite
/// cannot trip: the 10 s deadline is pinned by the timeout tests alone.
@MainActor
func testRenderer(script: String, pageHTML: @escaping (String) -> String = DiagramPage.html(vendorScript:)) -> WebKitDiagramRenderer {
    let renderer = WebKitDiagramRenderer(script: script, pageHTML: pageHTML)
    renderer.timeout = .seconds(60)
    return renderer
}

/// How many watchdog timers are alive per test name; a finished body must leave none.
@MainActor
enum WatchdogStats { static var live: [String: Int] = [:] }

/// One real web view test at a time. Each web view launches a content process
/// and its setup runs on the main actor; a dozen at once starve the timing
/// tests of the rest of the suite (JobQueueTests measures 40 ms on the main
/// actor). Serial, the bursts are short and apart.
@MainActor
enum WebKitSlot {
    private static var busy = false
    private static var waiting: [CheckedContinuation<Void, Never>] = []

    static func acquire() async {
        if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
    }

    static func release() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}

/// `watched`, holding the web view slot for the body.
@MainActor
func watchedWeb(_ seconds: Double = 60, _ name: String, _ body: @escaping @MainActor () async -> Void) async {
    await WebKitSlot.acquire()
    await watched(seconds, name, body)
    WebKitSlot.release()
}
