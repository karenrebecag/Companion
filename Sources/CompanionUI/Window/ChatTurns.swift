import CompanionCore
import CompanionUIPro
import Foundation

/// What the turn in progress adds to the saved messages: the reply still
/// streaming, and the specialist's steps while it works.
struct ChatLive: Equatable {
    var streaming: String
    var busy: Bool
    var job: JobTimeline?
    var now: Date
}

/// Companion's messages as Arc's ai-chat turns. The port stays data-agnostic;
/// this is the one place that knows which status line is a tool result, where
/// a reply's sources are and which steps are thoughts.
enum ChatTurns {
    struct Thread: Equatable {
        var turns: [AIChatTurn]
        /// Cards a reply painted from its own channel, by turn id: they never
        /// passed through the text, so the host draws them under the answer.
        var cards: [String: [Card]]
    }

    /// The reply the island is working on, before any message of it exists.
    static let liveID = "live"

    static func thread(_ messages: [ChatMessage], live: ChatLive? = nil) -> Thread {
        var builder = Builder()
        for message in messages { builder.add(message) }
        let working = builder.openParentRun
        builder.flush(settled: !(live?.busy ?? false))
        var turns = builder.turns
        if let live, live.busy { applyLive(live, parent: working, to: &turns) }
        return Thread(turns: turns, cards: builder.cards)
    }

    /// One assistant turn gathers everything between two user messages: the
    /// preface, the tools it called and their results, and the final reply.
    private struct Builder {
        var turns: [AIChatTurn] = []
        var cards: [String: [Card]] = [:]
        private var reply: Reply?

        struct Reply {
            var id: String
            var texts: [String] = []
            var calls: [ChatAgentRun.ParentStep] = []
            var cards: [Card] = []
            var failure: String?
            var endedWithoutAnswer = false
            var stopped = false
            var run: AIAgentRun?
        }

        mutating func add(_ message: ChatMessage) {
            if message.role == .user, !message.isStatus {
                flush(settled: true)
                turns.append(AIChatTurn(
                    id: message.id.uuidString,
                    content: .user(text: message.text, attachments: message.attachments.map(\.name))))
                return
            }
            var current = reply ?? Reply(id: message.id.uuidString)
            if let recall = message.recall, recall.role == .assistant {
                current.calls += recall.toolCalls.map(ChatAgentRun.parentStep)
            }
            if message.isStatus {
                if let recall = message.recall, recall.role == .tool, let id = recall.toolCallID,
                   let index = current.calls.firstIndex(where: { $0.id == id }) {
                    current.calls[index].result = message.text
                    current.calls[index].failed = message.stepFailed
                }
                if message.isFailure { current.failure = message.text }
                if let record = message.job { current.run = ChatAgentRun.finished(record) }
                if message.text == ChatCopy.jobStopped { current.stopped = true }
            } else {
                if !message.text.isEmpty { current.texts.append(message.text) }
                if message.endedWithoutAnswer { current.endedWithoutAnswer = true }
                if let card = message.card { current.cards.append(card) }
            }
            reply = current
        }

        /// The parent's run of the reply still writing, before it settles.
        var openParentRun: AIAgentRun? {
            guard let current = reply else { return nil }
            return ChatAgentRun.parent(current.calls, settled: false, stopped: false, failedTurn: false)
        }

        /// `settled` is false only for the turn a live reply is still writing.
        mutating func flush(settled: Bool) {
            guard let current = reply else { return }
            reply = nil
            let text = current.texts.joined(separator: "\n\n")
            let status: AIChatAnswer.Status =
                current.failure != nil ? .error : current.stopped ? .stopped : settled ? .done : .streaming
            var answer = ChatTurns.answer(text: text, status: status, failure: current.failure)
            answer.run = ChatAgentRun.joined(
                ChatAgentRun.parent(current.calls, settled: settled, stopped: current.stopped,
                                    failedTurn: current.failure != nil || current.endedWithoutAnswer),
                current.run)
            turns.append(AIChatTurn(id: current.id, content: .assistant(answer)))
            if !current.cards.isEmpty { cards[current.id] = current.cards }
        }
    }

    /// The reply's own words, with its "Sources" list lifted out into the
    /// citation list: the same links as bare text above would say them twice.
    static func answer(text: String, status: AIChatAnswer.Status, failure: String?) -> AIChatAnswer {
        let found = MarkdownSplitter.extractSources(MarkdownSplitter.split(text)).web
        let sources = found.compactMap { link -> AIChatSource? in
            guard let url = IslandResultCardModel.webURL(link.url) else { return nil }
            return AIChatSource(
                title: link.title.isEmpty ? IslandResultCardModel.readableHost(url) : link.title,
                url: url, snippet: link.detail)
        }
        let body = sources.isEmpty ? text : removingSourcesSection(text)
        return AIChatAnswer(text: body, status: status, sources: sources, errorNote: failure)
    }

    /// The live turn: the words streaming so far, the specialist's steps as
    /// Arc's agent-run timeline, its thoughts as the reasoning fold.
    private static func applyLive(_ live: ChatLive, parent: AIAgentRun?, to turns: inout [AIChatTurn]) {
        var answer: AIChatAnswer
        var id = liveID
        if let last = turns.last, case .assistant(let saved) = last.content {
            answer = saved
            id = last.id
            turns.removeLast()
        } else {
            answer = AIChatAnswer(text: "", status: .thinking)
        }
        if !live.streaming.isEmpty {
            answer.text = answer.text.isEmpty ? live.streaming : answer.text + "\n\n" + live.streaming
        }
        if let job = live.job {
            let steps = job.steps.filter { !JobSteps.isHidden($0.tool) }
            let thoughts = steps.filter { $0.tool == JobSteps.Thinking.tool }
            answer.thinking = thoughts.map(\.label).joined(separator: "\n")
            answer.run = ChatAgentRun.joined(parent, ChatAgentRun.live(job, now: live.now))
            if let last = thoughts.last {
                answer.thoughtFor = max(Int((last.finishedAt ?? live.now).timeIntervalSince(job.startedAt).rounded()), 1)
            }
        }
        // Arc's rule: the first tool, run or word ends the thinking phase.
        answer.status = answer.text.isEmpty && answer.run == nil ? .thinking : .streaming
        turns.append(AIChatTurn(id: id, content: .assistant(answer)))
    }

    /// Drops the "Sources"/"Fuentes" header and the link lines under it, the
    /// same section `MarkdownSplitter.extractSources` reads them from.
    static func removingSourcesSection(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: isSourcesHeader) else { return text }
        var end = start + 1
        while end < lines.count {
            let line = lines[end].trimmingCharacters(in: .whitespaces)
            let isItem = line.hasPrefix("-") || line.hasPrefix("*") || line.first?.isNumber == true
            guard line.isEmpty || isItem || line.contains("http") else { break }
            end += 1
        }
        lines.removeSubrange(start..<end)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSourcesHeader(_ line: String) -> Bool {
        let clean = line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":*"))
            .lowercased()
        return ["sources", "fuentes", "referencias"].contains(clean)
    }
}
