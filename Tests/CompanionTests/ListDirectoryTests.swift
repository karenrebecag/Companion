import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func listDirectoryTests() {
    testListsEntriesAndMarksFolders()
    testFindsTheFolderThatFuzzySearchWouldMiss()
    testDepthShowsWhatIsInside()
    testRefusesOutsideTheWorkdir()
    testAFileIsNotADirectory()
    testMissingPathSaysSo()
    testTruncationIsAnnouncedNotSilent()
    testItIsSafeSoItNeverAsksForApproval()
}

@MainActor private func sandbox(_ name: String) -> String {
    let base = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("companion-ls-\(name)")
    try? FileManager.default.removeItem(atPath: base)
    try! FileManager.default.createDirectory(
        atPath: base, withIntermediateDirectories: true)
    return base
}

@MainActor private func run(
    _ runner: NativeToolRunner, path: String, depth: Int? = nil
) -> ToolResult {
    do {
        return try runAsync {
            var args: [String: Any] = ["path": path]
            if let depth { args["depth"] = depth }
            return try await runner.execute(
                tool: "list_directory", arguments: args, approved: false)
        }
    } catch {
        expect(false, "list_directory no debia tirar: \(error)")
        return ToolResult(ok: false, output: "")
    }
}

@MainActor func testListsEntriesAndMarksFolders() {
    let dir = sandbox("basico")
    try! FileManager.default.createDirectory(
        atPath: (dir as NSString).appendingPathComponent("unaCarpeta"),
        withIntermediateDirectories: true)
    FileManager.default.createFile(
        atPath: (dir as NSString).appendingPathComponent("archivo.txt"),
        contents: Data("hola".utf8))

    let result = run(NativeToolRunner(workdir: dir), path: dir)
    expect(result.ok, "lista sin pedir permiso")
    expect(result.output.contains("unaCarpeta/"),
           "las carpetas se distinguen de los archivos: \(result.output)")
    expect(result.output.contains("archivo.txt"), "y los archivos salen")
}

@MainActor func testFindsTheFolderThatFuzzySearchWouldMiss() {
    // El caso real que motivo la herramienta: el usuario pidio "Software
    // Development Projects" y la carpeta se llama "SoftwareDevProjects". Ni
    // substring ni glob la encuentran — el modelo si, en cuanto puede VER la
    // lista. Por eso la respuesta era dar ojos, no mejor busqueda.
    let dir = sandbox("fuzzy")
    try! FileManager.default.createDirectory(
        atPath: (dir as NSString).appendingPathComponent("SoftwareDevProjects"),
        withIntermediateDirectories: true)

    let result = run(NativeToolRunner(workdir: dir), path: dir)
    expect(result.output.contains("SoftwareDevProjects"),
           "el nombre real esta en la lista para que el modelo lo reconozca")
}

@MainActor func testDepthShowsWhatIsInside() {
    let dir = sandbox("hondo")
    let inner = (dir as NSString).appendingPathComponent("proyecto")
    try! FileManager.default.createDirectory(
        atPath: inner, withIntermediateDirectories: true)
    FileManager.default.createFile(
        atPath: (inner as NSString).appendingPathComponent("dentro.md"),
        contents: Data())

    let shallow = run(NativeToolRunner(workdir: dir), path: dir)
    expect(!shallow.output.contains("dentro.md"), "por defecto, un solo nivel")

    let deep = run(NativeToolRunner(workdir: dir), path: dir, depth: 2)
    expect(deep.output.contains("dentro.md"),
           "con depth 2 se ve el contenido: \(deep.output)")
}

@MainActor func testRefusesOutsideTheWorkdir() {
    let dir = sandbox("barrera")
    let result = run(NativeToolRunner(workdir: dir), path: "/etc")
    expect(!result.ok, "la barrera de rutas vale igual para listar")
}

@MainActor func testAFileIsNotADirectory() {
    let dir = sandbox("archivo")
    let file = (dir as NSString).appendingPathComponent("solo.txt")
    FileManager.default.createFile(atPath: file, contents: Data())
    let result = run(NativeToolRunner(workdir: dir), path: file)
    expect(!result.ok, "listar un archivo es un error, no una lista vacia")
}

@MainActor func testMissingPathSaysSo() {
    let dir = sandbox("ausente")
    let result = run(
        NativeToolRunner(workdir: dir),
        path: (dir as NSString).appendingPathComponent("no-existe"))
    expect(!result.ok, "una ruta que no existe se dice, no se calla")
}

@MainActor func testTruncationIsAnnouncedNotSilent() {
    // Un tope silencioso se lee como "eso es todo lo que hay", que es una
    // mentira del tamano de la carpeta.
    let dir = sandbox("muchos")
    for i in 0 ..< 260 {
        FileManager.default.createFile(
            atPath: (dir as NSString).appendingPathComponent("f\(i).txt"),
            contents: Data())
    }
    let result = run(NativeToolRunner(workdir: dir), path: dir)
    expect(result.output.contains("260"),
           "dice cuantas habia en total: \(result.output.suffix(120))")
}

@MainActor func testItIsSafeSoItNeverAsksForApproval() {
    // El punto entero de la herramienta: mirar no puede costar un clic, o
    // explorar una carpeta cuesta un clic por nivel.
    expectEq(NativeTool.listDirectory.riskLevel, .safe,
             "mirar es seguro; escribir es lo que pide permiso")
}
