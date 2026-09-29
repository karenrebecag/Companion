import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// 16k-4 "Añádelo aquí": la edicion de la lista es pura (Core) y la
// escritura del archivo queda en Services. Lo que se fija aqui: nombre y
// URL validados antes de tocar la lista, nada se muta, y el archivo
// guardado vuelve a cargar identico con permisos de solo dueño.

@Test func ownMCPEditTests() {
    let existing = [MCPServerConfig(label: "docs", url: "https://mcp.example.dev/mcp")]

    // Add: appends without mutating the input, defaults to asking.
    switch OwnMCPEdit.add(existing, label: " notas ", url: "https://notes.dev/mcp") {
    case .success(let servers):
        expectEq(servers.count, 2, "add: agrega al final")
        expectEq(servers.last?.label, "notas", "add: recorta espacios del nombre")
        expectEq(existing.count, 1, "add: no muta la lista original")
    case .failure(let error):
        Issue.record("add valido fallo: \(error)")
    }

    // Validation: each rejection names its field.
    expectEq(OwnMCPEdit.add(existing, label: "  ", url: "https://x.dev").failureOrNil,
             .emptyName, "add: nombre vacio se rechaza")
    expectEq(OwnMCPEdit.add(existing, label: "DOCS", url: "https://x.dev").failureOrNil,
             .duplicateName, "add: nombre duplicado se rechaza sin distinguir mayusculas")
    expectEq(OwnMCPEdit.add(existing, label: "x", url: "http://x.dev").failureOrNil,
             .invalidURL, "add: http plano se rechaza — el servidor viaja con token")
    expectEq(OwnMCPEdit.add(existing, label: "x", url: "no es url").failureOrNil,
             .invalidURL, "add: texto que no parsea se rechaza")
    expectEq(OwnMCPEdit.add(existing, label: "x", url: "https://").failureOrNil,
             .invalidURL, "add: https sin host se rechaza")
    // Security review 16k-4 M3/M4: the label reaches OpenAI's server_label
    // and the model instructions; credentials in the URL would travel in
    // clear and never show in the UI.
    expectEq(OwnMCPEdit.add(existing, label: "mis notas", url: "https://x.dev").failureOrNil,
             .invalidName, "add: espacios y acentos en el nombre se rechazan")
    expectEq(OwnMCPEdit.add(existing, label: String(repeating: "a", count: 65),
                            url: "https://x.dev").failureOrNil,
             .invalidName, "add: nombre de mas de 64 se rechaza")
    expectEq(OwnMCPEdit.add(existing, label: "x", url: "https://user:pw@x.dev").failureOrNil,
             .invalidURL, "add: credenciales incrustadas en la URL se rechazan")
    switch OwnMCPEdit.add(existing, label: "x", url: "  https://x.dev/mcp\n") {
    case .success(let servers):
        expectEq(servers.last?.url, "https://x.dev/mcp",
                 "add: recorta tambien saltos de linea y guarda la URL normalizada")
    case .failure(let error):
        Issue.record("URL con salto de linea deberia pasar tras el recorte: \(error)")
    }

    // Remove: by label, immutable, unknown label is a no-op.
    let removed = OwnMCPEdit.remove(existing, label: "docs")
    expect(removed.isEmpty, "remove: quita por nombre")
    expectEq(existing.count, 1, "remove: no muta la lista original")
    expectEq(OwnMCPEdit.remove(existing, label: "nadie").count, 1,
             "remove: nombre desconocido no borra nada")

    // Host for display: the URL's host, or the raw string when unparseable.
    expectEq(OwnMCPEdit.host(of: existing[0]), "mcp.example.dev", "host: extrae el host")
}

@Test func mcpConfigFileSaveTests() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("own-mcp-\(UUID().uuidString)")
    let secrets = TestHostSecretStore()
    defer { try? FileManager.default.removeItem(at: root) }

    let servers = [
        MCPServerConfig(label: "docs", url: "https://mcp.example.dev/mcp"),
        MCPServerConfig(label: "notas", url: "https://notes.dev/mcp",
                        authorization: "tok"),
    ]
    try MCPConfigFile.save(servers, root: root, secrets: secrets)

    expectEq(MCPConfigFile.load(root: root, secrets: secrets), servers, "save: lo guardado recarga identico")

    // An old file's "never" still loads but is never written back: nothing
    // reads it any more (20c D2), so persisting it would only mislead.
    try Data(#"[{"label":"a","url":"https://a.dev","requireApproval":"never"}]"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).count, 1, "save: un archivo viejo con never carga")
    try MCPConfigFile.save(MCPConfigFile.load(root: root, secrets: secrets), root: root, secrets: secrets)
    let rewritten = try String(contentsOf: root.appendingPathComponent("mcp.json"), encoding: .utf8)
    expect(!rewritten.contains("requireApproval"), "save: requireApproval no se reescribe")
    try MCPConfigFile.save(servers, root: root, secrets: secrets)

    // The file may carry a bearer token: owner-only, like the bridge socket.
    let path = root.appendingPathComponent("mcp.json").path
    let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    expectEq(perms, 0o600, "save: mcp.json queda 0600")

    // Saving over an existing file replaces it whole.
    try MCPConfigFile.save([servers[0]], root: root, secrets: secrets)
    expectEq(MCPConfigFile.load(root: root, secrets: secrets).count, 1, "save: reemplaza, no anexa")

    // read distingue los tres estados: sin archivo, con servidores, roto.
    switch MCPConfigFile.read(root: root) {
    case .servers(let loaded): expectEq(loaded.count, 1, "read: archivo bueno da servidores")
    default: Issue.record("read de archivo bueno no dio .servers")
    }
    let empty = FileManager.default.temporaryDirectory
        .appendingPathComponent("own-mcp-\(UUID().uuidString)")
    expectEq(MCPConfigFile.read(root: empty), MCPFileRead.absent, "read: sin archivo es absent")
    // Foundation's decoder forgives a trailing comma these days, so the
    // fixture is truncated mid-object — unambiguously broken.
    try Data(#"[{"label":"a","url":"https://a.dev","authorization":"#.utf8)
        .write(to: root.appendingPathComponent("mcp.json"))
    expectEq(MCPConfigFile.read(root: root), MCPFileRead.unreadable,
             "read: JSON roto es unreadable, nunca lista vacia (H1 review 16k-4)")
}

// The model wires the pure edit to the injected file seam: a rejected add
// never touches the file, a failed save never updates the list the page
// shows, every edit re-reads the disk first (an out-of-band hand edit
// survives, review 16k-4 M1), and a broken file blocks editing instead of
// being wiped by the next save (H1).
@Test @MainActor func appsModelOwnMCPTests() {
    final class Disk: @unchecked Sendable {
        var contents: MCPFileRead = .servers(
            [MCPServerConfig(label: "docs", url: "https://mcp.example.dev")])
        var saved: [[MCPServerConfig]] = []
        var failNext = false
    }
    let disk = Disk()
    let model = AppsModel(
        secrets: TestSecretStore(), hostSecrets: TestHostSecretStore(),
        defaults: UserDefaults(suiteName: "own-\(UUID().uuidString)")!,
        makeService: { _, _ in fatalError("unused") },
        readMCP: { disk.contents },
        saveMCP: { servers in
            if disk.failNext { throw CocoaError(.fileWriteNoPermission) }
            disk.saved.append(servers)
            disk.contents = .servers(servers)
        })

    model.loadOwn()
    expectEq(model.ownServers.map { $0.label }, ["docs"], "own: carga del seam inyectado")

    expect(!model.addOwn(label: "docs", url: "https://x.dev"), "own: duplicado se rechaza")
    expectEq(model.ownError, OwnMCPEdit.EditError.duplicateName, "own: el error queda para la UI")
    expect(disk.saved.isEmpty, "own: un add rechazado no toca el archivo")

    // A server hand-added while the sheet is open survives the next add.
    disk.contents = .servers([
        MCPServerConfig(label: "docs", url: "https://mcp.example.dev"),
        MCPServerConfig(label: "amano", url: "https://hand.dev", authorization: "tok"),
    ])
    expect(model.addOwn(label: "notas", url: "https://notes.dev/mcp"), "own: add valido")
    expect(model.ownError == nil, "own: el error se limpia al lograr un add")
    expectEq(disk.saved.last?.map { $0.label }, ["docs", "amano", "notas"],
             "own: el add edita la lista fresca del disco, no la cache")
    expectEq(model.ownServers.count, 3, "own: la lista visible se actualiza")

    disk.failNext = true
    expect(!model.addOwn(label: "otro", url: "https://o.dev"), "own: save fallido reporta")
    expect(model.ownSaveFailed, "own: la falla de disco queda para la UI")
    expectEq(model.ownServers.count, 3, "own: la lista visible no promete lo no guardado")

    disk.failNext = true
    let before = model.ownServers
    model.removeOwn(label: "notas")
    expectEq(model.ownServers, before, "own: remove con save fallido no cambia la lista")

    disk.failNext = false
    expect(!model.addOwn(label: "mal nombre", url: "https://x.dev"), "own: charset invalido")
    expect(!model.ownSaveFailed,
           "own: un error de validacion nuevo limpia la falla vieja de disco (no la enmascara)")

    model.removeOwn(label: "notas")
    expectEq(model.ownServers.map { $0.label }, ["docs", "amano"], "own: remove quita y persiste")
    expect(model.ownError == nil, "own: remove limpia el error anterior")

    // H1: a broken file blocks every edit instead of being overwritten.
    disk.contents = .unreadable
    disk.saved = []
    expect(!model.addOwn(label: "x", url: "https://x.dev"), "own: archivo roto bloquea add")
    expect(model.ownFileBroken, "own: el archivo roto se reporta a la UI")
    model.removeOwn(label: "docs")
    expect(disk.saved.isEmpty, "own: archivo roto jamas se sobreescribe")
}

private extension Result where Success == [MCPServerConfig], Failure == OwnMCPEdit.EditError {
    var failureOrNil: OwnMCPEdit.EditError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
