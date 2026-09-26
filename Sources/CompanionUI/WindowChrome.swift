import AppKit
import SwiftUI

/// Silhouette of the Companion window. The frame owns size; SwiftUI does not.
/// Landscape 16:10 like Incredible's (spec 16j §8): a sidebar and a page,
/// no longer the 2:3 column the chat needed.
public enum WindowChrome {
    public static let designSize = NSSize(width: 1120, height: 700)
    public static let aspectRatio = NSSize(width: 16, height: 10)
    public static let contentMinSize = NSSize(width: 880, height: 550)
    public static let contentMaxSize = NSSize(width: 1440, height: 900)
    public static let styleMask: NSWindow.StyleMask = [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
    ]
    // AppDelegate retains the window; the default true double-frees on close.
    public static let releasedWhenClosed = false

    public static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = releasedWhenClosed
        window.contentAspectRatio = aspectRatio
        window.contentMinSize = contentMinSize
        window.contentMaxSize = contentMaxSize
        applyAppearance(window)
    }

    public static func appearance(for pref: AppearancePreference) -> NSAppearance? {
        switch pref {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
    }

    public static func applyAppearance(_ window: NSWindow) {
        window.appearance = appearance(for: AppearancePreference.stored)
    }

    public static func install<Root: View>(
        _ hosting: NSHostingView<Root>, in window: NSWindow
    ) {
        hosting.sizingOptions = []
        window.contentView = hosting
        hosting.autoresizingMask = [.width, .height]
    }
}
