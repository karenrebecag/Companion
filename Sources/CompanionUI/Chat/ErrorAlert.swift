import SwiftUI

/// A recoverable error above Home's tasks: what went wrong in one sentence,
/// an icon that says it is a problem, and an exit. The sentence is announced
/// once, when it appears, so a screen reader hears the failure too.
struct ErrorAlert: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.uiBody)
                .foregroundStyle(Semantic.destructive)
                .accessibilityHidden(true)
            Text(text)
                .typeRole(.body)
                .foregroundStyle(Semantic.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            CloseButton(label: Localized.string("island.notice.dismiss"), action: onDismiss)
        }
        .padding(Space.x3)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.destructiveMuted))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Semantic.destructive, lineWidth: Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(ChatErrorSurface.announcement(text)).post() }
    }
}
