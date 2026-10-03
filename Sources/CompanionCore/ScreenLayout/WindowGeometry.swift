import Foundation

/// A rectangle in global pixels with the origin at the top-left of the main
/// display: the space Accessibility reads and writes frames in.
package struct WindowRect: Sendable, Equatable, Hashable, CustomStringConvertible {
    package var x: Int
    package var y: Int
    package var width: Int
    package var height: Int

    package init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package var right: Int { x + width }
    package var bottom: Int { y + height }

    package var description: String { "\(width)×\(height) @ \(x),\(y)" }

    package func overlapArea(_ other: WindowRect) -> Int {
        let w = min(right, other.right) - max(x, other.x)
        let h = min(bottom, other.bottom) - max(y, other.y)
        return w > 0 && h > 0 ? w * h : 0
    }

    /// Apps round frames to their own grid, so an exact compare would call
    /// almost every placement off target.
    package func isClose(to other: WindowRect, tolerance: Int = 2) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// Shifted inside `area`, size kept. A window bigger than the area pins
    /// to its top-left, so its title bar stays reachable.
    package func clamped(into area: WindowRect) -> WindowRect {
        WindowRect(
            x: min(max(x, area.x), max(area.x, area.right - width)),
            y: min(max(y, area.y), max(area.y, area.bottom - height)),
            width: width, height: height)
    }
}

/// One display. `number` is what the user and the model say ("on display
/// 2"); the main display (the one with the menu bar) is always 1. Layouts
/// fill `workArea`, which leaves out the menu bar and the Dock.
package struct DisplayInfo: Sendable, Equatable, CustomStringConvertible {
    package var number: Int
    package var name: String
    package var frame: WindowRect
    package var workArea: WindowRect

    package init(number: Int, name: String, frame: WindowRect, workArea: WindowRect) {
        self.number = number
        self.name = name
        self.frame = frame
        self.workArea = workArea
    }

    package var isMain: Bool { number == 1 }

    package var description: String {
        let role = isMain ? ", main" : ""
        return "Display \(number) \"\(name)\"\(role): \(frame.width)×\(frame.height) "
            + "at \(frame.x),\(frame.y); usable \(workArea)"
    }

    /// AppKit's numbers, before any flip: origin at the main display's
    /// bottom-left, y growing up.
    package struct AppKitRect: Sendable, Equatable {
        package var x: Double
        package var y: Double
        package var width: Double
        package var height: Double

        package init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        package func flipped(mainHeight: Double) -> WindowRect {
            WindowRect(
                x: Int(x.rounded()), y: Int((mainHeight - (y + height)).rounded()),
                width: Int(width.rounded()), height: Int(height.rounded()))
        }
    }

    package struct AppKitScreen: Sendable, Equatable {
        package var name: String
        package var frame: AppKitRect
        package var visibleFrame: AppKitRect

        package init(name: String, frame: AppKitRect, visibleFrame: AppKitRect) {
            self.name = name
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// AppKit lists the main display first and measures every screen from
    /// its bottom-left, so the main height is what turns y around.
    package static func fromAppKit(_ screens: [AppKitScreen]) -> [DisplayInfo] {
        guard let mainHeight = screens.first?.frame.height else { return [] }
        return screens.enumerated().map { index, screen in
            DisplayInfo(
                number: index + 1, name: screen.name,
                frame: screen.frame.flipped(mainHeight: mainHeight),
                workArea: screen.visibleFrame.flipped(mainHeight: mainHeight))
        }
    }

    /// The work area of the display `rect` mostly lies on; the first display
    /// when it lies on none.
    package static func workArea(containing rect: WindowRect, in displays: [DisplayInfo]) -> WindowRect {
        var best: WindowRect?
        var bestOverlap = -1
        for display in displays {
            let overlap = display.workArea.overlapArea(rect)
            if overlap > bestOverlap { (best, bestOverlap) = (display.workArea, overlap) }
        }
        return best ?? rect
    }

    /// The display holding most of the frame, nil when it is on none.
    package static func number(holding rect: WindowRect, in displays: [DisplayInfo]) -> Int? {
        var best: (number: Int, overlap: Int)?
        for display in displays {
            let overlap = display.frame.overlapArea(rect)
            if overlap > (best?.overlap ?? 0) { best = (display.number, overlap) }
        }
        return best?.number
    }
}

/// One standard window, as the screen reports it.
package struct WindowInfo: Sendable, Equatable {
    /// Stable for as long as the window lives; what undo finds it by.
    package var id: Int
    package var app: String
    package var title: String
    package var pid: Int32
    package var frame: WindowRect
    package var minimized: Bool
    package var fullscreen: Bool
    /// The whole app is hidden (Cmd-H): the window keeps its frame but is
    /// not painted.
    package var appHidden: Bool

    package init(
        id: Int, app: String, title: String, pid: Int32, frame: WindowRect,
        minimized: Bool = false, fullscreen: Bool = false, appHidden: Bool = false
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.pid = pid
        self.frame = frame
        self.minimized = minimized
        self.fullscreen = fullscreen
        self.appHidden = appHidden
    }

    package var state: String {
        if fullscreen { return "full screen" }
        if minimized { return "minimized" }
        if appHidden { return "hidden" }
        return "visible"
    }

    /// What the adapter does before it can write a frame: a full-screen
    /// window refuses a position, a minimized one is not on screen.
    package var prepNeeded: [String] {
        var steps: [String] = []
        if fullscreen { steps.append("leave full screen") }
        if minimized { steps.append("un-minimize") }
        return steps
    }

    package func whereabouts(on displays: [DisplayInfo]) -> String {
        let on = DisplayInfo.number(holding: frame, in: displays).map { " on Display \($0)" } ?? ""
        return "\(frame)\(on), \(state)"
    }
}
