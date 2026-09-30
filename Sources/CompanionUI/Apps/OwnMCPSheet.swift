import CompanionCore
import SwiftUI

/// 16k-4 "Añádelo aquí" (spec 16k §2.6): the user's own remote MCP
/// servers, on top of what 9j-3 already runs. The page edits the same
/// mcp.json the user could edit by hand; the next realtime session picks
/// the list up on open, which the note below says out loud (16m: the UI
/// never promises more than what runs).
struct OwnMCPSheet: View {
    var apps: AppsModel
    let onClose: () -> Void

    @State private var name = ""
    @State private var url = ""
    /// The label mid-confirmation, or nil. Removing is destructive and the
    /// row is the confirmation surface, like the panel's Disconnect.
    @State private var confirmingRemove: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            Text(Localized.string("apps.own.title"))
                .font(Fonts.sans(TypeSize.dialogTitle).weight(.semibold))
                .tracking(Tracking.title, at: TypeSize.dialogTitle)
                .foregroundStyle(Semantic.foreground)
            Text(Localized.string("apps.own.note"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if apps.ownServers.isEmpty {
                Text(Localized.string("apps.own.none"))
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
            } else {
                VStack(spacing: Space.none) {
                    ForEach(apps.ownServers, id: \.label) { server in
                        row(server)
                        if server.label != apps.ownServers.last?.label {
                            Rectangle().fill(Semantic.border).frame(height: Stroke.hairline)
                        }
                    }
                }
                .background(Semantic.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
            }
            form
        }
        .padding(Space.x6)
        .frame(width: AppsMetrics.formWidth)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Semantic.background))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .stroke(Semantic.border, lineWidth: Stroke.hairline))
        .overlay(alignment: .topTrailing) { closeButton.padding(Space.x4) }
    }

    private func row(_ server: MCPServerConfig) -> some View {
        HStack(spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(server.label)
                    .font(.uiLabel.weight(.semibold))
                    .foregroundStyle(Semantic.foreground)
                Text(OwnMCPEdit.host(of: server))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .lineLimit(1)
            }
            Spacer()
            if confirmingRemove == server.label {
                AppButton(Localized.string("apps.own.confirmRemove"), kind: .destructive) {
                    apps.removeOwn(label: server.label)
                    confirmingRemove = nil
                }
                AppButton(Localized.string("apps.panel.disconnect.cancel"), kind: .ghost) {
                    confirmingRemove = nil
                }
            } else {
                AppButton(Localized.string("apps.own.remove"), kind: .ghost) {
                    confirmingRemove = server.label
                }
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            AppField(placeholder: Localized.string("apps.own.name"), text: $name,
                     onSubmit: submit)
            AppField(placeholder: Localized.string("apps.own.url"), text: $url,
                     error: errorText, onSubmit: submit)
            HStack {
                Spacer()
                AppButton(Localized.string("apps.own.submit"), enabled: canSubmit,
                          action: submit)
            }
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        if apps.addOwn(label: name, url: url) {
            name = ""
            url = ""
        }
    }

    private var errorText: String? {
        // A broken file outranks everything: the edits are blocked until
        // the user fixes mcp.json by hand (H1, review 16k-4).
        if apps.ownFileBroken { return Localized.string("apps.own.error.broken") }
        if apps.ownSaveFailed { return Localized.string("apps.own.error.save") }
        switch apps.ownError {
        case .emptyName: return Localized.string("apps.own.error.name")
        case .invalidName: return Localized.string("apps.own.error.nameCharset")
        case .duplicateName: return Localized.string("apps.own.error.duplicate")
        case .invalidURL: return Localized.string("apps.own.error.url")
        case nil: return nil
        }
    }

    private var closeButton: some View {
        CloseButton(action: onClose)
    }
}
