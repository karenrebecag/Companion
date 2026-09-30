import CompanionCore
import Foundation
import Observation

/// Wave 18-4b. The Settings panel's state. It holds no browser logic: the
/// composition root fills the closures from the browser host, and presence
/// changes arrive by `refresh()`, which the page calls on a timer (the same
/// way the permission rows follow System Settings).
@Observable
@MainActor
package final class BrowserSettingsModel {
    package enum Notice: Equatable {
        case moveApp, noBrowser, symlink, failed
    }

    package private(set) var status: BrowserLinkStatus = .notInstalled
    package private(set) var notice: Notice?
    package let extensionFolder: String?
    package let extensionID: String

    private let readStatus: () -> BrowserLinkStatus
    private let connectAction: () -> BrowserLinkOutcome
    private let removeAction: () -> BrowserLinkOutcome

    package init(
        status: @escaping () -> BrowserLinkStatus,
        connect: @escaping () -> BrowserLinkOutcome,
        remove: @escaping () -> BrowserLinkOutcome,
        extensionFolder: String?, extensionID: String
    ) {
        self.readStatus = status
        self.connectAction = connect
        self.removeAction = remove
        self.extensionFolder = extensionFolder
        self.extensionID = extensionID
        self.status = status()
    }

    package func refresh() { status = readStatus() }

    package func connect() { finish(connectAction()) }

    package func remove() { finish(removeAction()) }

    private func finish(_ outcome: BrowserLinkOutcome) {
        switch outcome {
        case .done: notice = nil
        case .moveApp: notice = .moveApp
        case .noBrowser: notice = .noBrowser
        case .symlink: notice = .symlink
        case .failed: notice = .failed
        }
        refresh()
    }

    package var statusText: String {
        switch status {
        case .notInstalled: Localized.string("settings.browser.status.notInstalled")
        case .disconnected: Localized.string("settings.browser.status.disconnected")
        case .connected(let kind):
            String(format: Localized.string("settings.browser.status.connected"), Self.name(kind))
        }
    }

    package var noticeText: String? {
        switch notice {
        case .none: nil
        case .moveApp: Localized.string("settings.browser.notice.moveApp")
        case .noBrowser: Localized.string("settings.browser.notice.noBrowser")
        case .symlink: Localized.string("settings.browser.notice.symlink")
        case .failed: Localized.string("settings.browser.notice.failed")
        }
    }

    static func name(_ kind: BrowserKind) -> String {
        switch kind {
        case .chrome: "Chrome"
        case .comet: "Comet"
        }
    }
}
