import CompanionCore
import SwiftUI

// S1c of the Settings brief (ajustes-hoja-incredible): after a search pick,
// Incredible looks for the row a few times while the page mounts, centres it
// and lays a band behind it. Values come from the local reference
// [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967].

/// Finding the picked row. Pure: the page swap mounts its rows a beat after
/// the pick, so the view polls this until the row shows up or it gives up.
package struct SettingsSearchJump: Equatable {
    package static let fadeIn = 0.3
    package static let hold = 1.1
    package static let fadeOut = 0.35
    package static let bandOutset: CGFloat = Space.x1_5
    package static let attempts = 20
    package static let retryInterval = 0.05

    package struct BandStep: Equatable {
        package let visible: Bool
        package let fade: Double
        /// How long to wait after starting this step before the next one.
        package let wait: Double
    }

    /// In, hold, out: the hold rides on the fade-in's wait.
    package static let bandSteps: [BandStep] = [
        BandStep(visible: true, fade: fadeIn, wait: fadeIn + hold),
        BandStep(visible: false, fade: fadeOut, wait: fadeOut),
    ]

    package enum Step: Equatable {
        case wait, found(String), done
    }

    private let target: String
    private var tries = 0
    private var finished = false

    package init(target: String) { self.target = target }

    /// Page entries open the page and stop: there is no row to centre.
    package static func target(for entry: SettingsSearch.Entry) -> String? {
        entry.id.hasPrefix("settings.tab.") ? nil : entry.id
    }

    package mutating func poll(present: Set<String>) -> Step {
        guard !finished else { return .done }
        tries += 1
        if present.contains(target) {
            finished = true
            return .found(target)
        }
        if tries >= Self.attempts {
            finished = true
            return .done
        }
        return .wait
    }
}

/// The band behind the row a search landed on.
struct SettingsBand: Equatable {
    let key: String
    var visible: Bool
}

private struct SettingsBandKey: EnvironmentKey {
    static let defaultValue: SettingsBand? = nil
}

extension EnvironmentValues {
    var settingsBand: SettingsBand? {
        get { self[SettingsBandKey.self] }
        set { self[SettingsBandKey.self] = newValue }
    }
}

/// Only keyed rows take a scroll id: a shared nil id would tie every unkeyed row together.
private struct ScrollID: ViewModifier {
    let key: String?

    func body(content: Content) -> some View {
        if let key { content.id(key) } else { content }
    }
}

/// The keyed rows the page has mounted, so the jump knows when its row exists.
struct SettingsRowKeys: PreferenceKey {
    static let defaultValue: Set<String> = []
    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
        value.formUnion(nextValue())
    }
}

private struct SettingsSearchTarget: ViewModifier {
    let key: String?
    @Environment(\.settingsBand) private var band

    func body(content: Content) -> some View {
        content
            .background {
                Semantic.hover
                    .padding(.vertical, -SettingsSearchJump.bandOutset)
                    .opacity(lit ? 1 : 0)
            }
            .modifier(ScrollID(key: key))
            // Added to the children's keys, not set: a keyed card holds keyed rows.
            .transformPreference(SettingsRowKeys.self) { keys in
                if let key { keys.insert(key) }
            }
    }

    private var lit: Bool {
        guard let key, let band else { return false }
        return band.key == key && band.visible
    }
}

extension View {
    /// Makes a row findable by a search pick: scroll id, presence and band.
    func settingsSearchTarget(_ key: String?) -> some View {
        modifier(SettingsSearchTarget(key: key))
    }
}
