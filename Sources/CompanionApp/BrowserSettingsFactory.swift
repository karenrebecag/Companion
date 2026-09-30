import CompanionCore
import CompanionServices
import CompanionUI
import Foundation

/// Wave 18-4b: the Settings panel's model, filled from the browser host.
@MainActor
func makeBrowserSettings(host: BrowserHost) -> BrowserSettingsModel {
    // The extension ships inside the app so its path is stable; a dev build
    // run from the package has none and the panel simply omits the line.
    let folder = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true)
    let exists = folder.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    return BrowserSettingsModel(
        status: { host.status },
        connect: { host.connect() },
        remove: { host.remove() },
        extensionFolder: exists ? folder?.path : nil,
        extensionID: BrowserPolicy.pinnedExtensionID)
}
