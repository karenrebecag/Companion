import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func conversationStoreTests() {
    testCapDefault()
    testRoundtripISO8601()
    testAttachmentsAbsentStillDecode()
    testListCapsAtThirty()
    testLoadMissingReturnsNil()
    testLoadCorruptThrows()
    testEmptyMessagesNotWritten()
    testExtraJSONKeysDecode()
    testReportRolePreserved()
    testListSkipsUnreadableAndSorts()
    testSavePrunesOldest()
    testSaveCreatesDirectory()
    testSaveOverwritesSameId()
    testWriteFailureThrowsIO()
    testRejectsTraversingId()
}

@MainActor func testCapDefault() {
    expectEq(ConversationStore.cap, 30, "cap: default 30")
}

@MainActor func testRoundtripISO8601() {
    withTempDir { dir in
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let record = ConversationRecord(
            id: "c1",
            title: "Notas de ñoño",
            updatedAt: stamp,
            messages: [
                ConversationMessage(
                    role: "user",
                    text: "hola café — '; DROP",
                    attachmentPaths: ["/tmp/a png.png", "/tmp/ñoño.txt"]),
                ConversationMessage(role: "assistant", text: "listo"),
            ])
        let store = ConversationStore(directory: dir)
        do {
            try store.save(record)
            let raw = try String(
                contentsOf: dir.appendingPathComponent("c1.json"),
                encoding: .utf8)
            expect(raw.contains("2023-11-14T22:13:20Z"),
                   "iso8601: fecha en RFC 3339 con Z")
            expect(!raw.contains("2023-11-14T22:13:20."),
                   "iso8601: sin fracciones de segundo")
            expectEq(try store.load("c1"), record,
                     "roundtrip: el record vuelve igual")
        } catch {
            expect(false, "roundtrip: no debía tirar \(error)")
        }
    }
}

@MainActor func testAttachmentsAbsentStillDecode() {
    withTempDir { dir in
        writeJSON(dir, id: "old", """
            {"id":"old","title":"Vieja","updatedAt":"2023-11-14T22:13:20Z",\
            "messages":[{"role":"user","text":"hola"}]}
            """)
        let store = ConversationStore(directory: dir)
        do {
            let loaded = try store.load("old")
            expectEq(loaded?.messages.count, 1,
                     "ausente: un mensaje")
            expectEq(loaded?.messages.first?.attachmentPaths, [],
                     "ausente: attachments faltante decodifica a []")
            expectEq(loaded?.messages.first?.text, "hola",
                     "ausente: el texto sigue ahí")
        } catch {
            expect(false, "ausente: no debía tirar \(error)")
        }
    }
}

@MainActor func testListCapsAtThirty() {
    withTempDir { dir in
        let store = ConversationStore(directory: dir)
        do {
            for i in 0..<31 {
                try store.save(ConversationRecord(
                    id: "c\(i)",
                    title: "t\(i)",
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                    messages: [ConversationMessage(role: "user", text: "m\(i)")]))
            }
            let listed = try store.list()
            expectEq(listed.count, 30, "cap: save 31 → list 30")
            expectEq(listed.first?.id, "c30", "cap: el más nuevo encabeza")
            expectEq(listed.last?.id, "c1", "cap: el más viejo listado es c1")
            expect(!listed.contains { $0.id == "c0" },
                   "cap: c0 no aparece en list")
        } catch {
            expect(false, "cap: no debía tirar \(error)")
        }
    }
}

@MainActor func testLoadMissingReturnsNil() {
    withTempDir { dir in
        let store = ConversationStore(directory: dir)
        do {
            expect(try store.load("nope") == nil, "missing: nil")
            expect(try store.list().isEmpty, "missing: list vacío")
        } catch {
            expect(false, "missing: no debía tirar \(error)")
        }
    }
    let ghost = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-ghost-\(UUID().uuidString)")
    let store = ConversationStore(directory: ghost)
    do {
        expect(try store.load("x") == nil, "missing: dir inexistente → nil")
        expect(try store.list().isEmpty, "missing: dir inexistente → list []")
    } catch {
        expect(false, "missing: dir inexistente no debía tirar \(error)")
    }
}

@MainActor func testLoadCorruptThrows() {
    withTempDir { dir in
        let store = ConversationStore(directory: dir)
        writeJSON(dir, id: "bad", "{not json")
        expectPersistence({ _ = try store.load("bad") }, .decoding,
                          "corrupt: JSON roto → decoding")

        writeJSON(dir, id: "arr", "[]")
        expectPersistence({ _ = try store.load("arr") }, .decoding,
                          "corrupt: array → decoding")

        writeJSON(dir, id: "empty", "{}")
        expectPersistence({ _ = try store.load("empty") }, .decoding,
                          "corrupt: objeto vacío → decoding")

        writeJSON(dir, id: "date", """
            {"id":"date","title":"t","updatedAt":"no-es-fecha",\
            "messages":[{"role":"user","text":"x"}]}
            """)
        expectPersistence({ _ = try store.load("date") }, .decoding,
                          "corrupt: fecha inválida → decoding")
    }
}

@MainActor func testEmptyMessagesNotWritten() {
    withTempDir { dir in
        let store = ConversationStore(directory: dir)
        let blank = ConversationRecord(
            id: "empty", title: "Nada",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            messages: [])
        do {
            try store.save(blank)
            let url = dir.appendingPathComponent("empty.json")
            expect(!FileManager.default.fileExists(atPath: url.path),
                   "vacío: no escribe el archivo")
            expect(try store.list().isEmpty, "vacío: list no lo ve")
            expect(try store.load("empty") == nil, "vacío: load es nil")
        } catch {
            expect(false, "vacío: no debía tirar \(error)")
        }
    }
}

@MainActor func testExtraJSONKeysDecode() {
    withTempDir { dir in
        writeJSON(dir, id: "extra", """
            {"id":"extra","title":"T","updatedAt":"2023-11-14T22:13:20Z",\
            "orphan":true,"messages":[{"role":"user","text":"hola",\
            "attachments":["/tmp/a"],"executor":"claude","goal":"x",\
            "unknown":1}]}
            """)
        let store = ConversationStore(directory: dir)
        do {
            let loaded = try store.load("extra")
            expectEq(loaded?.id, "extra", "extra: id")
            expectEq(loaded?.title, "T", "extra: title")
            expectEq(loaded?.messages.count, 1, "extra: un mensaje")
            expectEq(loaded?.messages.first?.role, "user", "extra: role")
            expectEq(loaded?.messages.first?.attachmentPaths, ["/tmp/a"],
                     "extra: attachments conocidos se conservan")
        } catch {
            expect(false, "extra: keys de más no debían tirar \(error)")
        }
    }
}

@MainActor func testReportRolePreserved() {
    withTempDir { dir in
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let record = ConversationRecord(
            id: "rep", title: "Informe", updatedAt: stamp,
            messages: [ConversationMessage(role: "report", text: "hecho")])
        let store = ConversationStore(directory: dir)
        do {
            try store.save(record)
            expectEq(try store.load("rep")?.messages.first?.role, "report",
                     "report: el store no reescribe el role")
        } catch {
            expect(false, "report: no debía tirar \(error)")
        }
    }
}

@MainActor func testListSkipsUnreadableAndSorts() {
    withTempDir { dir in
        writeJSON(dir, id: "good", """
            {"id":"good","title":"Ok","updatedAt":"2023-11-14T22:13:20Z",\
            "messages":[{"role":"user","text":"hola"}]}
            """)
        writeJSON(dir, id: "newer", """
            {"id":"newer","title":"Nueva","updatedAt":"2023-11-15T22:13:20Z",\
            "messages":[{"role":"user","text":"después"}]}
            """)
        writeJSON(dir, id: "bad", "{nope")
        try? "nota".write(
            to: dir.appendingPathComponent("readme.txt"),
            atomically: true, encoding: .utf8)
        let store = ConversationStore(directory: dir)
        do {
            let listed = try store.list()
            expectEq(listed.map(\.id), ["newer", "good"],
                     "list: salta ilegibles, orden desc por updatedAt")
            expectEq(listed.first?.title, "Nueva", "list: title del record")
        } catch {
            expect(false, "list: no debía tirar \(error)")
        }
    }
}

@MainActor func testSavePrunesOldest() {
    withTempDir { dir in
        let store = ConversationStore(directory: dir, cap: 2)
        do {
            for i in 0..<3 {
                try store.save(ConversationRecord(
                    id: "p\(i)", title: "t",
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                    messages: [ConversationMessage(role: "user", text: "x")]))
            }
            expectEq(try store.list().map(\.id), ["p2", "p1"],
                     "prune: list respeta cap inyectado")
            expect(
                !FileManager.default.fileExists(
                    atPath: dir.appendingPathComponent("p0.json").path),
                "prune: borra el json que ya no entra")
            expect(
                FileManager.default.fileExists(
                    atPath: dir.appendingPathComponent("p2.json").path),
                "prune: conserva el más nuevo")
        } catch {
            expect(false, "prune: no debía tirar \(error)")
        }
    }
}

@MainActor func testSaveCreatesDirectory() {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-parent-\(UUID().uuidString)")
    let dir = parent.appendingPathComponent("conversations")
    defer { try? FileManager.default.removeItem(at: parent) }
    let store = ConversationStore(directory: dir)
    let record = ConversationRecord(
        id: "c1", title: "Hola",
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        messages: [ConversationMessage(role: "user", text: "hey")])
    do {
        try store.save(record)
        expect(
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("c1.json").path),
            "save: crea el directorio inyectado")
        expectEq(try store.load("c1"), record, "save: load tras crear dir")
    } catch {
        expect(false, "save: crear dir no debía tirar \(error)")
    }
}

@MainActor func testSaveOverwritesSameId() {
    withTempDir { dir in
        let store = ConversationStore(directory: dir)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        do {
            try store.save(ConversationRecord(
                id: "c1", title: "Uno", updatedAt: t0,
                messages: [ConversationMessage(role: "user", text: "a")]))
            try store.save(ConversationRecord(
                id: "c1", title: "Dos", updatedAt: t1,
                messages: [ConversationMessage(role: "user", text: "b")]))
            let listed = try store.list()
            expectEq(listed.count, 1, "overwrite: un solo meta")
            expectEq(listed.first?.title, "Dos", "overwrite: title nuevo")
            expectEq(try store.load("c1")?.messages.first?.text, "b",
                     "overwrite: mensaje nuevo")
        } catch {
            expect(false, "overwrite: no debía tirar \(error)")
        }
    }
}

@MainActor func testWriteFailureThrowsIO() {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-io-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: parent) }
    do {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    } catch {
        expect(false, "io: no pude crear el padre")
        return
    }
    let blocked = parent.appendingPathComponent("blocked")
    do {
        try Data("x".utf8).write(to: blocked)
    } catch {
        expect(false, "io: no pude crear el archivo-trampa")
        return
    }
    let store = ConversationStore(directory: blocked)
    let record = ConversationRecord(
        id: "c1", title: "X",
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        messages: [ConversationMessage(role: "user", text: "hey")])
    expectPersistence({ try store.save(record) }, .io,
                      "io: directorio que es un archivo → io")
    do {
        try store.save(ConversationRecord(
            id: "empty", title: "",
            updatedAt: Date(timeIntervalSince1970: 0),
            messages: []))
        expect(true, "vacío: no-op no tira aunque el dir sea un archivo")
    } catch {
        expect(false, "vacío: no-op no debía tirar \(error)")
    }
}

@MainActor func testRejectsTraversingId() {
    withTempDir { dir in
        let store = ConversationStore(directory: dir)
        let record = ConversationRecord(
            id: "../pwned", title: "x",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            messages: [ConversationMessage(role: "user", text: "hi")])
        expectPersistence({ try store.save(record) }, .io,
                          "id: ../ no escribe fuera del directorio")
        let escaped = dir.deletingLastPathComponent()
            .appendingPathComponent("pwned.json")
        expect(!FileManager.default.fileExists(atPath: escaped.path),
               "id: no crea el archivo escapado")
        expectPersistence({ _ = try store.load("../pwned") }, .io,
                          "id: load ../ no lee el padre")
        expectPersistence({ _ = try store.load("foo/bar") }, .io,
                          "id: slash anidado se rechaza")
    }
}

@MainActor func withTempDir(_ body: (URL) -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-conv-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        expect(false, "temp: no se pudo crear \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: dir) }
    body(dir)
}

@MainActor func writeJSON(_ dir: URL, id: String, _ raw: String) {
    do {
        try Data(raw.utf8).write(to: dir.appendingPathComponent("\(id).json"))
    } catch {
        expect(false, "fixture: no pude escribir \(id).json — \(error)")
    }
}

@MainActor func expectPersistence(
    _ body: () throws -> Void,
    _ want: PersistenceError,
    _ label: String
) {
    do {
        try body()
        expect(false, "\(label) — no tiró")
    } catch let error as PersistenceError {
        expectEq(error, want, label)
    } catch {
        expect(false, "\(label) — tiró \(error), no PersistenceError")
    }
}
