import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The drop zone's honesty: the highlight follows the drag, a refused file says
// why, and an accepted one lands in the same pending list the window shows.

private struct RefusingStore: AttachmentStoring {
    let error: AttachmentError
    func adopt(_ source: URL, conversationId: String) throws -> AttachmentRef { throw error }
    func adopt(imageData: Data, name: String, conversationId: String) throws -> AttachmentRef { throw error }
    func restore(path: String) -> AttachmentRef? { nil }
    func discard(_ ref: AttachmentRef) {}
    func payload(for ref: AttachmentRef) -> AttachmentPayload? { nil }
}

private final class Said {
    var lines: [String] = []
    var failures: [IslandAttachFailure] = []
}

@MainActor private func actions(_ store: any AttachmentStoring, _ said: Said) -> (IslandAttachActions, ChatViewModel) {
    let chat = ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                             store: MemoryConversationStore(), config: Config(), attachments: store)
    let voice = VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter())
    return (IslandAttachActions(chat: chat, voice: voice, grabber: nil,
                                say: { said.lines.append($0) },
                                onFail: { said.failures.append($0) }), chat)
}

@Test @MainActor func theHighlightFollowsEnterMoveAndExit() {
    var highlight = IslandDropHighlight()
    expectEq(highlight.enter(hasFiles: false), .ignored, "a drag without files is not answered")
    expect(!highlight.dropping, "a drag without files lights nothing")
    expect(!highlight.move(to: .ask), "moving before entering changes nothing")
    expectEq(highlight.zone, nil, "no zone before entering")

    expectEq(highlight.enter(hasFiles: true), .began, "files entering are answered")
    expect(highlight.dropping, "entering lights the island")
    expect(highlight.move(to: .airDrop), "moving over a zone is answered")
    expectEq(highlight.zone, .airDrop, "the zone under the pointer is lit")
    expect(highlight.move(to: nil), "leaving the card is still a move")
    expectEq(highlight.zone, nil, "outside the card no zone is lit")

    highlight.end()
    expect(!highlight.dropping, "exit clears the highlight")
    expectEq(highlight.zone, nil, "exit clears the zone")
}

@Test @MainActor func aDropLandsInTheLitZoneAndClearsTheHighlight() {
    var highlight = IslandDropHighlight()
    _ = highlight.enter(hasFiles: true)
    _ = highlight.move(to: .airDrop)
    expectEq(highlight.drop(), .airDrop, "dropped over AirDrop lands in AirDrop")
    expectEq(highlight, IslandDropHighlight(), "the drop clears the highlight")

    _ = highlight.enter(hasFiles: true)
    expectEq(highlight.drop(), .ask, "dropped before the card opened, asking is the default")
}

@Test @MainActor func aDroppedFileReachesThePendingAttachments() {
    let said = Said()
    let (island, chat) = actions(MemoryAttachments(), said)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString).txt")
    try? Data("hola".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    island.drop([file], zone: .ask)
    expectEq(chat.pendingAttachments.map(\.name), [file.lastPathComponent], "the drop attaches the file")
    expect(said.failures.isEmpty && said.lines.isEmpty, "an accepted file says nothing")
}

@Test @MainActor func aTooLargeFileSaysWhy() {
    let said = Said()
    let (island, chat) = actions(RefusingStore(error: .tooLarge), said)
    island.stage(URL(fileURLWithPath: "/tmp/enorme.mov"))
    expect(chat.pendingAttachments.isEmpty, "a refused file is not attached")
    expectEq(said.failures.first?.reason, ChatCopy.attachFailed(.tooLarge), "the card carries the size reason")
    expectEq(said.lines, [ChatCopy.attachFailed(.tooLarge)], "the reason is said under the field")
}

@Test @MainActor func aFolderSaysItIsNotAFile() throws {
    let said = Said()
    let (island, chat) = actions(MemoryAttachments(), said)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dir-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    island.drop([folder], zone: .ask)
    expect(chat.pendingAttachments.isEmpty, "a folder is not attached")
    expectEq(said.failures.first?.reason, Localized.string("island.attach.notFile"), "the folder gets its own reason")
}

@Test @MainActor func aDragIsAnnouncedOnceNotOnEveryEnter() {
    var highlight = IslandDropHighlight()
    expectEq(highlight.enter(hasFiles: true), .began, "the first enter begins the drag")
    expectEq(highlight.enter(hasFiles: true), .continued, "a second enter without an end is the same drag")
    highlight.end()
    expectEq(highlight.enter(hasFiles: true), .began, "after the end a new drag begins")

    var active = IslandDropHighlight()
    _ = active.enter(hasFiles: true)
    _ = active.move(to: .airDrop)
    expectEq(active.enter(hasFiles: false), .ignored, "a drag without files is ignored")
    expect(active.dropping, "an ignored enter leaves the active drag active")
    expectEq(active.zone, .airDrop, "an ignored enter keeps the lit zone")
}

@Test @MainActor func theHighlightEdgeCases() {
    var highlight = IslandDropHighlight()
    _ = highlight.enter(hasFiles: true)
    _ = highlight.move(to: .airDrop)
    _ = highlight.enter(hasFiles: true)
    expectEq(highlight.zone, .airDrop, "a second enter keeps the zone")
    highlight.end()
    expect(!highlight.move(to: .ask), "moving after the end is not answered")
    expectEq(highlight.zone, nil, "moving after the end lights nothing")
    var fresh = IslandDropHighlight()
    expectEq(fresh.drop(), .ask, "a drop with no enter falls back to asking")
}

@Test @MainActor func reduceMotionTurnsTheZoneAnimationOff() {
    let base = Animation.expoOut(MotionTime.fast)
    expect(ChromeMotion.animation(base, reduceMotion: true) == nil, "Reduce Motion: no animation")
    expect(ChromeMotion.animation(base, reduceMotion: false) != nil, "otherwise the zone eases")
}

@Test @MainActor func aFileThatCannotBeReadIsNotCalledAFolder() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString)")
    expectEq(IslandDropTarget.verdict(missing), .unreadable, "a file that vanished could not be read")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dir-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    expectEq(IslandDropTarget.verdict(folder), .notFile, "a folder is not a file")

    let said = Said()
    let (island, _) = actions(MemoryAttachments(), said)
    island.drop([missing], zone: .ask)
    expectEq(said.failures.first?.reason, ChatCopy.attachFailed(.unreadable), "unreadable says it could not be read")
}

@Test @MainActor func theAirDropZoneSaysWhyAFileWasFiltered() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dir-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let missing = folder.appendingPathComponent("gone.txt")

    let said = Said()
    let (island, _) = actions(MemoryAttachments(), said)
    island.drop([folder, missing], zone: .airDrop)
    expect(!said.lines.contains(Localized.string("island.drop.airDropUnavailable")),
           "filtered files are not blamed on AirDrop")
    expectEq(said.failures.map(\.reason), [Localized.string("island.attach.notFile"),
                                           ChatCopy.attachFailed(.unreadable)],
             "each filtered file carries its own reason")

    let sorted = IslandDropTarget.sort([folder, missing])
    expect(sorted.files.isEmpty, "nothing is left to send")
    expectEq(sorted.refused.map(\.url), [folder, missing], "both are refused, in order")
}

@Test @MainActor func attachResultKeepsTheRefusal() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("res-\(UUID().uuidString).txt")
    try Data("hola".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    let bare = ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                             store: MemoryConversationStore(), config: Config(), attachments: nil)
    expectEq(bare.attachResult(file), .failure(.io), "no attachment store is an io failure")

    let (_, ok) = actions(MemoryAttachments(), Said())
    guard case .success(let ref) = ok.attachResult(file) else {
        expect(false, "a readable file attaches")
        return
    }
    expectEq(ok.pendingAttachments.map(\.name), [ref.name], "success lands in the pending list")

    let (_, refusing) = actions(RefusingStore(error: .tooLarge), Said())
    expectEq(refusing.attachResult(file), .failure(.tooLarge), "the refusal is kept")
    expectEq(refusing.notices.queue.visible.last?.text, ChatCopy.attachFailed(.tooLarge), "the error toast still fires")
    expectEq(refusing.notices.queue.visible.last?.level, .error, "and it is an error")

    let failure = IslandAttachFailure(name: "a.txt", reason: "why")
    expectEq(IslandAttachCardItem.failed(failure).failureReason, "why", "a failed card carries its reason")
    expectEq(IslandAttachCardItem.failed(IslandAttachFailure(name: "a")).failureReason, nil, "no reason, none shown")
}

@Test @MainActor func theDropWordsAreInBothLanguages() async {
    let expected: [AppLanguage: [String: String]] = [
        .en: ["island.drop.a11y": "Drop to attach",
              "island.attach.notFile": "That is a folder or a link, not a file I can attach."],
        .es: ["island.drop.a11y": "Suelta para adjuntar",
              "island.attach.notFile": "Eso es una carpeta o un enlace, no un archivo que pueda adjuntar."],
    ]
    for (language, strings) in expected {
        await Localized.scoped(to: language) {
            for (key, value) in strings {
                expectEq(Localized.string(key), value, "\(language): \(key)")
            }
        }
    }
}

@Test func aStoredNameLosesControlAndInvisibleCharacters() {
    let name = AttachmentPolicy.sanitizedFileName("fac\ntu\tra\u{200B}\u{2060}.pdf")
    expectEq(name, "factura.pdf", "newline, tab and zero-width characters do not survive")
    expectEq(AttachmentPolicy.sanitizedFileName("\u{200B}\n"), "file", "a name of only those falls back")
}
