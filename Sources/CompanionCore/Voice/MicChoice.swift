import Foundation

// brief ajustes-hoja-incredible E35
// The stored choice is an id, not a name: names collide, and a missing
// device has to stay stored so the same choice applies when it returns.
// An empty list is not "missing" — the devices have not been read yet.

package struct MicInput: Equatable, Sendable, Identifiable {
    package var id: String
    package var name: String
    package var builtIn: Bool

    package init(id: String, name: String, builtIn: Bool) {
        self.id = id
        self.name = name
        self.builtIn = builtIn
    }
}

package struct MicDeviceSnapshot: Equatable, Sendable {
    package var devices: [MicInput]
    package var systemDefaultName: String?
    package static let empty = MicDeviceSnapshot(devices: [], systemDefaultName: nil)

    package init(devices: [MicInput], systemDefaultName: String?) {
        self.devices = devices
        self.systemDefaultName = systemDefaultName
    }
}

package enum MicPreference: Equatable, Sendable, Codable {
    case systemDefault
    case builtIn
    case device(id: String, name: String)
}

package enum MicMenuRow: Equatable, Sendable, Identifiable {
    case builtIn(selected: Bool)
    case systemDefault(name: String?, holding: Bool, selected: Bool)
    case device(id: String, name: String, selected: Bool)
    case missing(id: String, name: String)

    package var id: String {
        switch self {
        case .builtIn: "built-in"
        case .systemDefault: "system"
        case .device(let id, _, _): "input-\(id)"
        case .missing(let id, _): "absent-\(id)"
        }
    }

    package var enabled: Bool {
        if case .missing = self { return false }
        return true
    }

    package var selected: Bool {
        switch self {
        case .builtIn(let selected): selected
        case .systemDefault(_, _, let selected): selected
        case .device(_, _, let selected): selected
        case .missing: false
        }
    }
}

/// What capture and the probe pin. `.builtIn` is "the built-in mic, whichever
/// it is": used when the device list has not been read, so no id is known.
package enum MicTarget: Equatable, Sendable {
    case systemDefault
    case builtIn
    case device(String)

    package var deviceID: String? {
        if case .device(let id) = self { return id }
        return nil
    }
}

/// A target plus what makes the same target a different input. The system
/// default moves without the list changing, so its name is part of the route.
package struct MicRoute: Equatable, Sendable {
    package var target: MicTarget
    package var systemName: String?

    package init(target: MicTarget, systemName: String?) {
        self.target = target
        self.systemName = systemName
    }
}

package struct MicResolved: Equatable, Sendable {
    package var target: MicTarget
    /// Set only when a chosen device is absent from a list that was read.
    package var missingName: String?
    package var rows: [MicMenuRow]

    /// Nil means no specific device id is pinned.
    package var captureID: String? { target.deviceID }

    package init(target: MicTarget, missingName: String?, rows: [MicMenuRow]) {
        self.target = target
        self.missingName = missingName
        self.rows = rows
    }
}

package enum MicChoice {
    package static func resolve(_ preference: MicPreference, _ snapshot: MicDeviceSnapshot) -> MicResolved {
        let devices = snapshot.devices
        let builtIns = devices.filter(\.builtIn)
        let others = devices.filter { !$0.builtIn }

        var target = MicTarget.systemDefault
        var missingName: String?
        var selectBuiltIn = false
        var selectSystem = false
        var selectedID: String?
        var holding = false
        var absent: (id: String, name: String)?

        switch preference {
        case .builtIn:
            if let first = builtIns.first {
                target = .device(first.id)
                selectBuiltIn = true
            } else if devices.isEmpty {
                target = .builtIn
                selectBuiltIn = true
            } else {
                selectSystem = true
            }
        case .systemDefault:
            selectSystem = true
        case .device(let id, let name):
            if let match = devices.first(where: { $0.id == id }) {
                target = .device(match.id)
                if match.builtIn {
                    selectBuiltIn = true
                } else {
                    selectedID = match.id
                }
            } else if !devices.isEmpty {
                missingName = name
                holding = true
                selectSystem = true
                absent = (id, name)
            }
        }

        var rows: [MicMenuRow] = []
        if devices.isEmpty || !builtIns.isEmpty {
            rows.append(.builtIn(selected: selectBuiltIn))
        }
        rows.append(.systemDefault(
            name: snapshot.systemDefaultName, holding: holding, selected: selectSystem))
        for device in others {
            rows.append(.device(
                id: device.id, name: device.name, selected: device.id == selectedID))
        }
        if let absent {
            rows.append(.missing(id: absent.id, name: absent.name))
        }
        return MicResolved(target: target, missingName: missingName, rows: rows)
    }

    package static func captureID(
        preference: MicPreference, snapshot: MicDeviceSnapshot
    ) -> String? {
        resolve(preference, snapshot).captureID
    }

    package static func target(
        preference: MicPreference, snapshot: MicDeviceSnapshot
    ) -> MicTarget {
        resolve(preference, snapshot).target
    }

    package static func route(
        preference: MicPreference, snapshot: MicDeviceSnapshot
    ) -> MicRoute {
        let target = resolve(preference, snapshot).target
        return MicRoute(
            target: target,
            systemName: target == .systemDefault ? snapshot.systemDefaultName : nil)
    }
}
