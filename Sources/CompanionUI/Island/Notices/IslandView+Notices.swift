import CompanionCore
import SwiftUI

// What a notice card's button does: every road that needs the window asks
// the main to raise it; the island only names the page.
extension IslandView {
    func perform(_ action: IslandState.Action) {
        switch action {
        case .openKeys:
            onShowMain()
            NotificationCenter.default.post(name: .companionOpenSettings, object: SettingsTab.privacy.rawValue)
        case .openPermission(let failure):
            if let link = VoiceCopy.settingsLink(for: failure) { openURL(link) }
        case .stopHands:
            NotificationCenter.default.post(name: .companionStopHands, object: nil)
        case .openApps(let slug):
            // Same road as .openKeys: the window is the main's to raise,
            // the island only names the page and the app it means.
            onShowMain()
            NotificationCenter.default.post(name: .companionOpenApps, object: slug)
        case .openUpdate:
            if let url = updates?.available?.pageURL { openURL(url) }
            // Going to the page is answering the offer.
            updates?.dismissNotice()
        }
    }

    /// The card's own exit: an offer is waved away for the session, every
    /// other notice by the chat's rule.
    func dismissNotice(_ line: IslandState.Line) {
        if case .updateAvailable = line { updates?.dismissNotice() } else { chat.dismissIslandNotice(line) }
    }
}
