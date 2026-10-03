import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func screenRecordingCardNamesTheSettingsPane() async {
    expectEq(VoiceCopy.settingsLink(for: .screenRecordingDenied), PermissionSettingsLink.screenRecording,
             "the card opens the Screen Recording pane")
    await Localized.scoped(to: .en) {
        let text = VoiceCopy.failure(.screenRecordingDenied)
        expect(text.contains("Privacy & Security > Screen & System Audio Recording"), "en names the pane: \(text)")
    }
    await Localized.scoped(to: .es) {
        let text = VoiceCopy.failure(.screenRecordingDenied)
        expect(text.contains("Privacidad y seguridad > Grabación de pantalla y audio del sistema"),
               "es names the pane: \(text)")
    }
    await Localized.scoped(to: .es) {
        expectEq(IslandNotice.content(for: .permission(.screenRecordingDenied))?.grid, .permission,
                 "it sits on the permission grid")
    }
}
