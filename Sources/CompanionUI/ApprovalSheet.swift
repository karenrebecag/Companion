import CompanionCore
import SwiftUI

/// The human in the loop. Denying is a first-class answer, not a dismissal:
/// the specialist is told and looks for another route. "Remember for this
/// session" (Wave 10c 3B.3) keeps the answer for the same tool and pattern
/// until the app closes — five files, one question.
public struct ApprovalSheet: View {
    private let request: ApprovalRequest
    private let answer: (Bool, Bool) -> Void
    @State private var remember = false

    public init(request: ApprovalRequest, answer: @escaping (Bool, Bool) -> Void) {
        self.request = request
        self.answer = answer
    }

    private var plan: Plan { Self.plan(for: request, language: Localized.language()) }

    public var body: some View {
        let plan = self.plan
        VStack(alignment: .leading, spacing: Space.x4) {
            Text(plan.title)
                .font(GeistFont.uiTitle)
                .foregroundStyle(Semantic.foreground)

            VStack(alignment: .leading, spacing: Space.x1) {
                Text(request.toolName)
                    .font(GeistFont.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                Text(plan.detail)
                    .font(GeistFont.uiBody)
                    .foregroundStyle(Semantic.foreground)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Semantic.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // §9-5: `bridge_session` has no `ApprovalKey` (security review
            // 2026-09-28) — a "remember" toggle here would promise a memory
            // that never happens, one sheet per connection, always.
            if plan.showsRemember {
                Toggle(isOn: $remember) {
                    Text(Localized.string("approval.remember"))
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
                .toggleStyle(.checkbox)
            }

            Text(Localized.string("approval.autodeny"))
                .font(GeistFont.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)

            HStack(spacing: Space.x3) {
                AppButton(Localized.string("approval.deny"), kind: .secondary) { answer(false, remember) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                AppButton(Localized.string("approval.allow"), kind: .primary) { answer(true, remember) }
                    .keyboardShortcut(Self.allowShortcut)
            }
        }
        .padding(Space.x6)
        .frame(width: 420)
        .background(Semantic.background)
    }
}

extension ApprovalSheet {
    /// Allowing is a click, never a stray Return: a key typed for something
    /// else must not approve (security review 16). Deny keeps Escape.
    static let allowShortcut: KeyboardShortcut? = nil

    /// What the sheet says and offers, decided once so a test can check it
    /// without rendering SwiftUI. Wave 17: `bridge_session` (no `ParentTool`
    /// behind it, no `ApprovalKey`) reads its own title/detail from
    /// `BridgeCopy` and never offers "remember".
    struct Plan: Equatable {
        let title: String
        let detail: String
        let showsRemember: Bool
    }

    static func plan(for request: ApprovalRequest, language: AppLanguage) -> Plan {
        guard request.toolName == "bridge_session" else {
            return Plan(
                title: Localized.string(
                    ParentTool(rawValue: request.toolName) != nil
                        ? "approval.title.parent" : "approval.title"),
                detail: ChatCopy.approvalDetail(tool: request.toolName, inputJSON: request.inputJSON),
                showsRemember: true)
        }
        return Plan(
            title: request.summary,
            detail: BridgeCopy.sheetDetail(language),
            showsRemember: false)
    }
}
