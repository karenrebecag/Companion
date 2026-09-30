import CompanionCore
import Foundation
import WebKit

/// Draws a Mermaid diagram in a WKWebView that can do nothing else (16m-5b).
///
/// Isolation, in layers: the page is built from `DiagramPage` with a CSP that
/// allows only its two inline scripts by hash; a content rule blocks every
/// URL with a scheme; navigation is denied after the first load; the store is
/// non-persistent; one fresh view per diagram, discarded after; the text is a
/// script ARGUMENT, never markup or code; Mermaid runs `securityLevel: strict`.
/// The script is the vendored file, checked against its pinned SHA-256 before
/// it is ever handed to the page. There is no network path to fail open.
///
/// Queueing, dedupe, caching, the deadline and cancellation are the
/// `DiagramScheduler`'s; this class is the page it drives.
@MainActor
package final class WebKitDiagramRenderer: DiagramRendering {
    /// Test seams: what the real page looked like, and the SVG it produced.
    var pageObserver: (@MainActor (WKWebView) -> Void)?
    var svgObserver: (@MainActor (String) -> Void)?

    private var scheduler: DiagramScheduler!
    private static var rules: WKContentRuleList?
    private static var script: String?

    package convenience init() {
        self.init(script: nil)
    }

    /// `script` replaces the vendored Mermaid (tests only: the real one is 3.6 MB
    /// and its hash is pinned); `pageHTML` builds the page around it.
    init(script: String?, pageHTML: @escaping (String) -> String = DiagramPage.html(vendorScript:),
         timeout: Duration = DiagramPage.renderTimeout) {
        scheduler = DiagramScheduler(timeout: timeout) { [unowned self] block, width in
            guard let script = script ?? Self.vendoredScript() else { return .failed(.unavailable) }
            return await Self.draw(block.source, width: width, html: pageHTML(script), owner: self)
        }
    }

    var timeout: Duration {
        get { scheduler.timeout }
        set { scheduler.timeout = newValue }
    }

    package func render(_ block: DiagramBlock, width: Double) async -> DiagramOutcome {
        await scheduler.render(block, width: width)
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isElementFullscreenEnabled = false
        config.preferences.isTextInteractionEnabled = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        return config
    }

    /// The vendored script, only if it is byte for byte the pinned one.
    static func vendoredScript() -> String? {
        if let script { return script }
        script = vendoredScript(from: ServicesResourceBundle.bundle)
        return script
    }

    /// Nil `bundle` (not found, 21c) is nil here and `.unavailable` upstream.
    static func vendoredScript(from bundle: Bundle?) -> String? {
        guard let url = bundle?.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Diagram") else {
            Log.app("diagram: mermaid.min.js is not in the bundle")
            return nil
        }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            Log.app("diagram: mermaid.min.js unreadable: \(error.localizedDescription)")
            return nil
        }
        return verified(data)
    }

    static func verified(_ data: Data) -> String? {
        guard DiagramPage.sha256Hex(data) == DiagramPage.mermaidSHA256 else {
            Log.app("diagram: mermaid.min.js does not match its pinned SHA-256; refusing to load it")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func draw(_ source: String, width: Double, html: String, owner: WebKitDiagramRenderer) async -> DiagramOutcome {
        guard let rules = await contentRules() else { return .failed(.unavailable) }
        let config = makeConfiguration()
        config.userContentController.add(rules)
        let page = DiagramWebPage(config: config, width: width)
        if let view = page.webView { owner.pageObserver?(view) }
        // A caller that leaves (or a deadline that passes) tears the page down
        // even when its script never answers.
        let outcome = await withTaskCancellationHandler {
            await page.draw(source: source, html: html, onSVG: owner.svgObserver)
        } onCancel: {
            Task { @MainActor in page.tearDown() }
        }
        page.tearDown()
        return outcome
    }

    /// Fail closed: without the rule list only the CSP would hold, and the
    /// design is two independent layers.
    private static func contentRules() async -> WKContentRuleList? {
        if let rules { return rules }
        do {
            rules = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "companion.diagram.no-network", encodedContentRuleList: DiagramPage.blockNetworkRules)
        } catch {
            Log.app("diagram: content rules did not compile: \(error.localizedDescription)")
        }
        return rules
    }
}

/// One page, one diagram. Released after the draw, the deadline or a cancel.
/// It reaches its view only through `webView`, never through a local that
/// would keep a hung page alive after `tearDown`.
@MainActor
final class DiagramWebPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    private(set) var webView: WKWebView?
    /// The web content process died: a platform failure, not a refusal.
    private(set) var terminated = false
    private var loaded: CheckedContinuation<Bool, Never>?
    private let width: Double

    init(config: WKWebViewConfiguration, width: Double) {
        self.width = width
        super.init()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 1), configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.underPageBackgroundColor = .clear
        webView = view
    }

    func tearDown() {
        loaded?.resume(returning: false)
        loaded = nil
        // Leaving the page fails a script still awaiting an answer.
        webView?.loadHTMLString("", baseURL: nil)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
    }

    private var lost: DiagramFailure { terminated ? .unavailable : .invalid }

    func draw(source: String, html: String, onSVG: (@MainActor (String) -> Void)?) async -> DiagramOutcome {
        let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            guard let view = webView else { return continuation.resume(returning: false) }
            loaded = continuation
            view.loadHTMLString(html, baseURL: nil)
        }
        guard ready, !terminated else { return .failed(.unavailable) }
        let result: Any?
        do {
            result = try await webView?.callAsyncJavaScript(
                DiagramPage.renderCall, arguments: ["source": source], in: nil, contentWorld: .page)
        } catch {
            // Mermaid's own message can quote the model's text; it stays out of the log.
            Log.app("diagram: the page did not draw (process lost: \(terminated))")
            return .failed(lost)
        }
        guard webView != nil else { return .failed(.unavailable) }
        guard let box = result as? [String: Any], let height = (box["height"] as? NSNumber)?.doubleValue else {
            return .failed(lost)
        }
        guard DiagramPage.acceptsHeight(height) else {
            Log.app("diagram: the drawing is \(height) tall, past the cap; refusing it")
            return .failed(.invalid)
        }
        if let onSVG {
            do {
                if let markup = try await webView?.evaluateJavaScript("document.getElementById('out').innerHTML") as? String {
                    onSVG(markup)
                }
            } catch {
                Log.app("diagram: the drawing could not be read back: \(error.localizedDescription)")
            }
        }
        webView?.setFrameSize(NSSize(width: width, height: height))
        let pdf = WKPDFConfiguration()
        pdf.rect = CGRect(x: 0, y: 0, width: width, height: height)
        let data: Data
        do {
            guard let drawn = try await webView?.pdf(configuration: pdf) else { return .failed(.unavailable) }
            data = drawn
        } catch {
            Log.app("diagram: the page could not be drawn to an image: \(error.localizedDescription)")
            return .failed(.unavailable)
        }
        let png = await export(height: height, transparent: false)
        let clear = await export(height: height, transparent: true)
        return .image(DiagramImage(data: data, width: width, height: height,
                                   png: png ?? Data(), pngTransparent: clear ?? Data()))
    }

    /// An export that fails costs its own tool, not the drawing.
    private func export(height: Double, transparent: Bool) async -> Data? {
        guard let view = webView else { return nil }
        do {
            return transparent
                ? try await DiagramPNG.transparent(of: view, width: width, height: height)
                : try await DiagramPNG.withBackground(of: view, width: width, height: height)
        } catch {
            Log.app("diagram: the PNG export failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func finishLoad(_ ok: Bool) {
        loaded?.resume(returning: ok)
        loaded = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(DiagramPage.allowsNavigation(to: navigationAction.request.url) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad(true) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.app("diagram: navigation failed: \(error.localizedDescription)")
        finishLoad(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.app("diagram: the page did not load: \(error.localizedDescription)")
        finishLoad(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.app("diagram: the web content process terminated")
        terminated = true
        finishLoad(false)
        tearDown()
    }

    /// A window the model's diagram asks for is never opened.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}
