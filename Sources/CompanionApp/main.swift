import AppKit
import CompanionCore
import CompanionServices
import CompanionUI
import SwiftUI

@main
enum CompanionMain {
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var model: ChatViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        Log.configure(
            fileURL: home
                .appendingPathComponent("Library/Logs/Companion.log"))

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/conversations")
        do {
            try FileManager.default.createDirectory(
                at: support, withIntermediateDirectories: true)
        } catch {
            // Log without error details to avoid exposing system paths/permissions.
            Log.app("could not create conversations dir")
        }

        let secrets = KeychainSecretStore()
        let transport = URLSessionChatTransport()
        let probe = LiveCapabilityProbe(transport: transport)
        let first = NSFullUserName()
            .split(separator: " ").first.map(String.init) ?? ""
        let config = Config(ownerFirstName: first)
        let chat = ChatProviderClient(
            secrets: secrets,
            probe: probe,
            transport: transport,
            settings: config.chat,
            ownerFirstName: first)
        let store = ConversationStore(directory: support)
        let model = ChatViewModel(
            chat: chat, secrets: secrets, store: store, config: config)
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.minSize = NSSize(width: 440, height: 660)
        window.maxSize = NSSize(width: 680, height: 1020)
        window.title = "Companion"
        window.contentView = NSHostingView(
            rootView: CompanionRootView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        Log.app("launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}
