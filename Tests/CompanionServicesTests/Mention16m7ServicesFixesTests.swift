import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 16m-7, review round: what a mention may copy, the recents cache under
// cancellation, the capture folder, and the address-book guards.

// MARK: - AttachmentStore adopts regular files only

@Test @MainActor func attachmentAdoptRegularFilesOnlyTests() {
    withTempDir { dir in
        let store = AttachmentStore(root: dir.appendingPathComponent("store"))
        let fm = FileManager.default
        func adopt(_ url: URL) -> AttachmentError? {
            do {
                _ = try store.adopt(url, conversationId: "c1")
                return nil
            } catch let error as AttachmentError {
                return error
            } catch {
                return .io
            }
        }
        let file = dir.appendingPathComponent("ok.txt")
        expect((try? Data("hola".utf8).write(to: file)) != nil, "setup")
        expect(adopt(file) == nil, "16m-7 review: un archivo normal se adopta")

        let plain = dir.appendingPathComponent("Carpeta", isDirectory: true)
        let package = dir.appendingPathComponent("Foo.app", isDirectory: true)
        let library = dir.appendingPathComponent("Fotos.photoslibrary", isDirectory: true)
        for directory in [plain, package, library] {
            expect((try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil, "setup dir")
            expect((try? Data(repeating: 7, count: 4096).write(to: directory.appendingPathComponent("inside.bin"))) != nil, "setup inside")
            expectEq(adopt(directory), .unreadable, "16m-7 review: un directorio o paquete no se copia: \(directory.lastPathComponent)")
        }

        let sshLike = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        let toSecrets = dir.appendingPathComponent("innocente.txt")
        expect((try? fm.createSymbolicLink(at: toSecrets, withDestinationURL: sshLike)) != nil, "setup symlink")
        expectEq(adopt(toSecrets), .unreadable, "16m-7 review: un symlink hacia ~/.ssh no se sigue ni se copia")
        let toFile = dir.appendingPathComponent("enlace.txt")
        expect((try? fm.createSymbolicLink(at: toFile, withDestinationURL: file)) != nil, "setup symlink 2")
        expectEq(adopt(toFile), .unreadable, "16m-7 review: ni siquiera uno hacia un archivo inocente: la ruta ya no dice lo que hay detrás")
        let toDir = dir.appendingPathComponent("enlace-dir")
        expect((try? fm.createSymbolicLink(at: toDir, withDestinationURL: plain)) != nil, "setup symlink 3")
        expectEq(adopt(toDir), .unreadable, "16m-7 review: ni hacia una carpeta")
    }
}

// MARK: - Spotlight predicate

@Test @MainActor func recentFilesPredicateExcludesPackagesTests() {
    let format = RecentFiles.predicate(since: Date()).predicateFormat
    expect(format.contains("com.apple.package"), "16m-7 review: Spotlight tampoco devuelve paquetes: \(format)")
    expect(format.contains("public.folder"), "16m-7 review: ni carpetas")
}

// MARK: - RecentFiles cache

private final class RunCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
}

private let home = NSHomeDirectory()

@Test func recentFilesSharesOneQueryTests() async {
    let runs = RunCounter()
    let recents = RecentFiles(runner: { _, _ in
        runs.bump()
        try? await Task.sleep(for: .milliseconds(150))
        return [home + "/Documents/a.txt"]
    })
    async let one = recents.candidates()
    async let two = recents.candidates()
    async let three = recents.candidates()
    let all = await [one, two, three]
    expectEq(runs.value, 1, "16m-7 review: tres preguntas a la vez comparten una sola consulta")
    expectEq(all.map(\.count), [1, 1, 1], "16m-7 review: y las tres ven el resultado")
    _ = await recents.candidates()
    expectEq(runs.value, 1, "16m-7 review: y el siguiente sale de la caché")
}

@Test func recentFilesSurvivesCancellationTests() async {
    let runs = RunCounter()
    let recents = RecentFiles(runner: { _, _ in
        runs.bump()
        try? await Task.sleep(for: .milliseconds(150))
        return [home + "/Documents/a.txt"]
    })
    let first = Task { await recents.candidates() }
    try? await Task.sleep(for: .milliseconds(20))
    first.cancel()
    _ = await first.value
    let second = await recents.candidates()
    expectEq(second.count, 1, "16m-7 review: cancelar a quien preguntó no envenena la caché con un resultado vacío")
    expectEq(runs.value, 1, "16m-7 review: la consulta en vuelo sigue viva y se reutiliza")
    expectEq(await recents.candidates().count, 1, "16m-7 review: y queda en caché")
}

@Test func recentFilesDoesNotCacheFailuresTests() async {
    let runs = RunCounter()
    let recents = RecentFiles(runner: { _, _ in
        runs.bump()
        return runs.value == 1 ? nil : [home + "/Documents/a.txt"]
    })
    expectEq(await recents.candidates().count, 0, "16m-7 review: una consulta fallida da lista vacía")
    expectEq(await recents.candidates().count, 1, "16m-7 review: y no se cacheó: la siguiente vuelve a intentar")
    expectEq(runs.value, 2, "16m-7 review: dos consultas")
}

// MARK: - Capture folder

@Test @MainActor func captureFolderIsPurgedAtLaunchTests() {
    withTempDir { dir in
        let fm = FileManager.default
        let folder = dir.appendingPathComponent("companion-captures", isDirectory: true)
        expect((try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil, "setup")
        let leftovers = ["a.png", "b.png"].map { folder.appendingPathComponent($0) }
        for url in leftovers { expect((try? Data([1, 2, 3]).write(to: url)) != nil, "setup file") }
        let outside = dir.appendingPathComponent("not-mine.png")
        expect((try? Data([9]).write(to: outside)) != nil, "setup outside")

        let grabber = ScreenRegionGrabber(directory: folder)
        grabber.purgeLeftovers()
        expect(leftovers.allSatisfy { !fm.fileExists(atPath: $0.path) }, "16m-7 review: las capturas viejas se borran al arrancar")
        expect(fm.fileExists(atPath: outside.path), "16m-7 review: solo dentro de su carpeta")
        ScreenRegionGrabber(directory: dir.appendingPathComponent("never-created")).purgeLeftovers()
        expect(true, "16m-7 review: una carpeta que no existe no es un error")

        // A folder that is really a link elsewhere is never emptied.
        let target = dir.appendingPathComponent("target", isDirectory: true)
        let precious = target.appendingPathComponent("precious.txt")
        expect((try? fm.createDirectory(at: target, withIntermediateDirectories: true)) != nil, "setup target")
        expect((try? Data([5]).write(to: precious)) != nil, "setup precious")
        let link = dir.appendingPathComponent("linked", isDirectory: true)
        expect((try? fm.createSymbolicLink(at: link, withDestinationURL: target)) != nil, "setup link")
        ScreenRegionGrabber(directory: link).purgeLeftovers()
        expect(fm.fileExists(atPath: precious.path), "16m-7 review: si la carpeta es un enlace, no se toca lo que hay detrás")
    }
}
