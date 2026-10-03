import Foundation

package struct ArrangeRequest: Sendable, Equatable {
    package var layout: String
    package var apps: [String]
    package var screen: Int
    package var dryRun: Bool

    package init(layout: String, apps: [String], screen: Int, dryRun: Bool) {
        self.layout = layout
        self.apps = apps
        self.screen = screen
        self.dryRun = dryRun
    }
}

/// One `arrange_windows` call, validated before anything reads the screen.
package enum ArrangeWindowsCall: Sendable, Equatable {
    case inventory
    case listLayouts
    case arrange(ArrangeRequest)
    case undo

    static let actions = ["inventory", "list_layouts", "arrange", "undo"]

    /// What moves windows asks; what only reads or plans does not.
    package var needsApproval: Bool {
        switch self {
        case .inventory, .listLayouts: false
        case .arrange(let request): !request.dryRun
        case .undo: true
        }
    }

    package static func parse(_ arguments: [String: Any]) -> Result<ArrangeWindowsCall, ContractError> {
        let action = (arguments["action"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        switch action {
        case "inventory": return .success(.inventory)
        case "list_layouts": return .success(.listLayouts)
        // The reference names it restore; either word means the same undo.
        case "undo", "restore": return .success(.undo)
        case "arrange": return arrange(arguments).map(ArrangeWindowsCall.arrange)
        default:
            return .failure(.invalidArgs(
                "unknown action \"\(action)\"; use one of: \(actions.joined(separator: ", "))"))
        }
    }

    private static func arrange(_ arguments: [String: Any]) -> Result<ArrangeRequest, ContractError> {
        let layout = (arguments["layout"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard let slots = WindowLayouts.fractions(layout)?.count else {
            return .failure(.invalidArgs(
                "unknown layout \"\(layout)\"; valid layouts: \(WindowLayouts.names.joined(separator: ", "))"))
        }
        let apps: [String]
        switch appNames(arguments["apps"]) {
        case .success(let names): apps = names
        case .failure(let error): return .failure(error)
        }
        guard apps.count <= slots else {
            return .failure(.invalidArgs(
                "layout '\(layout)' has \(slots) slots but \(apps.count) apps were given"))
        }
        let screen = (arguments["screen"] as? NSNumber)?.intValue
            ?? (arguments["screen"] as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1
        guard screen >= 1 else {
            return .failure(.invalidArgs("Display \(screen) does not exist; displays are numbered from 1"))
        }
        let dryRun = (arguments["dry_run"] as? Bool) ?? false
        return .success(ArrangeRequest(layout: layout, apps: apps, screen: screen, dryRun: dryRun))
    }

    /// A list of names; a single comma-separated string is read as one,
    /// since models send either.
    private static func appNames(_ raw: Any?) -> Result<[String], ContractError> {
        let items: [Any]
        if let list = raw as? [Any] {
            items = list
        } else if let text = raw as? String {
            items = text.split(separator: ",").map(String.init)
        } else {
            items = []
        }
        var names: [String] = []
        for item in items {
            guard let text = item as? String else {
                return .failure(.invalidArgs("apps must be a list of app names"))
            }
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= ParentToolPolicy.maxAppNameLength else {
                return .failure(.invalidArgs(
                    "each app name must be 1 to \(ParentToolPolicy.maxAppNameLength) characters"))
            }
            names.append(name)
        }
        guard !names.isEmpty else {
            return .failure(.invalidArgs("arrange needs apps: the app names to place, in slot order"))
        }
        return .success(names)
    }
}

/// One window's before and after.
package struct Placement: Sendable, Equatable {
    package var window: WindowInfo
    package var requested: WindowRect
    package var actual: WindowRect
    package var prep: [String]
    /// Set when the move failed; the window stayed where it was.
    package var failure: String?
    /// The window moved but could not be pulled back inside the work area.
    package var clampFailure: String?

    package var exact: Bool { failure == nil && requested.isClose(to: actual) }
}

/// What `arrange` did or, on a dry run, would do.
package struct Arrangement: Sendable, Equatable {
    package var layout: String
    package var display: DisplayInfo
    package var placed: [Placement]
    package var notFound: [String]
    package var dryRun: Bool
    /// Displays as they were read, to say where a window is now.
    package var displays: [DisplayInfo]

    package var report: String {
        var lines = ["Layout '\(layout)' on Display \(display.number) (\(dryRun ? "would go" : "placed")):"]
        for placement in placed {
            let app = WindowArrangement.safe(placement.window.app)
            if let failure = placement.failure {
                lines.append("  \(app): could not move (\(failure))")
                continue
            }
            let note: String
            if dryRun {
                note = "  (now \(placement.window.whereabouts(on: displays)))"
            } else {
                let clamp = placement.clampFailure.map { "; could not pull it inside the work area: \($0)" } ?? ""
                note = placement.exact ? "" : "  (app settled at \(placement.actual)\(clamp))"
            }
            let prep = placement.prep.isEmpty ? "" : "  [\(placement.prep.joined(separator: ", "))]"
            lines.append("  \(app): \(placement.requested)\(note)\(prep)")
        }
        for name in notFound {
            lines.append("  \(WindowArrangement.safe(name)): no window found")
        }
        return lines.joined(separator: "\n")
    }
}

package enum WindowArrangement {
    /// Window titles and app names come from other apps: one line each,
    /// capped, never able to forge a line of the report.
    static func safe(_ text: String) -> String {
        TextSanitizer.display(text, maxLength: 80)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    package static let permission = ContractError(
        code: BridgeCode.needsAccessibility,
        message: "Accessibility permission is not granted to Companion, so windows cannot be read or moved. "
            + "Ask the user to enable Companion under System Settings > Privacy & Security > Accessibility.")

    package static let busy = ContractError(
        code: "busy", message: "another arrange or undo is still moving windows; try again when it finishes")

    /// Nothing moved: a failure, so nothing downstream says it was arranged.
    /// The report still names every window and why.
    static func nothingMoved(_ report: String) -> ContractError {
        ContractError(code: "nothing_moved", message: report)
    }

    package static let nothingToUndo = ContractError(
        code: "nothing_to_undo", message: "no arrangement made in this session is waiting to be undone")

    package static func display(_ number: Int, in displays: [DisplayInfo]) -> Result<DisplayInfo, ContractError> {
        guard !displays.isEmpty else { return .failure(.notFound("no displays found")) }
        guard number >= 1, number <= displays.count else {
            return .failure(.invalidArgs(
                "Display \(number) does not exist; there are \(displays.count) (numbered from 1)"))
        }
        return .success(displays[number - 1])
    }

    /// Requested apps to windows, in slot order. A window already taken is
    /// not offered again, so "Chrome, Chrome" fills two Chrome windows.
    package static func plan(
        _ request: ArrangeRequest, display: DisplayInfo, displays: [DisplayInfo], windows: [WindowInfo]
    ) -> Arrangement {
        let rects = WindowLayouts.slots(request.layout, in: display.workArea) ?? []
        var free = windows
        var placed: [Placement] = []
        var notFound: [String] = []
        for (app, rect) in zip(request.apps, rects) {
            guard let window = WindowLayouts.match(app: app, in: free) else {
                notFound.append(app)
                continue
            }
            free.removeAll { $0.id == window.id }
            placed.append(Placement(window: window, requested: rect, actual: window.frame,
                                    prep: window.prepNeeded))
        }
        return Arrangement(layout: request.layout, display: display, placed: placed,
                           notFound: notFound, dryRun: request.dryRun, displays: displays)
    }

    /// Enough for any real desk; past it the list costs context and says
    /// nothing new.
    static let maxInventoryWindows = 200

    /// Titles go to the model, as Incredible sends them: telling two windows
    /// of one app apart is what the user asks for ("the Docs one on the
    /// left"). They are read only when the model asks, sanitized, and never
    /// written to the log.
    package static func inventory(displays: [DisplayInfo], windows: [WindowInfo]) -> String {
        var lines = ["Displays:"] + (displays.isEmpty ? ["  none found"] : displays.map { "  \($0)" })
        guard !windows.isEmpty else {
            return (lines + ["No standard windows are open."]).joined(separator: "\n")
        }
        lines.append("Windows by app, front to back:")
        let listed = windows.prefix(maxInventoryWindows)
        var order: [String] = []
        var byApp: [String: [WindowInfo]] = [:]
        for window in listed {
            if byApp[window.app] == nil { order.append(window.app) }
            byApp[window.app, default: []].append(window)
        }
        for app in order {
            lines.append("\(safe(app)):")
            for window in byApp[app] ?? [] {
                lines.append("  \"\(safe(window.title))\" \(window.whereabouts(on: displays))")
            }
        }
        if windows.count > listed.count {
            lines.append("+\(windows.count - listed.count) more windows not listed")
        }
        return lines.joined(separator: "\n")
    }

    /// What undo has to do: the windows still open and somewhere else go
    /// back; the ones closed since are reported, never guessed at. A window
    /// that was in full screen goes back into it and gets no frame write:
    /// full screen sets its own frame, and a write clamped to the work area
    /// would only be undone by it.
    package struct Restore: Sendable {
        package var moves: [(window: WindowInfo, to: WindowRect)]
        package var fullScreen: [WindowInfo]
        package var closed: [WindowInfo]
    }

    package static func restore(snapshot: [WindowInfo], live: [WindowInfo]) -> Restore {
        var plan = Restore(moves: [], fullScreen: [], closed: [])
        for old in snapshot {
            guard let now = live.first(where: { $0.id == old.id }) else {
                plan.closed.append(old)
                continue
            }
            if old.fullscreen {
                if !now.fullscreen { plan.fullScreen.append(now) }
            } else if !now.frame.isClose(to: old.frame) || now.fullscreen {
                plan.moves.append((now, old.frame))
            }
        }
        return plan
    }

    package static func restoreReport(
        moved: Int, failed: [(WindowInfo, String)], unclamped: [(WindowInfo, String)] = [],
        closed: [WindowInfo], allClosed: Bool = false
    ) -> String {
        var lines: [String] = []
        switch moved {
        case 0 where allClosed:
            lines.append("None of the windows from the last arrangement are still open:")
        case 0: lines.append("Every window is already where it was before the last arrangement.")
        case 1: lines.append("Restored 1 window to where it was before the last arrangement.")
        default: lines.append("Restored \(moved) windows to where they were before the last arrangement.")
        }
        for (window, reason) in failed {
            lines.append("  \(safe(window.app)) \"\(safe(window.title))\": could not move back (\(reason))")
        }
        for (window, reason) in unclamped {
            lines.append("  \(safe(window.app)) \"\(safe(window.title))\": moved back, but could not pull "
                + "it inside the work area (\(reason))")
        }
        for window in closed {
            lines.append("  \(safe(window.app)) \"\(safe(window.title))\": closed since, skipped")
        }
        return lines.joined(separator: "\n")
    }
}
