import CompanionCore
import CompanionUIPro
import SwiftUI

/// The controls a settings row ends with. Layout (groups, rows, headers) is
/// the Arc Pro components' job; this file only supplies Companion's buttons
/// and switch to them.

/// 16l: Incredible's Button variants. `neutral` is the ghost (5 % wash),
/// `primary` the black solid, `destructive` the red ghost.
enum SettingsPillKind {
    /// Grey "Cambiar": the everyday action.
    case neutral
    /// Black "+ Añadir": the one thing a page is for.
    case primary
    /// Red: removes something that does not come back.
    case destructive
}

/// A settings action in shadcn's button: the pill's three roles map onto
/// its variants.
struct SettingsPill: View {
    let title: String
    var kind: SettingsPillKind = .neutral
    var symbol: String? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ButtonSize.default.gap) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
        }
        .buttonStyle(.shadcn(ButtonVariant(pill: kind)))
        .disabled(!enabled)
    }
}

extension ButtonVariant {
    init(pill: SettingsPillKind) {
        switch pill {
        case .neutral: self = .secondary
        case .primary: self = .default
        case .destructive: self = .destructive
        }
    }
}

/// The drawn Arc switch, not the native Toggle: macOS greys a native switch
/// whenever its window is not key, and draws its own capsule thumb.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        IncredibleSwitch(label, isOn: $isOn)
    }
}

extension View {
    /// Gives a row the id a palette pick scrolls to; rows without a palette entry get none.
    @ViewBuilder func settingsAnchor(_ key: String?) -> some View {
        if let key { self.id(key) } else { self }
    }
}
