import CompanionCore
import Foundation

extension VoiceSession {
    func openAIKey() -> String? {
        let value: String?
        do {
            value = try secrets.read(.openAI)
        } catch {
            Log.app("voice: OpenAI key unread")
            return nil
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
