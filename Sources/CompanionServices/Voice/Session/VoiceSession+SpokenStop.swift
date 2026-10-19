import CompanionCore
import Foundation

extension VoiceSession {
    /// The classic hold said only "para": the same brake as the Stop button,
    /// plus the background errand, since someone talking to their Mac cannot
    /// reach the button. A pending approval sheet is not touched: the sheet's
    /// own rules (a spoken no, a click) decide it. False hands the words back
    /// to the ordinary turn.
    func stopBySpeech() async -> Bool {
        guard livePendingApproval == nil, !machine.snapshot.sheetParked else { return false }
        Log.app("voice: spoken stop, no model call")
        screen?.cancel()
        classic.cancelPressedContext()
        await classic.onStopJob?(nil)
        await interrupt()
        return true
    }
}
