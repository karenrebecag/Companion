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
        Group {
            switch model.state {
            case .failed(let failure):
                fallback(failure)
            case .loading:
                surface(tools: nil) { loading }
            case .image(let drawn):
                // Bytes that do not decode are a failure like any other.
                if let image = Self.decode(drawn) {
                    surface(tools: drawn) { picture(image, drawn) }
                } else {
                    fallback(.unavailable)
                }
            }
        }
        // Keyed on the block: a message that streams in gets one render for
        // the text it finished with.
        .task(id: block) {
            await model.load(block, renderer: renderer, width: Double(IslandVisualMetrics.diagramWidth))
        }
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
        HStack(spacing: Space.x2) {
            ProgressView().controlSize(.small)
            Text(Localized.string("island.diagram.loading"))
                .font(Fonts.geist(AnswerBlockMetrics.tableSize))
                .foregroundStyle(AnswerInk.white(AnswerInk.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A timeout says so; every other failure is the same plain note.
    static func noteKey(_ failure: DiagramFailure) -> String {
        switch failure {
        case .timeout: "island.diagram.timeout"
        case .invalid, .unavailable: "island.diagram.failed"
        }
    }

    private func fallback(_ failure: DiagramFailure) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(Localized.string(Self.noteKey(failure)))
                .font(Fonts.geist(AnswerBlockMetrics.tableSize))
                .foregroundStyle(AnswerInk.white(AnswerInk.secondary))
            AnswerCodeBlock(language: "mermaid", body: block.source)
        }
    }
}
