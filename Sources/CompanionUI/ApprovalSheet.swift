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
        VStack(alignment: .leading, spacing: Space.x4) {
            Text("¿Permitir que el especialista haga esto?")
                .font(Font.uiTitle)
                .foregroundStyle(Semantic.foreground)

            VStack(alignment: .leading, spacing: Space.x1) {
                Text(request.toolName)
                    .font(Font.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                Text(ChatCopy.approvalDetail(
                    tool: request.toolName, inputJSON: request.inputJSON))
                    .font(Font.uiBody)
                    .foregroundStyle(Semantic.foreground)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Semantic.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Si no respondes, se deniega solo.")
                .font(Font.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)

            HStack(spacing: Space.x3) {
                AppButton("No permitir", kind: .secondary) { answer(false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                AppButton("Permitir", kind: .primary) { answer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.x6)
        .frame(width: 420)
        .background(Semantic.background)
    }
}
