import CompanionCore
import SwiftUI

// What drops from the notch band: tooltips, the menu, volume and the clip's
// list (16o-1), and what the menu's picks do.
extension IslandView {
    /// Tooltips and dropdowns over the clip (16o-1), kept off the notch band.
    func portalLayer(_ items: [PortalItem], in proxy: GeometryProxy) -> some View {
        let canvas = proxy.size
        let notch = geometry.notch
        let band = CGRect(x: canvas.width / 2 - notch.width / 2, y: 0, width: notch.width, height: notch.height)
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.request.id) { item in
                let anchor = proxy[item.anchor]
                switch item.request {
                case .tooltip(let text):
                    PortalPlaced(anchor: anchor, canvas: canvas, forbidden: band) {
                        IslandTooltipBubble(text: text)
                    }
                    .transition(.opacity)
                case .popover(let kind):
                    PortalPlaced(anchor: anchor, canvas: canvas, forbidden: band, prefers: .below,
                                 align: .leading, onFrame: { rect in
                        geometry.portal = PortalFrame.next(
                            current: geometry.portal, report: rect, from: kind, active: popover)
                    }) {
                        IslandPopover {
                            switch kind {
                            case .menu:
                                IslandMenuList { picked in
                                    popover = nil
                                    choose(picked)
                                }
                            case .volume:
                                IslandVolumeControl(onChange: voice.setVolume)
                            case .attach:
                                IslandAttachList { picked in
                                    popover = nil
                                    pickAttach(picked)
                                }
                            }
                        }
                    }
                    .transition(.islandPopover(anchor: .topLeading, reduceMotion: reduceMotion))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Every path that opens or closes it (button, pick, Escape, the
        // panel closing) animates, so the transition plays.
        .animation(.expoOut(IslandMotionBudget.popover.openDuration), value: popover)
    }

    func choose(_ item: IslandMenuItem) {
        switch item {
        case .settings, .shortcuts:
            onShowMain()
            NotificationCenter.default.post(
                name: .companionOpenSettings,
                object: item == .shortcuts ? SettingsTab.general.rawValue : nil)
        case .openWindow:
            onShowMain()
        case .feedback:
            // The modal lives in the main window (16m-7): bring it up and ask.
            onShowMain()
            FeedbackRequest.raise()
            NotificationCenter.default.post(name: .companionOpenFeedback, object: nil)
        case .clearHistory:
            // The island menu has Clear history in red, as Incredible's does,
            // and its yes runs the same real clear as Settings.
            clearFlow.ask()
        }
    }
}
