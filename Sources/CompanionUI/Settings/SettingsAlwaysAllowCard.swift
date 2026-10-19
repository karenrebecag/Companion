import CompanionCore
import CompanionUIPro
import SwiftUI

/// The "siempre permitir" rules the person kept, each one revocable where it
/// was kept. Revoking takes effect on the next sheet.
struct SettingsAlwaysAllowCard: View {
    @State private var list: AlwaysAllowList

    init(initial: AlwaysAllowList = AlwaysAllowPreference.list) {
        _list = State(initialValue: initial)
    }

    var body: some View {
        SecuritySection(
            title: Localized.string("settings.alwaysAllow.header"),
            description: Localized.string("settings.alwaysAllow.blurb")
        ) {
            ForEach(list.rules, id: \.self) { rule in
                SecurityRow(title: Self.title(of: rule)) {
                    // Revoking is undone by the next "siempre", so it is not a red action.
                    SettingsPill(title: Localized.string("settings.alwaysAllow.revoke"), kind: .neutral) {
                        revoke(rule)
                    }
                }
            }
        }
    }

    private func revoke(_ rule: AlwaysAllowRule) {
        AlwaysAllowPreference.list = AlwaysAllowPreference.list.removing(rule)
        list = AlwaysAllowPreference.list
    }

    static func title(of rule: AlwaysAllowRule) -> String {
        let folder = (rule.folder as NSString).abbreviatingWithTildeInPath
        return String(format: Localized.string("settings.alwaysAllow.upload"), folder, rule.host)
    }
}
