import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The chip shows a name and keeps the path for its actions. Only a local path
// becomes a chip; the tooltip folds the home folder, the text never shows it.

@Test func aLocalPathBecomesAChipNamedByItsLastPart() {
    let chip = FileChip("~/Desktop/Informe final.pdf")
    expectEq(chip?.name, "Informe final.pdf", "el nombre es la última parte, con espacios")
    expectEq(chip?.path, "~/Desktop/Informe final.pdf", "la ruta se guarda para abrir")
    expectEq(FileChip("/Users/k/Notes/")?.name, "Notes", "una carpeta sin barra final")
}

@Test func aURLOrASentenceStaysText() {
    expect(FileChip("https://example.com/a.pdf") == nil, "una URL no es archivo local")
    expect(FileChip("abre el informe") == nil, "una frase no es ruta")
    expect(FileChip("/") == nil, "la raíz no tiene nombre")
}

@Test func theTooltipFoldsHomeAndTheActionExpandsIt() {
    expectEq(FileChip.tooltip("/Users/k/Desktop/a.pdf", home: "/Users/k"), "~/Desktop/a.pdf",
             "el tooltip pliega la carpeta de inicio a ~")
    expectEq(FileChip.tooltip("/tmp/a.pdf", home: "/Users/k"), "/tmp/a.pdf", "fuera de inicio se queda igual")
    expectEq(FileChip.resolved("~/Desktop/a.pdf", workdir: nil, home: "/Users/k"), "/Users/k/Desktop/a.pdf",
             "la acción abre la ruta completa")
}

// The model often names a file by a folder and a name ("Desktop/notas.md"). Read
// as text it made the receipt say the raw path, and the chip never drew.
@Test func aRelativePathBecomesAChipNamedByItsLastPart() {
    let chip = FileChip("Desktop/Swift_vs_TypeScript.md")
    expectEq(chip?.name, "Swift_vs_TypeScript.md", "el chip muestra solo el nombre")
    expectEq(chip?.path, "Desktop/Swift_vs_TypeScript.md", "la ruta se guarda para abrir")
    expectEq(FileChip.resolved("Desktop/a.md", workdir: nil, home: "/Users/k"), "/Users/k/Desktop/a.md",
             "relativa se abre desde la carpeta de inicio, como open_file")
}

// A chip's click is a file the reader may open. Programs and scripts are only
// revealed in Finder, and a protected path has no action at all.
@Test func aLauncherOrScriptIsRevealedNeverOpened() {
    let home = "/Users/k"
    for path in ["\(home)/Desktop/run.sh", "\(home)/Desktop/go.command", "\(home)/Desktop/App.app",
                 "\(home)/Desktop/tool.tool", "\(home)/Desktop/setup.pkg"] {
        expectEq(FileChip.action(for: path, home: home, runnable: { _ in false }), .revealOnly,
                 "\(path): solo se muestra en Finder")
    }
    expectEq(FileChip.action(for: "\(home)/Desktop/notas.txt", home: home, runnable: { _ in true }), .revealOnly,
             "un archivo con bit de ejecución: solo se muestra en Finder")
}

@Test func aProtectedPathHasNoAction() {
    let home = "/Users/k"
    for path in ["\(home)/.ssh/id_rsa", "\(home)/Library/Keychains/login.keychain-db", "/usr/bin/env"] {
        expectEq(FileChip.action(for: path, home: home, runnable: { _ in false }), .none,
                 "\(path): ruta protegida, el chip no hace nada")
    }
}

@Test func anOrdinaryFileOpens() {
    expectEq(FileChip.action(for: "/Users/k/Desktop/x.md", home: "/Users/k", runnable: { _ in false }), .open,
             "un archivo normal se abre")
}

@Test func aChipResolvesLikeTheReadTools() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("chip-\(UUID().uuidString)")
    let home = base.appendingPathComponent("home"), work = home.appendingPathComponent("work")
    try FileManager.default.createDirectory(at: work.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    FileManager.default.createFile(atPath: work.appendingPathComponent("Desktop/x.md").path, contents: Data())
    expectEq(FileChip.resolved("Desktop/x.md", workdir: work.path, home: home.path),
             work.appendingPathComponent("Desktop/x.md").path, "el chip abre lo que leyó el modelo: primero el workdir")
    expectEq(FileChip.resolved("Desktop/otro.md", workdir: work.path, home: home.path),
             home.appendingPathComponent("Desktop/otro.md").path, "sin copia en el workdir, el home")
}
