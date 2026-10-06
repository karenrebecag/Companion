import AppKit
import CompanionCore
import SwiftUI

// Wave 16m-5b: a Mermaid diagram in the `visual` container, with Incredible's
// tools: copy the image and download the PNG, each with the popup's background
// or without it. The picture comes from the renderer the composition root
// injects; when there is none, or it fails or takes too long, the same text
// shows as code with the reason.

struct IslandDiagramVisual: View {
    let block: DiagramBlock
    @Environment(\.diagramRenderer) private var renderer
    @Environment(\.fileSaver) private var saveFile
    @State private var model: IslandDiagramModel

    /// The model is injectable so a snapshot can show a state the `.task`
    /// (which ImageRenderer never runs) would otherwise have to reach.
    init(block: DiagramBlock, model: IslandDiagramModel = IslandDiagramModel()) {
        self.block = block
        _model = State(initialValue: model)
    }

    var body: some View {
        let shown = snapshot
        Group {
            switch shown.face {
            case .failure(let failure):
                fallback(failure)
            case .loading:
                surface(tools: nil) { loading }
            case .success:
                if let image = shown.image, let data = shown.data {
                    surface(tools: data) { picture(image, data) }
                }
            }
        }
        // Keyed on the block: a message that streams in gets one render for
        // the text it finished with.
        .task(id: block) {
            await model.load(block, renderer: renderer, width: Double(IslandVisualMetrics.diagramWidth))
        }
    }

    private var snapshot: IslandDiagramSnapshot {
        let image: NSImage?
        let data: DiagramImage?
        switch model.state {
        case .image(let drawn):
            image = Self.decode(drawn)
            data = drawn
        default:
            image = nil
            data = nil
        }
        return IslandDiagramSnapshot(
            face: IslandDiagramChrome.face(model.state, decoded: image != nil),
            image: image,
            data: data)
    }

    static func decode(_ drawn: DiagramImage) -> NSImage? {
        guard let image = NSImage(data: drawn.data) else { return nil }
        image.size = IslandDiagramLayout.displaySize(drawn)
        return image
    }

    private func surface<Content: View>(tools: DiagramImage?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            header(tools)
            content()
            if model.saveFailed {
                Text(Localized.string("island.diagram.save.failed"))
                    .font(Fonts.geist(AnswerBlockMetrics.tableSize))
                    .foregroundStyle(AnswerInk.white(AnswerInk.secondary))
            }
        }
        .islandVisualSurface()
    }

    private func header(_ drawn: DiagramImage?) -> some View {
        HStack(spacing: Space.x2) {
            Text(Localized.string("island.diagram.label"))
                .font(Fonts.geist(AnswerBlockMetrics.tableSize).weight(.semibold))
                .foregroundStyle(AnswerInk.white(AnswerInk.text))
                .lineLimit(1)
            Spacer(minLength: Space.none)
            // An export the page could not make is a tool that is not offered.
            if let drawn, IslandDiagramTools.pngData(drawn, background: model.includesBackground) != nil {
                IconButton(model.includesBackground ? "rectangle.fill" : "rectangle.dashed",
                           label: Localized.string(Self.backgroundKey(model.includesBackground)),
                           size: .islandClose, tone: .island, pressable: true, action: model.toggleBackground)
                IslandVisualCopyButton(copyLabel: "island.diagram.copy", copiedLabel: "island.diagram.copied") {
                    IslandDiagramTools.copyImage(drawn, background: model.includesBackground)
                }
                if let saveFile {
                    IconButton("arrow.down.to.line", label: Localized.string("island.diagram.download"),
                               size: .islandClose, tone: .island, pressable: true) {
                        let background = model.includesBackground
                        Task {
                            let result = await IslandDiagramTools.download(drawn, background: background, save: saveFile)
                            model.record(result)
                        }
                    }
                }
            }
        }
    }

    /// What the toggle will do to the next copy or download.
    static func backgroundKey(_ on: Bool) -> String {
        switch on {
        case true: "island.diagram.background.on"
        case false: "island.diagram.background.off"
        }
    }

    /// The picture at its own size: narrower than that, the container
    /// scrolls sideways instead of shrinking it.
    private func picture(_ image: NSImage, _ drawn: DiagramImage) -> some View {
        let size = IslandDiagramLayout.displaySize(drawn)
        let picture = Image(nsImage: image)
            .frame(width: size.width, height: size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Localized.string("island.diagram.label"))
            .accessibilityValue(block.source)
        return ViewThatFits(in: .horizontal) {
            picture
            ScrollView(.horizontal) { picture }.scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var loading: some View {
        // The house skeleton is the pulse (see Skeleton.swift); the shimmer
        // sweep is opt-in, and stacking it would run a second clock.
        SkeletonPulse { opacity in
            SkeletonBlock(
                width: nil,
                height: IslandVisualMetrics.diagramSkeletonHeight,
                radius: IslandVisualMetrics.radius,
                opacity: opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(IslandDiagramChrome.loadingLabel())
    }

    /// No retry control: the model draws again only when `load` is asked,
    /// and nothing on it is a retry the view can call.
    private func fallback(_ failure: DiagramFailure) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            alert(failure)
            AnswerCodeBlock(language: "mermaid", body: block.source)
        }
    }

    private func alert(_ failure: DiagramFailure) -> some View {
        HStack(alignment: .top, spacing: Space.x2) {
            Image(systemName: IslandDiagramChrome.symbol)
                .font(Fonts.symbol(IslandVisualMetrics.diagramAlertIcon, weight: .medium))
                .foregroundStyle(Semantic.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(IslandDiagramChrome.title(failure))
                    .font(Fonts.geist(AnswerBlockMetrics.tableSize).weight(.semibold))
                    .foregroundStyle(Semantic.danger)
                    .lineLimit(1)
                Text(IslandDiagramChrome.detail(failure))
                    .font(Fonts.geist(AnswerBlockMetrics.tableSize))
                    .foregroundStyle(Semantic.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Semantic.dangerMuted))
        .accessibilityElement(children: .contain)
        .onAppear {
            guard IslandDiagramChrome.announces(.failure(failure)) else { return }
            AccessibilityNotification.Announcement(IslandDiagramChrome.announcement(failure)).post()
        }
    }
}

private struct IslandDiagramSnapshot {
    var face: IslandDiagramChrome.Face
    var image: NSImage?
    var data: DiagramImage?
}

enum IslandDiagramChrome {
    enum Face: Equatable {
        case loading
        case failure(DiagramFailure)
        case success
    }

    static let symbol = "exclamationmark.triangle.fill"

    static func face(_ state: IslandDiagramModel.State, decoded: Bool) -> Face {
        switch state {
        case .loading: .loading
        case .failed(let failure): .failure(failure)
        case .image:
            // Bytes that do not decode are a failure like any other.
            decoded ? .success : .failure(.unavailable)
        }
    }

    static func announces(_ face: Face) -> Bool {
        if case .failure = face { return true }
        return false
    }

    static func loadingLabel(_ language: AppLanguage = Localized.language()) -> String {
        Localized.string("island.diagram.loading", language: language)
    }

    static func title(_ failure: DiagramFailure, _ language: AppLanguage = Localized.language()) -> String {
        parts(failure, language).title
    }

    static func detail(_ failure: DiagramFailure, _ language: AppLanguage = Localized.language()) -> String {
        parts(failure, language).detail
    }

    /// Danger interrupts, the way Arc's alert uses role="alert". VoiceOver
    /// hears the sentence the diagram already shipped, not a second copy.
    static func announcement(_ failure: DiagramFailure, language: AppLanguage = Localized.language()) -> String {
        sentence(failure, language)
    }

    private static func sentence(_ failure: DiagramFailure, _ language: AppLanguage) -> String {
        let key = switch failure {
        case .timeout: "island.diagram.timeout"
        case .invalid, .unavailable: "island.diagram.failed"
        }
        return Localized.string(key, language: language)
    }

    /// The catalog keeps one sentence. The alert shows its first clause on
    /// one line and the rest as the secondary line.
    private static func parts(_ failure: DiagramFailure, _ language: AppLanguage) -> (title: String, detail: String) {
        let line = sentence(failure, language)
        guard let split = line.range(of: ". ") else { return (line, "") }
        return (String(line[..<split.lowerBound]), String(line[split.upperBound...]))
    }
}
