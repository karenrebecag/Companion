import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// list_directory's tree is the same walk the model reads: hidden entries stay
// out, names sort, depth bounds the walk, and a cut listing says so.

@Test func theTreeWalksSortedVisibleEntriesWithinDepthAndSaysWhenCut() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("dirtree-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let docs = root.appendingPathComponent("docs", isDirectory: true)
    try FileManager.default.createDirectory(at: docs.appendingPathComponent("deep/deeper", isDirectory: true),
                                            withIntermediateDirectories: true)
    try "x".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appendingPathComponent(".secret"), atomically: true, encoding: .utf8)
    try "x".write(to: docs.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

    let tree = DirectoryTree.build(root.path, title: "root", depth: 2)
    expectEq(tree.nodes.map(\.name), ["b.txt", "docs"], "ocultos fuera y nombres ordenados")
    expect(!tree.nodes[0].isFolder && tree.nodes[1].isFolder, "un archivo no es carpeta; una carpeta sí")
    expectEq(tree.nodes[1].children.map(\.name), ["a.md", "deep"], "la carpeta se recorre dentro del límite")
    expect(tree.nodes[1].children[1].children.isEmpty, "a profundidad 2 no se entra a deep/")
    expect(!tree.truncated, "un listado completo no dice que está cortado")
    expectEq(tree.text, ["b.txt", "docs/", "  a.md", "  deep/"], "el texto del modelo sale del mismo recorrido")
}
