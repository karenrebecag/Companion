import Foundation

/// The named layouts and how a request finds its window. Values follow
/// Incredible 0.2.36 so a request phrased for it lands the same here.
package enum WindowLayouts {
    /// A slot as fractions of the work area.
    package struct Fraction: Sendable, Equatable {
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
    }

    private static let half = 0.5
    private static let third = 1.0 / 3.0
    private static let twoThirds = 2.0 / 3.0

    private static func f(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Fraction {
        Fraction(x: x, y: y, width: width, height: height)
    }

    /// Ordered: `list_layouts` and the spec's enum read in this order.
    package static let all: [(name: String, summary: String, slots: [Fraction])] = [
        ("left-right", "two halves side by side",
         [f(0, 0, half, 1), f(half, 0, half, 1)]),
        ("main-side", "a wide main window, a narrow one on the right",
         [f(0, 0, twoThirds, 1), f(twoThirds, 0, third, 1)]),
        ("side-main", "a narrow window on the left, a wide main one",
         [f(0, 0, third, 1), f(third, 0, twoThirds, 1)]),
        ("thirds", "three equal columns",
         [f(0, 0, third, 1), f(third, 0, third, 1), f(twoThirds, 0, third, 1)]),
        ("four-columns", "four equal columns",
         [f(0, 0, 0.25, 1), f(0.25, 0, 0.25, 1), f(0.5, 0, 0.25, 1), f(0.75, 0, 0.25, 1)]),
        ("top-bottom", "two halves, one above the other",
         [f(0, 0, 1, half), f(0, half, 1, half)]),
        ("grid", "four quarters: top-left, top-right, bottom-left, bottom-right",
         [f(0, 0, half, half), f(half, 0, half, half), f(0, half, half, half), f(half, half, half, half)]),
        ("main-stack", "a wide main window, two stacked on the right",
         [f(0, 0, twoThirds, 1), f(twoThirds, 0, third, half), f(twoThirds, half, third, half)]),
        ("stack-main", "two stacked on the left, one full-height column on the right",
         [f(0, 0, half, half), f(0, half, half, half), f(half, 0, half, 1)]),
        ("full", "one window filling the usable area (not macOS full screen)",
         [f(0, 0, 1, 1)]),
        ("centered", "one window centred at 70% by 80%, for focus",
         [f(0.15, 0.1, 0.7, 0.8)]),
    ]

    package static var names: [String] { all.map(\.name) }

    package static func fractions(_ name: String) -> [Fraction]? {
        all.first { $0.name == name }?.slots
    }

    package static func slots(_ name: String, in area: WindowRect) -> [WindowRect]? {
        fractions(name)?.map { slot($0, in: area) }
    }

    /// Edges are rounded, not sizes, so neighbouring slots share an edge
    /// exactly. Half goes to even, as the reference rounds.
    package static func slot(_ fraction: Fraction, in area: WindowRect) -> WindowRect {
        func edge(_ length: Int, _ at: Double) -> Int {
            Int((Double(length) * at).rounded(.toNearestOrEven))
        }
        let left = area.x + edge(area.width, fraction.x)
        let top = area.y + edge(area.height, fraction.y)
        let right = area.x + edge(area.width, fraction.x + fraction.width)
        let bottom = area.y + edge(area.height, fraction.y + fraction.height)
        return WindowRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    package static var listing: String {
        (["Layouts (slots fill in the order the apps are given):"]
            + all.map { "  \($0.name): \($0.slots.count) slot\($0.slots.count == 1 ? "" : "s"), \($0.summary)" })
            .joined(separator: "\n")
    }

    /// The frontmost window whose app name contains `app`, ignoring case;
    /// failing that, the frontmost whose title does. `title` narrows both.
    /// An app name of four letters or more inside the request also counts,
    /// so "VS Code" finds the app called Code; shorter names would match
    /// too much ("Arc" in "search").
    package static func match(app: String, title: String? = nil, in windows: [WindowInfo]) -> WindowInfo? {
        let needle = app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wanted = title.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { $0.isEmpty ? nil : $0 }
        func titleOK(_ window: WindowInfo) -> Bool {
            wanted.map { window.title.lowercased().contains($0) } ?? true
        }
        func appOK(_ window: WindowInfo) -> Bool {
            let name = window.app.lowercased()
            return name.contains(needle) || (name.count >= 4 && needle.contains(name))
        }
        if let byApp = windows.first(where: { appOK($0) && titleOK($0) }) { return byApp }
        return windows.first { $0.title.lowercased().contains(needle) && titleOK($0) }
    }
}
