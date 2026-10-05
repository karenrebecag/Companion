import CompanionCore
import SwiftUI

enum ResetPermissionsMetrics {
    /// Incredible's dialog width; no token carries it.
    static let dialogMaxWidth: CGFloat = 480
}

/// ON-18. One Settings row: what it does, and a danger button that opens its
/// own confirmation. No padding, background or card here; the section that
/// hosts the row supplies them. The port arrives through init, like every
/// other Settings model.
package struct ResetPermissionsRow: View {
    @State private var model: ResetPermissionsModel
    @State private var confirming = false

    package init(port: any PermissionResetting) {
        _model = State(initialValue: ResetPermissionsModel(port: port))
    }

    package var body: some View {
        HStack(alignment: .center, spacing: Space.x4) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(Localized.string("settings.resetPermissions.title"))
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("settings.resetPermissions.body"))
                    .typeRole(.micro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.x3)
            AppButton(Localized.string("settings.resetPermissions.button"),
                      kind: .destructive, size: .sm) {
                // An old error must not greet the next opening.
                model.dismissError()
                confirming = true
            }
        }
        .sheet(isPresented: $confirming) {
            ResetPermissionsDialog(model: model) { confirming = false }
                .interactiveDismissDisabled(model.isRunning)
        }
    }
}

/// Lists what goes and what stays, then asks for the word. Nothing closes
/// while the reset runs: a half-finished reset must not be left unattended.
private struct ResetPermissionsDialog: View {
    let model: ResetPermissionsModel
    let close: () -> Void

    @State private var typed = ""
    @FocusState private var typing: Bool

    private var language: AppLanguage { Localized.language() }
    private var word: String { ResetDialogState.promptWord(language: language) }
    private var closeEnabled: Bool { ResetDialogState.closeEnabled(phase: model.phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            HStack(alignment: .top) {
                Text(Localized.string("settings.resetPermissions.dialog.title"))
                    .font(GeistFont.uiSubtitle)
                    .foregroundStyle(Semantic.foreground)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.x3)
                CloseButton { close() }
                    .disabled(!closeEnabled)
            }
            paragraph(ResetDialogState.resetsText(language: language), Semantic.foreground)
            paragraph(Localized.string("settings.resetPermissions.dialog.keeps"), Semantic.mutedForeground)
            VStack(alignment: .leading, spacing: Space.x2) {
                Text(String(format: Localized.string("settings.resetPermissions.dialog.prompt"), word))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                TextField(word, text: $typed)
                    .textFieldStyle(.plain)
                    .font(.uiLabel)
                    .focused($typing)
                    .disabled(!closeEnabled)
                    .padding(Space.x2)
                    .background(RoundedRectangle(cornerRadius: Radius.chip).fill(Semantic.muted))
                    .onSubmit(confirm)
            }
            status
            HStack(spacing: Space.x3) {
                AppButton(Localized.string("settings.resetPermissions.dialog.cancel"),
                          kind: .secondary, enabled: closeEnabled) { close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                AppButton(Localized.string("settings.resetPermissions.dialog.confirm"),
                          kind: .destructive,
                          enabled: model.canConfirm(input: typed, language: language),
                          action: confirm)
            }
        }
        .padding(Space.x6)
        .frame(width: ResetPermissionsMetrics.dialogMaxWidth)
        .background(Semantic.surfaceOverlay)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { typing = true }
    }

    private func paragraph(_ text: String, _ ink: Color) -> some View {
        Text(text)
            .typeRole(.body)
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var status: some View {
        if model.isRunning {
            HStack(spacing: Space.x2) {
                ProgressView().controlSize(.small)
                Text(Localized.string("settings.resetPermissions.dialog.running"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        } else if let failure = model.failure {
            Text(ResetDialogState.errorText(for: failure, language: language))
                .typeRole(.micro)
                .foregroundStyle(Semantic.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func confirm() {
        guard model.canConfirm(input: typed, language: language) else { return }
        Task { await model.confirm(input: typed, language: language) }
    }
}
