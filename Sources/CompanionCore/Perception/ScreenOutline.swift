import Foundation

// What leaves the device about a window: its controls and their labels. The
// content of text rows, fields and areas, and the window title, stay in the
// snapshot. A diff carries which flags changed, never the values behind them.

/// One control, labels only. There is no value property on purpose: content
/// is reported as `hasValue`, and nothing else about it leaves.
package struct OutlineControl: Sendable, Equatable {
    package var role: String
    package var label: String
    package var enabled: Bool
    package var focused: Bool
    package var hasValue: Bool

    fileprivate init(_ element: SnapshotElement) {
        role = element.role
        label = ScreenOutline.clipLabel(element.label)
        enabled = element.enabled
        focused = element.focused
        hasValue = !(element.value ?? "").isEmpty
    }
}

/// Which flags of a control changed between two reads.
package struct OutlineChange: Sendable, Equatable {
    package var role: String
    package var label: String
    package var valueChanged: Bool
    package var enabledChanged: Bool
    package var focusedChanged: Bool
}

package struct ScreenOutline: Sendable, Equatable {
    /// Same caps as the scan the model reads: 150 elements, labels short.
    static let maxLabel = 80

    package var controls: [OutlineControl]
    package var partial: Bool

    package init(snapshot: ScreenSnapshot) {
        let projected = Self.project(snapshot.elements)
        controls = projected.controls
        partial = snapshot.partial || projected.cut
    }

    fileprivate static func clipLabel(_ label: String) -> String {
        label.count > maxLabel ? String(label.prefix(maxLabel)) + "…" : label
    }

    /// The controls among `elements`, capped; `cut` when the cap removed some.
    fileprivate static func project(_ elements: [SnapshotElement]) -> (controls: [OutlineControl], cut: Bool) {
        let controls = elements.filter { ScreenRoles.isControl($0.role) }
        return (controls.prefix(ScreenScan.maxElements).map(OutlineControl.init),
                controls.count > ScreenScan.maxElements)
    }
}

/// The controls that appeared, disappeared or changed flags between two reads.
package struct ScreenOutlineDiff: Sendable, Equatable {
    package var appeared: [OutlineControl]
    package var disappeared: [OutlineControl]
    package var changed: [OutlineChange]
    package var partial: Bool

    package init(diff: ScreenDiff) {
        let appeared = ScreenOutline.project(diff.appeared)
        let disappeared = ScreenOutline.project(diff.disappeared)
        let changed = diff.changed.filter { ScreenRoles.isControl($0.after.role) }
        self.appeared = appeared.controls
        self.disappeared = disappeared.controls
        self.changed = changed.prefix(ScreenScan.maxElements).map { change in
            OutlineChange(
                role: change.after.role, label: ScreenOutline.clipLabel(change.after.label),
                valueChanged: change.before.value != change.after.value,
                enabledChanged: change.before.enabled != change.after.enabled,
                focusedChanged: change.before.focused != change.after.focused)
        }
        partial = diff.partial || appeared.cut || disappeared.cut || changed.count > ScreenScan.maxElements
    }
}
