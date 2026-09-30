import CompanionCore
import SwiftUI

/// Where `ChatViewModel.errorText` becomes visible (16p-1). The island and
/// Home each ask this before painting, so the two never disagree.
enum ChatErrorSurface {
    /// The sentence to paint, or nil. The welcome paints its own copy of the
    /// error inside the welcome, and a dismissed sentence stays away until a
    /// different one arrives.
    static func visible(errorText: String?, needsOnboarding: Bool, dismissed: String?) -> String? {
        guard let text = errorText, !text.isEmpty, !needsOnboarding, text != dismissed else { return nil }
        return text
    }
}

extension ChatErrorSurface {
    static func announcement(_ text: String) -> String { text }
}

@MainActor
extension ChatViewModel {
    /// The island's own exit for what it shows; Home keeps its copy.
    public func dismissIslandError() {
        dismissedIslandError = errorText
    }

    /// A failure notice from the session already told the user what went
    /// wrong: the chat error it outranked is treated as reported, so it is
    /// not painted a second time when the notice leaves. Any other notice (a
    /// hint, "didn't hear you", an approval) says something else, and the
    /// error still waits its turn behind it.
    func supersedeIslandError(notice: SessionCard?) {
        guard errorText != nil else { return }
        switch notice {
        case .failure, .permission: dismissedIslandError = errorText
        default: break
        }
    }

    /// The card leaves on its own like the session notices. Runs only while
    /// the card is on screen, so the clock starts when it is seen.
    func expireIslandError(_ text: String) async {
        do {
            try await Task.sleep(for: .seconds(SessionMachine.noticeDelay))
        } catch {
            return
        }
        if errorText == text { dismissedIslandError = text }
    }

    func dismissIslandNotice(_ line: IslandState.Line) {
        if case .chatError = line { dismissIslandError() } else { session.send(.noticeDismissed) }
    }
}

/// The error above Home's tasks: the sentence and an exit.
struct HomeErrorBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            Text(text)
                .font(.uiBody)
                .foregroundStyle(Semantic.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            CloseButton(label: Localized.string("island.notice.dismiss"), action: onDismiss)
        }
        .padding(Space.x3)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.destructiveMuted))
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(ChatErrorSurface.announcement(text)).post() }
    }
}
