import CompanionCore
import SwiftUI

/// The human in the loop. Denying is a first-class answer, not a dismissal:
/// the specialist is told and looks for another route. "Remember for this
/// session" (Wave 10c 3B.3) keeps the answer for the same tool and pattern
/// until the app closes — five files, one question.
/// 19-1b: compact on Karen's live feedback — one title line, the auto-deny
/// as a counting ring instead of a sentence, glyphs on the answers.
package struct ApprovalSheet: View {
    private let request: ApprovalRequest
    private let answer: (Bool, Bool) -> Void
    @State private var remember = false
    /// When the sheet appeared: the ring counts from here against the same
    /// deadline the `Approvals` actor denies on (`ApprovalTiming`).
    @State private var shownAt = Date()

    package init(request: ApprovalRequest, answer: @escaping (Bool, Bool) -> Void) {
        self.request = request
        self.answer = answer
    }

    private var display: ApprovalDisplay {
        ApprovalCopy.display(for: request, language: Localized.language())
    }

    package var body: some View {
        let display = self.display
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .center, spacing: Space.x3) {
                mark(display.mark)
                    .frame(width: Space.x8, height: Space.x8)
                    .background(RoundedRectangle(cornerRadius: Radius.chip).fill(Semantic.surface))
                    // 19-1: the raw tool id left the body but stays one
                    // hover away — human-first is hierarchy, not hiding.
                    .help(request.toolName)
                    .accessibilityHidden(true)
                title(display)
                    .font(GeistFont.uiSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(display.title)
                autoDenyRing
            }

            if let preview = display.preview {
                // The scroll bounds what the ellipsis used to hide: the
                // datum is complete (the tail is part of what runs — 15g
                // M1) and the answer buttons can never be pushed off
                // screen by a long one (security review 19-1). Deciding by
                // length keeps a short preview hugging its text —
                // ViewThatFits picked the greedy scroll and drew a tall
                // empty box (seen live 19-1c).
                Group {
                    if Self.previewScrolls(preview) {
                        ScrollView(.vertical) { previewText(preview) }
                            .frame(maxHeight: Container.hero)
                    } else {
                        previewText(preview)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Semantic.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
            }

            // §9-5: `bridge_session` has no `ApprovalKey` (security review
            // 2026-09-28) — a "remember" toggle here would promise a
            // memory that never happens, one sheet per connection, always.
            // Its own row above the CTAs (19-1c): squeezed between the
            // buttons it truncated them.
            if display.showsRemember {
                Toggle(isOn: $remember) {
                    Text(Localized.string("approval.remember"))
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
                .toggleStyle(.checkbox)
            }

            HStack(spacing: Space.x3) {
                AppButton(Localized.string("approval.deny"), kind: .secondary,
                          systemImage: "xmark") { answer(false, remember) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                AppButton(Localized.string("approval.allow"), kind: .primary,
                          systemImage: "checkmark") { answer(true, remember) }
                    .keyboardShortcut(Self.allowShortcut)
            }
        }
        .padding(Space.x4)
        .frame(width: Container.approval)
        .background(Semantic.background)
    }

    /// The deadline made visible: the ring empties over the same seconds
    /// the actor counts, so "if you don't answer" needs no sentence. The
    /// sentence survives for accessibility.
    private var autoDenyRing: some View {
        TimelineView(.animation(minimumInterval: 1)) { context in
            let left = IslandNotice.remaining(
                elapsed: context.date.timeIntervalSince(shownAt),
                lifetime: ApprovalTiming.autoDeny)
            ZStack {
                Circle().stroke(Semantic.surface, lineWidth: Stroke.thin)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(Semantic.mutedForeground,
                            style: StrokeStyle(lineWidth: Stroke.thin, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: Space.x5, height: Space.x5)
        .accessibilityLabel(Localized.string("approval.autodeny"))
    }

    /// The tile's face: the Claude logo for a claude client (rendered from
    /// the bundled vector as a template, so it takes the foreground color),
    /// an SF Symbol for everything else.
    @ViewBuilder
    private func mark(_ mark: ApprovalDisplay.Mark) -> some View {
        switch mark {
        case .claude:
            if let logo = ClaudeLogo.image {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Space.x4, height: Space.x4)
                    .foregroundStyle(Semantic.foreground)
            } else {
                symbolMark("hand.raised")
            }
        case .symbol(let name):
            symbolMark(name)
        }
    }

    private func symbolMark(_ name: String) -> some View {
        Image(systemName: name)
            .font(GeistFont.uiLabel)
            .foregroundStyle(Semantic.foreground)
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

    /// Characters after which the preview trades hugging for a scroll.
    static let scrollThreshold = 400
    /// Newlines make a preview tall long before it is long: a few-hundred
    /// character script can still push the answer buttons off screen, and
    /// bounding those buttons is the 19-1 guarantee (review 19-1c).
    static let scrollLineThreshold = 8

    static func previewScrolls(_ preview: String) -> Bool {
        preview.count > scrollThreshold
            || preview.lazy.filter { $0 == "\n" }.count >= scrollLineThreshold
    }
}

/// The bundled Claude vector, loaded once. It ships as an SVG next to the
/// mascot; NSImage reads it natively and the template mode keeps only its
/// alpha, so the sheet tints it like any glyph.
enum ClaudeLogo {
    static let image: NSImage? = load(from: UIResourceBundle.bundle)

    /// Nil bundle (not found, 21c): no image, and the tile shows no mark.
    static func load(from bundle: Bundle?) -> NSImage? {
        guard let url = bundle?.url(
            forResource: "claude", withExtension: "svg", subdirectory: "Mascot"),
            let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}
