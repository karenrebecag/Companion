import AppKit
import CompanionCore
import Foundation
import PDFKit
import WebKit

/// HTML to a paginated A4 PDF (spec 20 D3). The page is ours: JavaScript off,
/// every network load blocked, no base URL, a throwaway data store. WebKit
/// prints only from a view that has a window, so an off-screen one holds it.
@MainActor
final class PDFRenderer: NSObject, WKNavigationDelegate {
    static let a4 = NSSize(width: 595.28, height: 841.89)
    static let margin: CGFloat = 46
    /// Loading plus printing a long report; past this something is stuck.
    static let timeout: Duration = .seconds(30)

    private var loaded: CheckedContinuation<Void, Error>?
    private var printed: CheckedContinuation<Bool, Never>?

    /// Every scheme a page could reach out with. The template has no
    /// reference at all; this is the belt to that brace.
    /// WebKit's rule regexes have no alternation: one rule per scheme.
    static let blockedSchemes = ["https?", "wss?", "ftp", "file", "blob", "data"]
    static var blockEverything: String {
        "[" + blockedSchemes.map {
            #"{"trigger":{"url-filter":"^\#($0):"},"action":{"type":"block"}}"#
        }.joined(separator: ",") + "]"
    }

    /// No script and nothing kept between renders; the rule list is added on top.
    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        return config
    }

    func render(html: String, to url: URL) async throws -> Int {
        let config = Self.configuration()
        let rules = try await Self.offlineRules()
        config.userContentController.add(rules.list)

        let frame = NSRect(origin: .zero, size: Self.a4)
        let webView = WKWebView(frame: frame, configuration: config)
        webView.navigationDelegate = self
        let window = NSWindow(contentRect: frame.offsetBy(dx: -20_000, dy: -20_000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        defer {
            webView.navigationDelegate = nil
            window.contentView = nil
            window.close()
        }

        let clock = watchdog()
        defer { clock.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        let ok = await printPDF(webView, window: window, to: url)
        guard ok, let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw DocumentError.renderFailed
        }
        return document.pageCount
    }

    private func printPDF(_ webView: WKWebView, window: NSWindow, to url: URL) async -> Bool {
        let info = NSPrintInfo()
        info.paperSize = Self.a4
        info.topMargin = Self.margin
        info.bottomMargin = Self.margin
        info.leftMargin = Self.margin
        info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds
        return await withCheckedContinuation { continuation in
            printed = continuation
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    /// AppKit finishes a modal print on its own thread.
    @objc nonisolated private func printDidRun(_ operation: NSPrintOperation, success: Bool,
                                               contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in self.finishPrint(success) }
    }

    private func finishPrint(_ success: Bool) {
        printed?.resume(returning: success)
        printed = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: DocumentError.renderFailed)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        loaded?.resume(throwing: DocumentError.renderFailed)
        loaded = nil
    }

    /// WebKit answers the compile on its own queue; the list is handed back
    /// to the main actor in a box, never touched in between.
    private struct RuleBox: @unchecked Sendable { let list: WKContentRuleList }

    private static func offlineRules() async throws -> RuleBox {
        let source = blockEverything
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "companion-document-offline", encodedContentRuleList: source
            ) { @Sendable list, error in
                if let list {
                    continuation.resume(returning: RuleBox(list: list))
                } else {
                    continuation.resume(throwing: error ?? DocumentError.renderFailed)
                }
            }
        }
    }

    /// Whatever is still pending when the clock runs out is answered once:
    /// a load that never finishes throws, a print that never returns fails.
    private func watchdog() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.timeout) } catch { return }
            guard let self else { return }
            self.loaded?.resume(throwing: DocumentError.timedOut)
            self.loaded = nil
            self.printed?.resume(returning: false)
            self.printed = nil
        }
    }
}

/// The document port: PDF through WebKit, XLSX through `XLSXWriter`.
public struct NativeDocumentRenderer: DocumentRendering {
    public init() {}

    public func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        switch format {
        case .pdf:
            let html = DocumentHTML.render(spec)
            let pages = try await MainActor.run { PDFRenderer() }.render(html: html, to: url)
            return DocumentReceipt(pages: pages, bytes: Self.bytes(url))
        case .xlsx:
            guard let data = XLSXWriter.package(spec) else { throw DocumentError.unsupportedFormat }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw DocumentError.renderFailed
            }
            return DocumentReceipt(pages: nil, bytes: data.count)
        }
    }

    static func bytes(_ url: URL) -> Int {
        do {
            return (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        } catch {
            return 0
        }
    }
}
