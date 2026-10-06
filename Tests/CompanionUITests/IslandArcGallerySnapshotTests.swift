import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The island's states on Arc's grid, side by side, as PNGs on demand
// (COMPANION_SNAPSHOTS). Built from the same pieces the island draws, in the
// open island's column on its black surface, so a reviewer sees every lead
// mark line up and every text start at the same x.

@MainActor private func panel<V: View>(_ title: String, @ViewBuilder _ body: () -> V) -> some View {
    VStack(alignment: .leading, spacing: IslandGrid.groupGap) { body() }
        .frame(width: IslandGrid.openColumn, alignment: .leading)
        .padding(IslandChrome.shellMargin)
        .background(RoundedRectangle(cornerRadius: NotchShape.openRadius).fill(Color.black))
        .overlay(alignment: .topLeading) {
            Text(verbatim: title).font(.caption).foregroundStyle(.gray).offset(y: -18)
        }
        .padding(.top, 22)
}

@MainActor private func statusRow<Lead: View>(_ text: String, @ViewBuilder lead: @escaping () -> Lead) -> some View {
    IslandGridRow(lead: lead) {
        Text(verbatim: text).font(Fonts.geist(TypeSize.rowTitle)).foregroundStyle(IslandInk.text)
    }
}

// Skipped, not green, when no snapshot directory is set.
@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil)) @MainActor
func islandArcGallerySnapshots() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"])
    let t0 = Date().addingTimeInterval(-80)
    var job = JobTimeline(goal: "Ordenar las capturas", startedAt: t0)
    job.steps = [
        JobStepInfo(tool: "Glob", label: "Glob: ~/Desktop/*.png", done: true, id: "a", startedAt: t0,
                    finishedAt: t0.addingTimeInterval(4)),
        JobStepInfo(tool: "Read", label: "Read: inventario.md", done: true, id: "b",
                    startedAt: t0.addingTimeInterval(4), finishedAt: t0.addingTimeInterval(12)),
        JobStepInfo(tool: "Bash", label: "Bash: mkdir Capturas", done: true, failed: true, id: "c",
                    startedAt: t0.addingTimeInterval(12), finishedAt: t0.addingTimeInterval(20)),
        JobStepInfo(tool: "Write", label: "Write: plan.md", id: "d", startedAt: t0.addingTimeInterval(20)),
    ]
    let receipt = try #require(ActionReceipt(entries: [
        ReceiptLine(text: "Abrí Safari.", verified: false), ReceiptLine(text: "Escribí el texto.", verified: true),
    ]))
    let notice = try #require(IslandNotice.content(for: .couldntHear))
    let approval = ApprovalRequest(requestId: "r", toolName: "Bash", summary: "rm -rf ~/Desktop/tmp",
                                   inputJSON: #"{"command":"rm -rf ~/Desktop/tmp"}"#)

    let gallery = HStack(alignment: .top, spacing: 32) {
        VStack(alignment: .leading, spacing: 28) {
            panel("Pensando") {
                statusRow("Pensando…") { VoiceOrb(state: .thinking, size: IslandGrid.lead, still: true) }
            }
            panel("Escuchando") {
                statusRow("Escucho") { VoiceOrb(state: .listening, size: IslandGrid.lead, still: true) }
                IslandTranscript(text: "abre el correo de ana y dime qué pide", fixed: false)
                    .islandContentColumn()
            }
            panel("Encargo") {
                IslandGridRow {
                    MorphLoader(status: .loading, size: AgentRunMetrics.loader, tone: false)
                        .foregroundStyle(ArcTone.foreground.color)
                } content: {
                    Text(verbatim: "Ordenar las capturas · 4 pasos").font(Fonts.geist(TypeSize.rowTitle))
                        .foregroundStyle(IslandInk.text)
                } trail: {
                    Text(verbatim: "1:20").font(Fonts.geist(AgentRunMetrics.metaSize).monospacedDigit())
                        .foregroundStyle(ArcTone.textSecondary.color)
                }
                IslandRunCard(job: job, expanded: true)
            }
        }
        VStack(alignment: .leading, spacing: 28) {
            panel("Recibo") { IslandReceiptCard(receipt: receipt, onDismiss: {}) }
            panel("Aviso") {
                IslandNoticeCard(content: notice, pausesClock: false, onHover: { _ in }, onAction: { _ in },
                                 onDismiss: {})
            }
            panel("Aprobación") { ApprovalSheet(request: approval, surface: .island) { _, _ in } }
            panel("Dictado") {
                IslandDictationCard(app: "Slack", text: "Nos vemos a las cinco en la sala grande.",
                                    onCopy: {}, onHide: {}, onHover: { _ in })
            }
        }
        VStack(alignment: .leading, spacing: 28) {
            panel("Pregunta") {
                AnswerOption(index: 0, title: "Esta tarde", detail: "A las cinco", state: .selected,
                             accessibility: "", action: {})
                AnswerOption(index: 1, title: "Mañana", detail: nil, state: .cursor, accessibility: "", action: {})
                AnswerOption(index: 2, title: "La semana que viene", detail: nil, state: .idle,
                             accessibility: "", action: {})
            }
            panel("Confirmar y deshacer") {
                IslandClearConfirm(onClear: {}, onCancel: {})
                IslandReceiptRow(receipt: UndoReceipt(kind: .created, subject: "plan.md"), onUndo: {})
            }
            panel("Menu y tooltip") {
                HStack(alignment: .top, spacing: 16) {
                    IslandPopover { IslandMenuList { _ in } }
                    IslandTooltipBubble(text: "Adjuntar archivos")
                }
            }
            panel("Resultado y soltar") {
                if let result = IslandResult(reply: "Correo de Ana. Pide el informe del viernes.") {
                    IslandResultCard(result: result, onOpen: {})
                }
                IslandDropZones(zone: .ask)
                ReferentChip(text: "Notas.app")
            }
        }
    }
    .padding(32)
    .background(Color(white: 0.12))
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: gallery)
    renderer.scale = 2
    let tiff = try #require(renderer.nsImage?.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("island-arc-gallery.png"))
}
