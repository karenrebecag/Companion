import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D4 follow-up: whatever the model puts under "workbook" never
// reaches a sheet, and an approval whose bound JSON cannot be read is a denial.

private struct NoAppSheets: SpreadsheetDriving {
    func active() async -> SheetApp? { nil }
    func workbook(_ app: SheetApp) async throws -> String { throw SheetError.unsavedDocument }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        SheetWriteReceipt(readBack: [])
    }
}

private let spoofed = #"{"range":"A1","values":"[[1]]","workbook":"/falso.xlsx"}"#

@Test func theNativeRunnerDropsAModelWorkbookItCannotResolve() async {
    let runner = NativeToolRunner(workdir: FileManager.default.temporaryDirectory.path, places: nil,
                                  documents: nil, sheets: NoAppSheets())
    let shown = await runner.approvalArguments(tool: "sheet_write", json: spoofed)
    expect(ToolArguments.parse(shown)?["workbook"] == nil, "nativo: sin app resuelta, el libro del modelo no queda")
    expectEq(ToolArguments.parse(shown)?["range"] as? String, "A1", "nativo: el resto queda")
}

@Test func theParentRunnerDropsAModelWorkbookWhenNoAppIsNamed() async {
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []),
                                  workdir: nil, documents: nil, sheets: NoAppSheets())
    let request = ApprovalRequest(requestId: "r", toolName: "sheet_write", summary: "", inputJSON: spoofed)
    let bound = await runner.bound(request)
    expect(ToolArguments.parse(bound.inputJSON)?["workbook"] == nil, "parent: sin app, el libro del modelo no queda")
}

@Test func anApprovalWithUnreadableBoundArgumentsIsADenial() {
    let original = #"{"a":1}"#
    expect(NativeExecutor.boundArguments(shown: "not json", original: original, parsed: ["a": 1]) == nil,
           "ejecutor: JSON ligado ilegible no corre con args vacíos")
    expectEq(NativeExecutor.boundArguments(shown: original, original: original, parsed: ["a": 1])?["a"] as? Int, 1,
             "ejecutor: sin cambios, los argumentos del modelo")
    expectEq(NativeExecutor.boundArguments(shown: #"{"a":2}"#, original: original, parsed: ["a": 1])?["a"] as? Int, 2,
             "ejecutor: cambiados, los ligados")
}
