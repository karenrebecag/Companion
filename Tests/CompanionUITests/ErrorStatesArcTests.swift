import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing
import Vision

// Arc's free alert, skeleton, and toast. Faces, motion, copy, and what
// actually gets drawn: a skeleton, a failure with the mermaid source and
// no retry, then a picture.

@Suite @MainActor struct ErrorStatesArc {
    @Test func errorStatesMapsDiagramFaces() {
        let image = DiagramImage(data: Data(), width: 10, height: 10)
        #expect(IslandDiagramChrome.face(.loading, decoded: false) == .loading)
        #expect(IslandDiagramChrome.face(.image(image), decoded: true) == .success)
        #expect(IslandDiagramChrome.face(.image(image), decoded: false) == .failure(.unavailable))
        #expect(IslandDiagramChrome.face(.failed(.invalid), decoded: true) == .failure(.invalid))
        #expect(IslandDiagramChrome.face(.failed(.timeout), decoded: false) == .failure(.timeout))
        #expect(IslandDiagramChrome.face(.failed(.unavailable), decoded: false) == .failure(.unavailable))
        expectSame(ToastChrome.fill(.error), Semantic.destructive, "error toast fill")
        expectSame(ToastChrome.ink(.error), Semantic.destructiveForeground, "error toast ink")
        expectSame(ToastChrome.fill(.info), Semantic.accent, "info toast fill")
        expectSame(ToastChrome.ink(.info), Semantic.accentForeground, "info toast ink")
    }

    @Test func errorStatesReduceMotionKeepsTheFade() {
        let moving = ToastMotion.animation(reduceMotion: false)
        let reduced = ToastMotion.animation(reduceMotion: true)
        #expect(moving == .expoOut(MotionTime.fast))
        // A nil animation would make the opacity change land at once.
        #expect(reduced != nil, "reduced motion still fades")
        #expect(reduced == MotionCurve.animation(MotionCurve.linear, MotionTime.fast))
        #expect(reduced != moving)
    }

    @Test func errorStatesSizesLiveInTheMetrics() {
        #expect(IslandVisualMetrics.diagramSkeletonHeight == 120)
        #expect(IslandVisualMetrics.diagramAlertIcon == 16)
    }

    @Test func errorStatesAnnouncementIsPinned() throws {
        let failed = Notice(text: "disk full", level: .error, bornAt: 0)
        let saved = Notice(text: "saved", level: .info, bornAt: 0)
        #expect(ToastChrome.announcement(failed, language: .en) == "Error: disk full")
        #expect(ToastChrome.announcement(failed, language: .es) == "Error: disk full")
        #expect(ToastChrome.announcement(saved, language: .en) == nil)
        #expect(ToastChrome.announcement(saved, language: .es) == nil)
        #expect(IslandDiagramChrome.announcement(.timeout, language: .en)
            == "Drawing this diagram took too long. Here is its text.")
        #expect(IslandDiagramChrome.announcement(.timeout, language: .es)
            == "Dibujar este diagrama tardó demasiado. Aquí está su texto.")
    }

    @Test func errorStatesAnnouncementIsOneBoundedBidiFreeLine() throws {
        let hostile = "first line\nsecond\u{202E}line\u{2028}third\t" + String(repeating: "x", count: 1000)
        let line = try #require(ToastChrome.announcement(
            Notice(text: hostile, level: .error, bornAt: 0), language: .en))
        #expect(line.hasPrefix("Error: first line second"))
        #expect(!line.unicodeScalars.contains { scalar in
            [.control, .format, .lineSeparator, .paragraphSeparator]
                .contains(scalar.properties.generalCategory)
        }, "control, format or bidi scalar survived: \(line.debugDescription)")
        #expect(!line.contains("\u{202E}"))
        #expect(line.count <= 200, "announcement is not bounded: \(line.count)")
        #expect(line.contains("x"), "the cap cut the copy to nothing")
    }

    @Test func errorStatesReadsTheLabels() throws {
        let es = try uiCatalog("es")
        let en = try uiCatalog("en")
        #expect(!(try #require(es["notices.error.prefix"])).isEmpty)
        #expect(!(try #require(en["notices.error.prefix"])).isEmpty)
        for language in ["en", "es"] {
            let catalog = try uiCatalog(language)
            #expect(catalog["island.diagram.alert.failed"] == nil)
            #expect(catalog["island.diagram.alert.timeout"] == nil)
            #expect(catalog["island.diagram.alert.detail"] == nil)
        }

        #expect(IslandDiagramChrome.loadingLabel(.en) == "Drawing the diagram")
        #expect(IslandDiagramChrome.loadingLabel(.es) == "Dibujando el diagrama")
        #expect(!IslandDiagramChrome.announces(.loading))
        #expect(!IslandDiagramChrome.announces(.success))

        #expect(IslandDiagramChrome.title(.invalid, .en) == "I could not draw this diagram")
        #expect(IslandDiagramChrome.title(.timeout, .en) == "Drawing this diagram took too long")
        #expect(IslandDiagramChrome.detail(.invalid, .en) == "Here is its text.")
        #expect(IslandDiagramChrome.detail(.timeout, .en) == "Here is its text.")
        #expect(IslandDiagramChrome.title(.invalid, .es) == "No pude dibujar este diagrama")
        #expect(IslandDiagramChrome.title(.timeout, .es) == "Dibujar este diagrama tardó demasiado")
        #expect(IslandDiagramChrome.detail(.invalid, .es) == "Aquí está su texto.")
        #expect(IslandDiagramChrome.detail(.timeout, .es) == "Aquí está su texto.")
        #expect(!IslandDiagramChrome.title(.invalid, .en).contains("\n"))
        #expect(!IslandDiagramChrome.title(.timeout, .es).contains("\n"))

        for language in [AppLanguage.en, .es] {
            #expect(IslandDiagramChrome.announces(.failure(.invalid)))
            #expect(IslandDiagramChrome.announces(.failure(.unavailable)))
            #expect(IslandDiagramChrome.announces(.failure(.timeout)))
            #expect(IslandDiagramChrome.announcement(.invalid, language: language)
                == Localized.string("island.diagram.failed", language: language))
            #expect(IslandDiagramChrome.announcement(.unavailable, language: language)
                == Localized.string("island.diagram.failed", language: language))
            #expect(IslandDiagramChrome.announcement(.timeout, language: language)
                == Localized.string("island.diagram.timeout", language: language))
        }
    }

    @Test func errorStatesRendersToastChipsInTheirTone() async throws {
        let center = NoticeCenter()
        center.toast("disk full", level: .error)
        center.toast("saved", level: .info)
        let hosted = Hosted(ToastStack(center: center))
        defer { hosted.close() }
        await settle(0.3)

        let ink = try hosted.ink()
        let background = ink.pixel(ink.width - 1, ink.height - 1)
        let chips = ink.bands(awayFrom: background)
        try #require(chips.count == 2, "expected two stacked chips, found \(chips.count)")
        let error = ink.dominantColour(rows: chips[0], awayFrom: background)
        let info = ink.dominantColour(rows: chips[1], awayFrom: background)
        #expect(error.isClose(to: srgb(Semantic.destructive)), "error chip is \(error)")
        #expect(info.isClose(to: srgb(Semantic.accent)), "info chip is \(info)")
    }

    @Test func errorStatesLoadingFaceDrawsASkeletonOnOneClock() async throws {
        let loading = try await renderLoading()
        defer { loading.release() }
        let ink = try loading.hosted.ink()
        let text = ink.recognizedText()
        #expect(ink.distinctColours > 2)
        #expect(!text.localizedCaseInsensitiveContains("mermaid"), "loading drew the source: \(text)")
        #expect(!looksLikeRetry(text), "loading drew a retry: \(text)")
        // A shimmer band over the pulse would make the fill vary along a row.
        let strip = ink.rowSpread(y: Int(CGFloat(100) * ink.scale), xs: Int(130 * ink.scale)..<Int(390 * ink.scale))
        #expect(strip <= 6, "the skeleton fill varies along its width by \(strip)")
    }

    @Test func errorStatesTimeoutFaceDrawsTheAlert() async throws {
        let loading = try await renderLoading()
        defer { loading.release() }
        let loadingInk = try loading.hosted.ink()
        let (failed, text) = try await renderFailure(.failed(.timeout))
        #expect(failed.share(differingFrom: loadingInk) > 0.02, "the alert is not the skeleton")
        #expect(text.localizedCaseInsensitiveContains(IslandDiagramChrome.title(.timeout)), "alert title missing: \(text)")
        #expect(text.localizedCaseInsensitiveContains("mermaid"), "failure hid the mermaid block: \(text)")
        #expect(text.localizedCaseInsensitiveContains("graph"), "failure hid the source: \(text)")
        #expect(!looksLikeRetry(text), "failure drew a retry: \(text)")
    }

    @Test func errorStatesPictureReplacesTheAlert() async throws {
        let (failed, _) = try await renderFailure(.failed(.timeout))
        let png = try #require(solidPNG(width: 80, height: 40))
        #expect(NSImage(data: png) != nil)
        let picture = DiagramImage(data: png, width: 80, height: 40, png: png, pngTransparent: png)
        let (drawn, text) = try await renderFailure(.image(picture))
        #expect(drawn.share(differingFrom: failed) > 0.02, "the picture replaces the alert")
        #expect(!text.localizedCaseInsensitiveContains("mermaid"), "success still shows the source: \(text)")
        #expect(!looksLikeRetry(text))
    }

    @Test func errorStatesUndecodableImageDrawsTheAlert() async throws {
        let loading = try await renderLoading()
        defer { loading.release() }
        let loadingInk = try loading.hosted.ink()
        let png = try #require(solidPNG(width: 80, height: 40))
        let good = DiagramImage(data: png, width: 80, height: 40, png: png, pngTransparent: png)
        let (drawn, _) = try await renderFailure(.image(good))
        let junk = DiagramImage(data: Data([0x00, 0x01, 0x02]), width: 80, height: 40)
        let (ink, text) = try await renderFailure(.image(junk))
        #expect(ink.distinctColours > 2)
        #expect(ink.share(differingFrom: loadingInk) > 0.02)
        #expect(ink.share(differingFrom: drawn) > 0.02, "a bad image is not the picture")
        #expect(text.localizedCaseInsensitiveContains(IslandDiagramChrome.title(.unavailable)), "alert title missing: \(text)")
        #expect(text.localizedCaseInsensitiveContains("mermaid"), "undecodable image hid the mermaid block: \(text)")
        #expect(!looksLikeRetry(text), "undecodable image drew a retry: \(text)")
    }

    private static let source = "graph TD\n  A-->B"

    /// A diagram whose renderer never answers: the model stays on loading.
    private func renderLoading() async throws -> LoadingRender {
        let renderer = ScriptedDiagramRenderer()
        let model = IslandDiagramModel()
        let hosted = Hosted(IslandDiagramVisual(block: DiagramBlock(source: Self.source), model: model)
            .environment(\.diagramRenderer, renderer))
        await pumpUntil("diagram stays loading", timeout: 2) { model.state == .loading }
        hosted.layout()
        await settle(0.1)
        return LoadingRender(hosted: hosted, renderer: renderer)
    }

    private func renderFailure(_ outcome: DiagramOutcome) async throws -> (Ink, String) {
        let block = DiagramBlock(source: Self.source)
        let renderer = ScriptedDiagramRenderer()
        renderer.provide(outcome)
        let model = IslandDiagramModel()
        await model.load(block, renderer: renderer, width: Double(IslandVisualMetrics.diagramWidth))
        let hosted = Hosted(IslandDiagramVisual(block: block, model: model)
            .environment(\.diagramRenderer, renderer))
        defer { hosted.close() }
        hosted.layout()
        await settle(0.2)
        let ink = try hosted.ink()
        return (ink, ink.recognizedText())
    }
}

@MainActor
private struct LoadingRender {
    let hosted: Hosted
    let renderer: ScriptedDiagramRenderer

    func release() {
        renderer.provide(.failed(.unavailable))
        hosted.close()
    }
}

private func srgb(_ color: Color) -> [Double] {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .clear
    return [ns.redComponent, ns.greenComponent, ns.blueComponent].map { Double($0) * 255 }
}

private extension Array where Element == Double {
    func isClose(to other: [Double], tolerance: Double = 14) -> Bool {
        zip(self, other).allSatisfy { abs($0 - $1) <= tolerance }
    }
}


@MainActor
private final class ScriptedDiagramRenderer: DiagramRendering {
    private var parked: CheckedContinuation<DiagramOutcome, Never>?
    private var queued: DiagramOutcome?

    func render(_ block: DiagramBlock, width: Double) async -> DiagramOutcome {
        if let queued { return queued }
        return await withCheckedContinuation { parked = $0 }
    }

    func provide(_ outcome: DiagramOutcome) {
        queued = outcome
        parked?.resume(returning: outcome)
        parked = nil
    }
}

private func uiCatalog(_ language: String) throws -> [String: String] {
    let root = try #require(Conformance.repoRoot())
    let url = root.appendingPathComponent("Sources/CompanionUI/\(language).lproj/Localizable.strings")
    return try #require(NSDictionary(contentsOf: url) as? [String: String])
}

private func looksLikeRetry(_ label: String) -> Bool {
    let folded = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    return folded.contains("retry") || folded.contains("reintent") || folded.contains("try again")
}

private func solidPNG(width: Int, height: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

@MainActor
private final class Hosted {
    let view: NSHostingView<AnyView>
    let window: NSWindow
    private let size = CGSize(width: 520, height: 360)

    init<V: View>(_ root: V) {
        view = NSHostingView(rootView: AnyView(
            root.frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Semantic.background)))
        view.frame = NSRect(origin: .zero, size: size)
        window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderBack(nil)
        layout()
    }

    func layout() {
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    func close() { window.orderOut(nil) }

    func ink() throws -> Ink {
        layout()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let cg = try #require(rep.cgImage)
        return try #require(Ink(cg, scale: CGFloat(rep.pixelsWide) / view.bounds.width))
    }
}

private struct Ink {
    let image: CGImage
    /// Pixels per point of the bitmap, so a point-space probe lands on the same spot at any backing scale.
    let scale: CGFloat
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ cg: CGImage, scale: CGFloat) {
        self.scale = scale
        image = cg
        width = cg.width
        height = cg.height
        var buffer = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        guard drew else { return nil }
        bytes = buffer
    }

    func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * width + x) * 4..<(y * width + x) * 4 + 3]) }

    /// Largest per-channel spread along one row: zero for a flat fill.
    func rowSpread(y: Int, xs: Range<Int>) -> Int {
        (0..<3).map { channel -> Int in
            let values = xs.map { Int(bytes[(y * width + $0) * 4 + channel]) }
            return (values.max() ?? 0) - (values.min() ?? 0)
        }.max() ?? 0
    }

    private func isBackground(_ x: Int, _ y: Int, _ background: [UInt8]) -> Bool {
        zip(pixel(x, y), background).allSatisfy { abs(Int($0) - Int($1)) <= 6 }
    }

    /// Runs of rows that hold anything but the background: one per stacked chip.
    func bands(awayFrom background: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?
        for y in 0..<height {
            let inked = (0..<width).contains { isBackground($0, y, background) == false }
            if inked, start == nil { start = y }
            if !inked, let from = start { result.append(from..<y); start = nil }
        }
        if let from = start { result.append(from..<height) }
        return result
    }

    /// The most common colour in the rows, which for a filled chip is its fill and not its text.
    func dominantColour(rows: Range<Int>, awayFrom background: [UInt8]) -> [Double] {
        var counts: [[UInt8]: Int] = [:]
        for y in rows {
            for x in 0..<width where !isBackground(x, y, background) { counts[pixel(x, y), default: 0] += 1 }
        }
        return (counts.max { $0.value < $1.value }?.key ?? []).map(Double.init)
    }

    var distinctColours: Int {
        var seen = Set<[UInt8]>()
        for y in stride(from: 0, to: height, by: 3) {
            for x in stride(from: 0, to: width, by: 3) { seen.insert(pixel(x, y)) }
        }
        return seen.count
    }

    func share(differingFrom other: Ink) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        var differing = 0
        for i in 0..<(width * height) {
            let delta = (0..<3).reduce(0) { $0 + abs(Int(bytes[i * 4 + $1]) - Int(other.bytes[i * 4 + $1])) }
            if delta > 24 { differing += 1 }
        }
        return Double(differing) / Double(width * height)
    }

    /// What a person can read off the bitmap. The hosting view's accessibility
    /// tree stays empty offscreen, so the rendered words are the check.
    func recognizedText() -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "es-ES"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
