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
        }
    }
}
