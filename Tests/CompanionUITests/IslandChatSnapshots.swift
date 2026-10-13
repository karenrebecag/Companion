import AppKit
import CompanionCore
import CompanionUIPro
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

/// The island's written chat (`.chat`) as Arc's ai-chat on the result
/// document's paper: a table, a list, an answer with sources, a reply still
/// streaming, the specialist working, and the result card beside them.
@MainActor enum IslandChatFixture {
    static let phones = """
    Estos son los cinco celulares premium que más se comparan hoy:

    | Modelo | Pantalla | Procesador | Cámara principal | Batería |
    |---|---|---|---|--:|
    | iPhone 16 Pro Max | 6.9" OLED 120 Hz | A18 Pro | 48 MP triple | 4685 mAh |
    | Galaxy S25 Ultra | 6.9" AMOLED 120 Hz | Snapdragon 8 Elite | 200 MP cuádruple | 5000 mAh |
    | Pixel 9 Pro XL | 6.8" OLED 120 Hz | Tensor G4 | 50 MP triple | 5060 mAh |
    | Xiaomi 15 Ultra | 6.73" AMOLED 120 Hz | Snapdragon 8 Elite | 50 MP cuádruple | 5410 mAh |
    | OnePlus 13 | 6.82" AMOLED 120 Hz | Snapdragon 8 Elite | 50 MP triple | 6000 mAh |

    Si priorizas **batería**, el OnePlus 13 dura más; para **foto**, el Galaxy S25 Ultra.
    """

    static let list = """
    Para tu viaje a Lima te conviene llevar:

    1. **Pasaporte** vigente con al menos seis meses.
    2. Un adaptador tipo A; los enchufes son de 220 V.
    3. Ropa en capas: en noviembre la mañana es fresca y la tarde templada.

    - Cambia pocos soles en el aeropuerto, el tipo de cambio es peor.
    - Descarga los mapas offline de Miraflores y Barranco.
    """

    static let sourced = """
    El Banco de México dejó la tasa en **7.25 %** en su última decisión [1], y los analistas esperan otro recorte antes de fin de año [2].

    > La inflación subyacente siguió bajando por quinto mes consecutivo.

    Fuentes:
    - [Anuncio de política monetaria](https://www.banxico.org.mx/publicaciones/anuncio.html)
    - [Encuesta de expectativas](https://www.eleconomista.com.mx/mercados/encuesta)
    """

    static func conversation(_ question: String, _ answer: String) -> [ChatMessage] {
        [
            ChatMessage(role: .user, text: "Hola, ¿me ayudas con algo rápido?"),
            ChatMessage(role: .assistant, text: "Claro, dime."),
            ChatMessage(role: .user, text: question),
            ChatMessage(role: .assistant, text: answer),
        ]
    }

    static var streaming: (messages: [ChatMessage], live: ChatLive) {
        let cut = String(phones.prefix(420))
        return ([ChatMessage(role: .user, text: "Compárame los celulares premium que existen.")],
                ChatLive(streaming: cut, busy: true, job: nil, now: Date()))
    }
}

/// The notch as the island draws it: black, the band with its controls,
/// the panel on its paper under them.
private struct ChatShot: View {
    let messages: [ChatMessage]
    let live: ChatLive?
    @State var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: IslandChrome.shellSpacing) {
            HStack {
                IslandHeaderControls(popover: .constant(nil))
                Spacer()
            }
            .frame(height: 32)
            IslandChatPanel(
                thread: IslandChatModel.thread(messages, live: live), maxHeight: IslandChrome.columnCap,
                onOpenURL: { _ in }, rows: { EmptyView() }) {
                AIChatComposer(
                    action: .resolve(busy: live?.busy ?? false, canSend: !draft.isEmpty),
                    focused: false,
                    strings: AIChatComposerStrings(send: "Enviar", stop: "Parar"),
                    style: .notchComposer, onSend: {}, onStop: {},
                    field: {
                        IslandComposerField(draft: $draft, focused: $focused, onSend: {},
                                            size: DocChatMetrics.fieldSize, lineHeight: DocChatMetrics.fieldLine,
                                            placeholderInk: AIThreadStyle.notchChat.muted)
                    },
                    leading: {
                        IconButton("paperclip", label: "Adjuntar", size: .chatTool, tone: .island, chip: true) {}
                    },
                    trailing: {
                        IslandVoiceOrb(state: .composer(levels: VoiceLevels(mic: 0, agent: 0)), size: IconButtonSize.chatTool.side)
                    })
            }
        }
        .padding(.horizontal, IslandChrome.docShellMargin)
        .padding(.bottom, IslandChrome.shellBottom)
        .background(RoundedRectangle(cornerRadius: NotchShape.openRadius).fill(IslandInk.panel))
        .environment(\.colorScheme, .dark)
        .padding(24)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func islandChatGallery() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let size = CGSize(width: IslandChrome.docCardWidth + 48, height: 720)
    let fixture = IslandChatFixture.self
    let cases: [(String, [ChatMessage], ChatLive?)] = [
        ("tabla", fixture.conversation("Compárame los celulares premium que existen.", fixture.phones), nil),
        ("lista", fixture.conversation("¿Qué llevo a Lima?", fixture.list), nil),
        ("fuentes", fixture.conversation("¿Cómo quedó la tasa de Banxico?", fixture.sourced), nil),
        ("streaming", fixture.streaming.messages, fixture.streaming.live),
        ("especialista", [ChatAgentRunFixture.question], ChatAgentRunFixture.live),
    ]
    for (name, messages, live) in cases {
        for scheme in [ColorScheme.light, .dark] {
            try await saveLive(AnyView(ChatShot(messages: messages, live: live)), scheme: scheme, size: size,
                               to: out, "isla-chat-\(name)-\(scheme == .dark ? "dark" : "light")")
        }
    }
    // The result card it has to match, as the island draws it today.
    let document = IslandResultCardModel.document(of: fixture.phones)
    for scheme in [ColorScheme.light, .dark] {
        try await saveLive(
            AnyView(IslandResultCard(
                title: "Compárame los celulares premium que existen", blocks: document.blocks, links: .none,
                maxHeight: IslandChrome.columnCap, onOpenURL: { _ in }, onDismiss: nil, onContinue: {}) { EmptyView() }
                .padding(.horizontal, IslandChrome.docShellMargin)
                .padding(.vertical, IslandChrome.shellBottom)
                .background(RoundedRectangle(cornerRadius: NotchShape.openRadius).fill(IslandInk.panel))
                .environment(\.colorScheme, .dark)
                .padding(24)),
            scheme: scheme, size: size, to: out, "isla-docCard-referencia-\(scheme == .dark ? "dark" : "light")")
    }
}
