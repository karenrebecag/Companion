import CompanionCore
import SwiftUI

/// The "siempre permitir" rules the person kept, each one revocable where it
/// was kept. Revoking takes effect on the next sheet.
struct SettingsAlwaysAllowCard: View {
    @State private var list: AlwaysAllowList

    init(initial: AlwaysAllowList = AlwaysAllowPreference.list) {
        _list = State(initialValue: initial)
    }

    var body: some View {
        SettingsCard(label: Localized.string("settings.alwaysAllow.label"), key: "settings.alwaysAllow.header") {
            if list.rules.isEmpty {
                Text(Localized.string("settings.alwaysAllow.empty"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.x4)
            } else {
                ForEach(list.rules, id: \.self) { rule in
                    SettingsRow(title: Self.title(of: rule)) {
                        Button(Localized.string("settings.alwaysAllow.revoke")) { revoke(rule) }
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
        String(format: Localized.string("settings.alwaysAllow.upload"), rule.host)
    }
}
