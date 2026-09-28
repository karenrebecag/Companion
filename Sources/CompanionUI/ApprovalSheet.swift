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

    private var display: ApprovalDisplay {
        ApprovalCopy.display(for: request, language: Localized.language())
    }

    public var body: some View {
        let display = self.display
        VStack(alignment: .leading, spacing: Space.x4) {
            HStack(alignment: .center, spacing: Space.x3) {
                Image(systemName: display.symbol)
                    .font(GeistFont.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                    .frame(width: Space.x10, height: Space.x10)
                    .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.surface))
                    // 19-1: the raw tool id left the body but stays one
                    // hover away — human-first is hierarchy, not hiding.
                    .help(request.toolName)
                    .accessibilityHidden(true)
                title(display)
                    .font(GeistFont.uiTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(display.title)
            }

            if let preview = display.preview {
                // The scroll bounds what the ellipsis used to hide: the
                // datum is complete (the tail is part of what runs — 15g
                // M1) and the answer buttons can never be pushed off
                // screen by a long one (security review 19-1). A short
                // preview keeps its natural height; only overflow scrolls.
                ViewThatFits(in: .vertical) {
                    previewText(preview)
                    ScrollView(.vertical) { previewText(preview) }
                }
                .frame(maxHeight: Container.hero)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Semantic.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
            }

            // §9-5: `bridge_session` has no `ApprovalKey` (security review
            // 2026-09-28) — a "remember" toggle here would promise a memory
            // that never happens, one sheet per connection, always.
            if display.showsRemember {
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
        .frame(width: Container.approval)
        .background(Semantic.background)
    }

    private func previewText(_ preview: String) -> some View {
        Text(preview)
            .font(GeistFont.uiBody)
            .foregroundStyle(Semantic.foreground)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The subject carries the visual weight; the words around it recede.
    private func title(_ display: ApprovalDisplay) -> Text {
        var parts = Text("")
        if let lead = display.lead {
            parts = parts + Text(lead + " ").foregroundStyle(Semantic.mutedForeground)
        }
        parts = parts + Text(display.subject)
            .fontWeight(.semibold).foregroundStyle(Semantic.foreground)
        if let trail = display.trail {
            parts = parts + Text(" " + trail).foregroundStyle(Semantic.mutedForeground)
        }
        return parts
    }
}

extension ApprovalSheet {
    /// Allowing is a click, never a stray Return: a key typed for something
    /// else must not approve (security review 16). Deny keeps Escape.
    static let allowShortcut: KeyboardShortcut? = nil
}
