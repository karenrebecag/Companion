import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D4 (H4): the specialist lane names the workbook on the sheet too,
// and what it writes is bound to that same workbook.

private final class ExecSheets: SpreadsheetDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _written: [String] = []
    var written: [String] { lock.withLock { _written } }
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { "/tmp/real.xlsx" }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [["1"]] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        lock.withLock { _written.append(workbook) }
        return SheetWriteReceipt(backupPath: "/tmp/b.xlsx", readBack: [["1"]])
    }
}

private actor CapturingApprovals: ApprovalsProvider {
    private(set) var requests: [ApprovalRequest] = []
    let answer: Bool
    init(answer: Bool) { self.answer = answer }
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        requests.append(approval)
        return ApprovalResponse(requestId: approval.requestId, approved: answer)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { true }
    func remembered(_ approval: ApprovalRequest) async -> Bool? { nil }
}

@Test @MainActor func specialistSheetWriteTests() async {
    let dir = FileManager.default.temporaryDirectory.path
    let args = #"{"app":"excel","range":"A1","values":"[[1]]","workbook":"/falso.xlsx"}"#
    for answer in [false, true] {
        let sheets = ExecSheets()
        let approvals = CapturingApprovals(answer: answer)
        let executor = NativeExecutor(
            descriptor: ExecutorCatalog.native,
            chatProvider: ToolCallTestProvider(toolName: "sheet_write", arguments: args),
            config: Config(workdir: dir), approvals: approvals, sheets: sheets)
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let drain = Task { for await _ in stream {} }
        do {
            _ = try await executor.run(JobRequest(id: "j", goal: "g", context: ""), events: sink)
        } catch {
            expect(false, "especialista: no debe lanzar (\(error))")
        }
        sink.finish()
        await drain.value
        let shown = await approvals.requests.first.flatMap { ToolArguments.parse($0.inputJSON) }
        expectEq(shown?["workbook"] as? String, "/tmp/real.xlsx", "especialista: la hoja nombra el libro del runner")
        if answer {
            expect(!sheets.written.isEmpty && sheets.written.allSatisfy { $0 == "/tmp/real.xlsx" },
                   "especialista: escribe en el libro que la hoja mostró")
        } else {
            expect(sheets.written.isEmpty, "especialista: negada, no escribe")
        }
    }
}
