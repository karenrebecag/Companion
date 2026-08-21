import CompanionCore
import SwiftUI

/// The human in the loop. Denying is a first-class answer, not a dismissal:
/// the specialist is told and looks for another route.
public struct ApprovalSheet: View {
    private let request: ApprovalRequest
    private let answer: (Bool) -> Void

    public init(request: ApprovalRequest, answer: @escaping (Bool) -> Void) {
        self.request = request
        self.answer = answer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text("¿Permitir que el especialista haga esto?")
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.Color.fg)

            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text(request.toolName)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.muted)
                Text(ChatCopy.approvalDetail(
                    tool: request.toolName, inputJSON: request.inputJSON))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Color.fg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Tokens.Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Si no respondes, se deniega solo.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.muted)

            HStack(spacing: Tokens.Space.s12) {
                Button("No permitir") { answer(false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Permitir") { answer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.s24)
        .frame(width: 420)
        .background(Tokens.Color.bg)
    }
}
