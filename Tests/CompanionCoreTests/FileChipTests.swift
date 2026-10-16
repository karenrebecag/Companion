import CompanionCore
import CompanionTestKit
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
    expectEq(FileChip.expanded("~/Desktop/a.pdf", home: "/Users/k"), "/Users/k/Desktop/a.pdf",
             "la acción abre la ruta completa")
}

// The model often names a file by a folder and a name ("Desktop/notas.md"). Read
// as text it made the receipt say the raw path, and the chip never drew.
@Test func aRelativePathBecomesAChipNamedByItsLastPart() {
    let chip = FileChip("Desktop/Swift_vs_TypeScript.md")
    expectEq(chip?.name, "Swift_vs_TypeScript.md", "el chip muestra solo el nombre")
    expectEq(chip?.path, "Desktop/Swift_vs_TypeScript.md", "la ruta se guarda para abrir")
    expectEq(FileChip.expanded("Desktop/a.md", home: "/Users/k"), "/Users/k/Desktop/a.md",
             "relativa se abre desde la carpeta de inicio, como open_file")
}

@Test func aReceiptNamesAFileByItsNameNeverItsPath() {
    let outcome = ParentToolOutcome(ok: true, output: "", target: "Desktop/Swift_vs_TypeScript.md")
    let entry = ReceiptProof.entry(tool: "open_file", outcome: outcome, language: .es)
    expectEq(entry?.text, "Abrí Swift_vs_TypeScript.md.", "el recibo dice el nombre, no la ruta")
    expectEq(entry?.file?.name, "Swift_vs_TypeScript.md", "y el chip lleva el mismo nombre")
}
