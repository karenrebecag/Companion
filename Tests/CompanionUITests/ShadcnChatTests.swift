import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

@MainActor private func chatSame(_ got: Color?, _ want: Color, _ label: String) {
    guard let got else { expect(false, label); return }
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        var a: [CGFloat] = [], b: [CGFloat] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            a = chatRGBA(got); b = chatRGBA(want)
        }
        expectEq(a, b, "\(label) (\(name.rawValue))")
    }
}

private func chatRGBA(_ c: Color) -> [CGFloat] {
    let n = NSColor(c).usingColorSpace(.sRGB) ?? .clear
    return [n.redComponent, n.greenComponent, n.blueComponent, n.alphaComponent]
}

@MainActor private func chatBitmap(_ view: some View, scheme: ColorScheme = .light) -> Data? {
    let framed = view
        .padding(Space.x4)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

/// shadcn's bubble: rounded-xl, px-3 py-2, text-sm, max-w 80 %.
@Test @MainActor func bubbleMetricsFollowTheScales() {
    expectEq(BubbleMetrics.paddingX, Space.x3, "px-3")
    expectEq(BubbleMetrics.paddingY, Space.x2, "py-2")
    expectEq(BubbleMetrics.radius, Radius.bubble, "rounded-xl")
    expectEq(Radius.bubble, 12, "rounded-xl is 0.75rem")
    expectEq(BubbleMetrics.fontSize, TypeSize.rowTitle, "text-sm")
    expectEq(BubbleMetrics.maxWidthFraction, 0.8, "max-w-[80%]")
    expectEq(MessageMetrics.gap, Space.x2, "gap-2")
}

@Test @MainActor func bubbleVariantRoles() {
    chatSame(BubbleVariant.default.background, Semantic.primary, "default: bg-primary")
    chatSame(BubbleVariant.default.foreground, Semantic.primaryForeground, "default: text")
    chatSame(BubbleVariant.secondary.background, Semantic.muted, "secondary: bg-secondary")
    chatSame(BubbleVariant.secondary.foreground, Semantic.foreground, "secondary: text")
    chatSame(BubbleVariant.outline.background, Semantic.background, "outline: bg-background")
    chatSame(BubbleVariant.outline.border, Semantic.border, "outline: border")
    chatSame(BubbleVariant.ghost.background, .clear, "ghost: transparent")
    chatSame(BubbleVariant.destructive.background, Semantic.dangerWash, "destructive: bg/10")
    chatSame(BubbleVariant.destructive.foreground, Semantic.destructive, "destructive: text")
    expect(!BubbleVariant.ghost.padded, "ghost has no padding")
    for variant in BubbleVariant.allCases where variant != .ghost {
        expect(variant.padded, "\(variant) is padded")
    }
    for variant in BubbleVariant.allCases where variant != .outline {
        expect(variant.border == nil, "only outline has a border: \(variant)")
    }
}

/// The user speaks on the right in the primary bubble; the reply sits on
/// the left in the secondary one.
@Test @MainActor func messageAlignmentFollowsTheRole() {
    expectEq(MessageAlign(role: .user), .end, "user is align=end")
    expectEq(MessageAlign(role: .assistant), .start, "assistant is align=start")
    expectEq(MessageAlign(role: nil), .start, "unknown is align=start")
    expectEq(BubbleVariant(role: .user), .default, "user bubble is primary")
    expectEq(BubbleVariant(role: .assistant), .secondary, "reply bubble is secondary")
}

@Test @MainActor func markerVariantsAndRendering() throws {
    expect(MarkerVariant.separator.drawsRules, "separator draws rules")
    expect(!MarkerVariant.default.drawsRules, "default draws none")
    expect(MarkerVariant.border.drawsBottomBorder, "border draws the bottom line")
    var seen: [Data] = []
    for variant in MarkerVariant.allCases {
        let png = try #require(chatBitmap(
            Marker("hace 2 h", systemImage: "clock", variant: variant).frame(width: 240)), "render: \(variant)")
        #expect(!seen.contains(png), "\(variant) looks like another marker")
        seen.append(png)
    }
}

@Test @MainActor func bubblesRenderDistinctlyAndUserDiffersFromReply() throws {
    var seen: [BubbleVariant: Data] = [:]
    for variant in BubbleVariant.allCases {
        let png = try #require(chatBitmap(
            ChatBubble(variant: variant, align: .start) { Text("Hola") }.frame(width: 240)), "render: \(variant)")
        for (other, data) in seen { #expect(png != data, "\(variant) looks like \(other)") }
        seen[variant] = png
    }
    let start = try #require(chatBitmap(ChatBubble(variant: .default, align: .start) { Text("Hola") }.frame(width: 240)))
    let end = try #require(chatBitmap(ChatBubble(variant: .default, align: .end) { Text("Hola") }.frame(width: 240)))
    #expect(start != end, "align=end pushes the bubble to the right")
}

/// The layout math behind "max 80 %, pinned to one edge", without a window.
@Test @MainActor func bubbleGeometryCapsAndPinsTheChild() {
    expectEq(BubbleGeometry.childWidth(row: 240, fraction: 0.8), 192, "capped at 80 % of the row")
    expectEq(BubbleGeometry.childWidth(row: 240, fraction: 1), 240, "ghost spans the row")
    expectEq(BubbleGeometry.originX(row: 240, child: 100, align: .start), 0, "start pins left")
    expectEq(BubbleGeometry.originX(row: 240, child: 100, align: .end), 140, "end pins right")
    expectEq(BubbleGeometry.originX(row: 240, child: 192, align: .end), 48, "a full-width cap leaves the 20 % gutter")
    expectEq(BubbleGeometry.childWidth(row: -5, fraction: 0.8), 0, "a negative proposal never goes below zero")
}

/// The sheet's thread: which message becomes which turn, and what it carries.
@Test @MainActor func taskThreadMapsMessagesToTurns() {
    let file = AttachmentRef(name: "plan.pdf", path: "/tmp/plan.pdf", kind: .file)
    let messages = [
        ChatMessage(role: .user, text: "a", attachments: [file]),
        ChatMessage(role: .assistant, text: "b"),
        ChatMessage(role: nil, isStatus: true, text: "status"),
        ChatMessage(role: .user, text: "c"),
    ]
    let items = TaskThread.items(messages)
    expectEq(items.count, 3, "status lines stay out of the thread")
    expectEq(items.map(\.role), [.user, .assistant, .user], "user turns and replies keep their side")
    expectEq(items.map(\.text), ["a", "b", "c"], "order is kept")
    expectEq(items[0].attachments, ["plan.pdf"], "a sent file shows by name")
    expectEq(items.map(\.id), messages.filter { !$0.isStatus }.map(\.id.uuidString), "ids are the messages' own")
}

/// Tool chips only from what the reply recorded: once each, in call order,
/// and never on a user turn or a reply read back from disk.
@Test @MainActor func taskThreadToolsComeFromTheRecall() {
    func call(_ name: String) -> ToolCallRef { ToolCallRef(id: UUID().uuidString, name: name, arguments: "{}") }
    let reply = ChatMessage(
        role: .assistant, text: "Listo.",
        recall: Recall(role: .assistant, content: "Listo.", toolCalls: [call("look"), call("click"), call("look")]))
    expectEq(TaskThread.tools(of: reply), ["look", "click"], "deduplicated, first call first")
    expectEq(TaskThread.tools(of: ChatMessage(role: .assistant, text: "x", restored: true)), [], "no record, no chips")
    let user = ChatMessage(role: .user, text: "x", recall: Recall(role: .user, content: "x", toolCalls: [call("see")]))
    expectEq(TaskThread.tools(of: user), [], "a user turn never shows tools")
}

@Test @MainActor func taskSubtitleCountsMessages() async {
    await Localized.scoped(to: .es) {
        expectEq(TaskThread.subtitle(ago: "Hace 2 h", count: 10), "Hace 2 h · 10 mensajes", "plural")
        expectEq(TaskThread.subtitle(ago: "Ahora", count: 1), "Ahora · 1 mensaje", "singular")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func shadcnChatGallery() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let task = ConversationMeta(id: "t1", title: "Vuelos a Lima", updatedAt: Date().addingTimeInterval(-7200))
    let messages = [
        ChatMessage(role: .user, text: "Busca vuelos a Lima para el martes"),
        ChatMessage(role: .assistant, text: "El mas barato sale el martes por 3.200 MXN, con una escala en Bogota."),
        ChatMessage(role: .user, text: "Reservalo"),
    ]
    // A ScrollView paints nothing under ImageRenderer, so the sheet goes
    // through a hosted window like the island galleries.
    for scheme in [ColorScheme.light, .dark] {
        try await saveLive(
            AnyView(TaskDetailSheet(task: task, messages: messages, canFollowUp: true, onFollowUp: { _ in true }, onClose: {})),
            scheme: scheme, size: CGSize(width: 760, height: 420), to: out,
            "shadcn-chat-\(scheme == .dark ? "dark" : "light")")
    }
}
