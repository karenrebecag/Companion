import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func attachmentTests() {
    testDeliveryByKindAndExtension()
    testMimeTypes()
    testScaledSizeOnlyShrinks()
    testInlineClip()
    testTurnNumberingStillHolds()
    testAdoptTooLarge()
    testAdoptZeroBytes()
    testAdoptCopyAndDiscard()
    testAdoptImageData()
    testRestoreAndUnsafePaths()
    testInlineAndPathPayloads()
    testUnsafeConversationId()
}

@MainActor func testDeliveryByKindAndExtension() {
    let png = AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)
    let swift = AttachmentRef(name: "a.swift", path: "/tmp/a.swift", kind: .file)
    let pdf = AttachmentRef(name: "a.pdf", path: "/tmp/a.pdf", kind: .file)
    expectEq(AttachmentPolicy.delivery(for: png), .imageDataURL,
             "policy: png viaja como image_url")
    expectEq(AttachmentPolicy.delivery(for: swift), .inlineText,
             "policy: fuente viaja inline")
    expectEq(AttachmentPolicy.delivery(for: pdf), .pathOnly,
             "policy: binario solo aporta la ruta")
}

@MainActor func testMimeTypes() {
    expectEq(AttachmentPolicy.mime(forExtension: "png"), "image/png",
             "mime: png")
    expectEq(AttachmentPolicy.mime(forExtension: "JPG"), "image/jpeg",
             "mime: jpg case-insensitive")
    expectEq(AttachmentPolicy.mime(forExtension: "swift"), "text/plain",
             "mime: texto legible")
}

@MainActor func testScaledSizeOnlyShrinks() {
    let fit = AttachmentPolicy.scaledSize(width: 800, height: 600)
    expectEq(fit.width, 800, "scale: bajo el tope no cambia")
    expectEq(fit.height, 600, "scale: alto intacto")
    let big = AttachmentPolicy.scaledSize(width: 4096, height: 2048)
    expectEq(big.width, 1024, "scale: el lado largo cae a 1024")
    expectEq(big.height, 512, "scale: el corto guarda la razon")
}

@MainActor func testInlineClip() {
    let short = AttachmentPolicy.clipInline("hola")
    expectEq(short, "hola", "clip: corto no se toca")
    let raw = String(repeating: "a", count: AttachmentPolicy.maxInlineChars + 10)
    let clipped = AttachmentPolicy.clipInline(raw)
    expect(clipped.hasPrefix(String(repeating: "a", count: AttachmentPolicy.maxInlineChars)),
           "clip: conserva el prefijo")
    expect(clipped.contains("recortado"), "clip: avisa el recorte")
}

@MainActor func testTurnNumberingStillHolds() {
    let img = AttachmentRef(
        name: "foto.png", path: "/tmp/foto.png", kind: .image, byteCount: 12)
    let doc = AttachmentRef(
        name: "notas.txt", path: "/tmp/notas.txt", kind: .file, byteCount: 4)
    let out = Turn.numbered("¿cuál te gusta?", [img, doc])
    expect(out.hasPrefix("[Imagen 1] [Archivo 2: notas.txt]"),
           "numerado: el AttachmentRef ampliado no rompe las etiquetas")
}

@MainActor func testAdoptTooLarge() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir, maxBytes: 32)
        let source = dir.appendingPathComponent("big.bin")
        do {
            try Data(repeating: 1, count: 64).write(to: source)
            _ = try store.adopt(source, conversationId: "c1")
            expect(false, "adopt: sobre el tope debe lanzar")
        } catch let error as AttachmentError {
            expectEq(error, .tooLarge, "adopt: tooLarge")
        } catch {
            expect(false, "adopt: error inesperado \(error)")
        }
    }
}

@MainActor func testAdoptZeroBytes() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir)
        let source = dir.appendingPathComponent("empty.txt")
        do {
            try Data().write(to: source)
            _ = try store.adopt(source, conversationId: "c1")
            expect(false, "adopt: vacio debe lanzar")
        } catch let error as AttachmentError {
            expectEq(error, .unreadable, "adopt: unreadable")
        } catch {
            expect(false, "adopt: error inesperado \(error)")
        }
    }
}

@MainActor func testAdoptCopyAndDiscard() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir)
        let source = dir.appendingPathComponent("nota.swift")
        do {
            try Data("let x = 1\n".utf8).write(to: source)
            let ref = try store.adopt(source, conversationId: "conv-1")
            expectEq(ref.kind, .file, "adopt: .swift es archivo")
            expectEq(ref.byteCount, 10, "adopt: peso original")
            expect(ref.path.contains("conv-1"), "adopt: vive bajo el id")
            expect(FileManager.default.fileExists(atPath: ref.path),
                   "adopt: copio el archivo")
            expect(source.path != ref.path, "adopt: no es la ruta original")
            store.discard(ref)
            expect(!FileManager.default.fileExists(atPath: ref.path),
                   "discard: borra la copia")
        } catch {
            expect(false, "adopt: \(error)")
        }
    }
}

@MainActor func testAdoptImageData() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir)
        do {
            let ref = try store.adopt(
                imageData: tinyPNG, name: "pegado.png", conversationId: "c1")
            expectEq(ref.kind, .image, "imageData: kind imagen")
            expectEq(ref.name, "pegado.png", "imageData: conserva el nombre")
            expect(ref.byteCount > 0, "imageData: peso")
            if case .imageDataURL(let url)? = store.payload(for: ref) {
                expect(url.hasPrefix("data:image/png;base64,"),
                       "payload: data URL de png pequeno")
            } else {
                expect(false, "payload: png pequeno es imageDataURL")
            }
        } catch {
            expect(false, "imageData: \(error)")
        }
    }
}

@MainActor func testRestoreAndUnsafePaths() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir)
        do {
            try Data("hola\n".utf8).write(
                to: dir.appendingPathComponent("hola.txt"))
            let ref = try store.adopt(
                dir.appendingPathComponent("hola.txt"), conversationId: "c1")
            let restored = store.restore(path: ref.path)
            expectEq(restored?.name, "hola.txt", "restore: nombre original")
            expectEq(restored?.kind, .file, "restore: kind")
            expect(store.restore(path: "/tmp/fuera.txt") == nil,
                   "restore: fuera del root es nil")
            expect(store.restore(path: "/no/existe") == nil,
                   "restore: ausente es nil")
        } catch {
            expect(false, "restore: \(error)")
        }
    }
}

@MainActor func testInlineAndPathPayloads() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir)
        do {
            try Data("print(1)\n".utf8).write(
                to: dir.appendingPathComponent("a.swift"))
            try Data([0x25, 0x50, 0x44, 0x46]).write(
                to: dir.appendingPathComponent("a.pdf"))
            let text = try store.adopt(
                dir.appendingPathComponent("a.swift"), conversationId: "c1")
            let bin = try store.adopt(
                dir.appendingPathComponent("a.pdf"), conversationId: "c1")
            if case .text(let body)? = store.payload(for: text) {
                expectEq(body, "print(1)\n", "payload: texto inline")
            } else {
                expect(false, "payload: swift es texto")
            }
            if case .path(let path)? = store.payload(for: bin) {
                expectEq(path, bin.path, "payload: pdf es la ruta")
            } else {
                expect(false, "payload: pdf es pathOnly")
            }
        } catch {
            expect(false, "payload: \(error)")
        }
    }
}

@MainActor func testUnsafeConversationId() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir)
        let source = dir.appendingPathComponent("a.txt")
        do {
            try Data("x".utf8).write(to: source)
            _ = try store.adopt(source, conversationId: "../escape")
            expect(false, "adopt: id con traversal debe lanzar")
        } catch let error as AttachmentError {
            expectEq(error, .io, "adopt: id inseguro es io")
        } catch {
            expect(false, "adopt: \(error)")
        }
    }
}

/// 1x1 PNG. Enough for ImageIO without shipping an asset.
private let tinyPNG = Data([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
    0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB4, 0x00, 0x00, 0x00,
    0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
])
