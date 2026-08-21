import AppKit
import SwiftUI

/// Silhouette of the Companion window. The frame owns size; SwiftUI does not.
public enum WindowChrome {
    public static let designSize = NSSize(width: 560, height: 840)
    public static let aspectRatio = NSSize(width: 2, height: 3)
    public static let contentMinSize = NSSize(width: 440, height: 660)
    public static let contentMaxSize = NSSize(width: 680, height: 1020)
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
    }

    public static func install<Root: View>(
        _ hosting: NSHostingView<Root>, in window: NSWindow
    ) {
        hosting.sizingOptions = []
        window.contentView = hosting
        hosting.autoresizingMask = [.width, .height]
    }
}
