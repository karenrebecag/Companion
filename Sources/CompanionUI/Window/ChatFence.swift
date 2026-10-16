import CompanionCore
import CompanionUIPro
import SwiftUI

/// The `companion:` fences the window draws as cards inside an ai-chat
/// answer; every other fence stays the port's code block.
enum ChatFence {
    static func view(_ fence: AIChatFence) -> AnyView? {
        guard fence.language.hasPrefix("companion:") else { return nil }
        // A card still arriving would show half its JSON as code, then jump.
        guard fence.closed else { return AnyView(EmptyView()) }
        // A body that no longer parses stays visible as the port's code block.
        if fence.language == PresentFence.language {
            return PresentFence.renders(body: fence.body).map { AnyView(PresentView($0)) }
        }
        if let card = MarkdownView.fenceCard(language: fence.language, body: fence.body) {
            return AnyView(CardView(card: card))
        }
        if fence.language == CompanionBlocks.choiceLanguage, let choice = CompanionBlocks.choice(fence.body) {
            return AnyView(MarkdownView.choiceText(choice))
        }
        return nil
    }
}

extension TaskThread {
    static var chatStrings: AIChatStrings {
        var strings = AIChatStrings(
            userPrefix: Localized.string("task.you"),
            assistantPrefix: Localized.string("task.assistant"),
            thinking: Localized.string("chat.ai.thinking"),
            thoughtFor: Localized.string("chat.ai.thoughtFor"),
            thoughtBriefly: Localized.string("chat.ai.thoughtBriefly"),
            stoppedThinking: Localized.string("chat.ai.stoppedThinking"),
            sourcesOne: Localized.string("chat.ai.sources.one"),
            sourcesOther: Localized.string("chat.ai.sources.other"),
            openSource: Localized.string("chat.ai.openSource"),
            citation: Localized.string("chat.ai.citation"),
            copyAnswer: Localized.string("chat.ai.copyAnswer"),
            copyCode: Localized.string("chat.ai.copyCode"),
            copied: Localized.string("chat.ai.copied"),
            code: Localized.string("chat.ai.code"),
            toolDone: Localized.string("chat.ai.toolDone"),
            stopped: Localized.string("chat.ai.stopped"),
            error: Localized.string("chat.ai.error"),
            emptyTitle: Localized.string("task.empty.title"),
            emptyText: Localized.string("task.empty.text"))
        strings.agentRun = ChatAgentRun.strings
        return strings
    }
}
