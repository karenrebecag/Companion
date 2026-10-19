import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Live 2026-10-16: claims without a tool, apps never discovered, a looped
// list_apps and a turn that ended with no text.

@Test func thePromptDemandsAToolBeforeAClaimAndOneQuestionWhenAmbiguous() {
    let es = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false, language: .es)
    expect(es.contains("sin haber llamado en este mismo turno a la tool"), "es: comprobar antes de afirmar")
    expect(es.contains("UNA pregunta corta"), "es: una pregunta ante lo ambiguo")
    let en = ChatPrompt.system(ownerFirstName: "", delegateEnabled: false, language: .en)
    expect(en.contains("unless you called the tool that checks it"), "en: comprobar antes de afirmar")
    expect(en.contains("ONE short question"), "en: una pregunta ante lo ambiguo")
}

@Test func connectedAppNamesReachThePromptThroughTheDiscoveryTool() async {
    let runner = AppToolRunner(service: { PromptApps() }, catalog: [], suggest: nil)
    await runner.refresh()
    runner.noteTurn("mandale el reporte a Juan")
    let slugs = runner.specs(.es).flatMap(\.appSlugs)
    expectEq(slugs, ["slack_v2"], "el descubrimiento lleva los nombres de las apps conectadas")
    let prompt = ChatPrompt.system(
        ownerFirstName: "", delegateEnabled: false, language: .es, connectedApps: slugs)
    expect(prompt.contains("Apps conectadas: slack_v2"), "el prompt nombra las apps")
    expect(prompt.contains("find_app_tools"), "el prompt manda descubrir antes de negar acceso")
    expect(!ChatPrompt.system(ownerFirstName: "", delegateEnabled: false).contains("Connected apps"),
           "sin apps no se promete nada")
}

@Test func thePromptNamesOnlyFileToolsTheParentDeclares() {
    let prompt = ChatPrompt.system(ownerFirstName: "", delegateEnabled: true, parentToolsEnabled: true)
    expect(prompt.contains("list_directory and read_file"), "nombra las lecturas declaradas")
    expect(!prompt.contains("run_shell for"), "no promete run_shell al padre")
}

@Test func theParentOffersFileReadsWithOrWithoutAWorkdir() async throws {
    let workspace = FakeWorkspaceOpener(installed: [], running: [])
    let bare = ParentToolRunner(workspace: workspace)
    expect(bare.specs(.en).map(\.name).contains("list_directory"), "todo el disco: se ofrece aun sin carpeta")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: dir.appendingPathComponent("uno"), withIntermediateDirectories: true)
    let granted = ParentToolRunner(workspace: workspace, workdir: dir.path)
    expect(granted.specs(.en).map(\.name).contains("list_directory"), "con carpeta se ofrece")
    let out = await granted.execute(name: "list_directory", argumentsJSON: "{\"path\":\"\(dir.path)\"}")
    expect(out.ok && out.output.contains("uno"), "lista la carpeta concedida")
}

@Test func theThirdIdenticalCallInATurnIsCut() {
    var guardrail = ToolRepeatGuard()
    expect(guardrail.check(name: "list_apps", arguments: "{}") == nil, "primera pasa")
    expect(guardrail.check(name: "list_apps", arguments: "{}") == nil, "segunda pasa")
    let cut = guardrail.check(name: "list_apps", arguments: "{}")
    expect(cut?.contains("already have this result") == true, "tercera se corta con el motivo")
    expect(guardrail.check(name: "list_directory", arguments: "{\"path\":\"~\"}") == nil,
           "otra tool o argumentos distintos siguen libres")
}

@Test func aTurnWithoutTextSaysWhatItTried() {
    let attempts = ["Listé las apps.", "Listé las apps.", "Navegador: Menú o lista no encontrada."]
    let es = ParentToolCopy.noAnswer(attempts: attempts, .es)
    expect(es.contains("listé las apps; navegador: Menú o lista no encontrada"), "dice qué probó, en palabras, sin repetir")
    expect(!es.contains("list_apps") && !es.contains("browser_"), "sin nombres de tools crudos")
    let en = ParentToolCopy.noAnswer(attempts: ["Listed the browser tabs."], .en)
    expect(en.contains("listed the browser tabs") && !en.contains("list_apps"), "en: mismo criterio")
    expect(!ParentToolCopy.noAnswer(attempts: [], .en).isEmpty, "nunca vacío")
}

@Test func aClearPortugueseReplyIsNotLabelledSpanish() {
    let text = "As três cores primárias são vermelho, azul e amarelo. Goodbye!"
    expectEq(NaturalLanguageRecognizer(constrainToAppLanguages: false).dominant(text)?.code, "pt",
             "la inspección ve el portugués como portugués")
}

// QA 606: a Spanish reply full of English product terms was tagged "id"
// (Indonesian) by the unconstrained recognizer. The tag is a label, so the
// candidates must be the languages the people reading it actually use.
@Test func aSpanishReplyWithEnglishTermsIsNotTaggedIndonesian() {
    let text = "Revisa el deploy en Vercel antes del release: el build del commit pasó y el dashboard de analytics ya tiene los datos del sprint."
    let label = NaturalLanguageRecognizer(constrainToAppLanguages: false).dominant(text)?.code
    expectEq(label, "es", "qa606: el español con términos en inglés no es indonesio")
}

private final class PromptApps: AppsService, @unchecked Sendable {
    func catalog(query: String, after: String?) async throws -> CatalogPage {
        CatalogPage(apps: [], total: 0, next: nil)
    }
    func accounts() async throws -> [ConnectedAccount] {
        [ConnectedAccount(id: "apn_1", app: "slack_v2", name: nil, state: .connected)]
    }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] {
        [AppAction(slug: "slack_v2-list-channels", name: "List", description: "List", group: .leer)]
    }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        AppCallResult(isError: false, text: "")
    }
}
