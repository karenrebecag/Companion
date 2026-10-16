import CompanionCore
import CompanionUIPro
import SwiftUI

/// The blocks of a `present` call, drawn. Core already chose the component
/// for each one (`PresentRender`); this view only paints that choice. The
/// island passes `compact`: the same content with less height and no axes it
/// can do without.
package struct PresentView: View {
    package let renders: [PresentRender]
    package var compact = false

    package init(_ renders: [PresentRender], compact: Bool = false) {
        self.renders = renders
        self.compact = compact
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.x3 : Space.x4) {
            ForEach(Array(renders.enumerated()), id: \.offset) { _, render in
                PresentRenderView(render: render, measures: PresentMeasures(compact: compact))
            }
        }
        .datosStrings(PresentStrings.datos)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One block, routed to the file that paints its family.
struct PresentRenderView: View {
    let render: PresentRender
    let measures: PresentMeasures

    var body: some View {
        switch render {
        case .prose(let block):
            PresentProse(block: block, compact: measures.compact)
        case .notice(let note):
            PresentNotice(note: note)
        case .sortableTable(let table):
            PresentTitled(title: table.title) { PresentTableView(table: table, measures: measures, filterable: false) }
        case .filterableTable(let table):
            PresentTitled(title: table.title) { PresentTableView(table: table, measures: measures, filterable: true) }
        case .slope, .donut, .splitBar, .treemap, .line, .brush, .streamgraph, .bar:
            PresentChart(render: render, measures: measures)
        case .metrics(let title, let tiles):
            PresentTitled(title: title) { PresentMetricsView(tiles: tiles, measures: measures) }
        case .timeline(let timeline):
            PresentTitled(title: timeline.title) { PresentTimelineView(timeline: timeline, measures: measures) }
        case .countdown(let event):
            PresentCountdown(event: event, compact: measures.compact)
        case .places(let places):
            MapCard(block: LocationsBlock(
                title: places.title,
                locations: places.places.map {
                    LocationsBlock.Location(
                        name: $0.name, address: $0.address, lat: $0.lat, lng: $0.lng, url: $0.url)
                }))
        case .treeView(let files):
            PresentTitled(title: files.title) { PresentTree(files: files) }
        case .chips(let files):
            PresentTitled(title: files.title) { PresentChips(files: files) }
        case .code(let code):
            PresentTitled(title: code.isDiff ? nil : code.title) { PresentCodeView(code: code, measures: measures) }
        case .sources(let sources):
            SourcesCard(
                webSources: sources.map { MarkdownSplitter.SourceLink(title: $0.title, url: $0.url) },
                fileSources: [])
        }
    }
}

/// A block's own title above it, once: the components take a label for
/// VoiceOver but do not draw one.
struct PresentTitled<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.uiSubtitle)
                    .foregroundStyle(Semantic.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
