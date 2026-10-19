import CompanionCore
@testable import CompanionUI
import CompanionUIPro
import Foundation
import Testing

@MainActor
struct ChatTurnsTests {
    private func answer(_ turn: AIChatTurn) -> AIChatAnswer? { turn.answer }

    /// A preface, the parent's tool call, its result line and the reply are
    /// one answer: the call becomes one step of its run, named by its result.
    @Test func toolCallAndResultBecomeOneStep() {
        let call = ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Safari"}"#)
        let messages = [
            ChatMessage(role: .user, text: "Abre Safari"),
            ChatMessage(isStatus: true, text: "Abriendo Safari…",
                        recall: Recall(role: .assistant, content: "", toolCalls: [call])),
            ChatMessage(isStatus: true, text: "Abrí Safari.",
                        recall: Recall(role: .tool, content: "ok", toolCallID: "c1")),
            ChatMessage(role: .assistant, text: "Listo, Safari está abierto."),
        ]
        let turns = ChatTurns.thread(messages).turns
        #expect(turns.count == 2)
        let reply = try? #require(turns.last?.answer)
        #expect(reply?.text == "Listo, Safari está abierto.")
        #expect(reply?.status == .done)
        #expect(reply?.tools.isEmpty == true, "tool calls are the run's steps, not chips")
        #expect(reply?.run?.steps.map(\.status) == [.done])
        #expect(reply?.run?.steps.first?.title == "Abrí Safari.")
        #expect(reply?.run?.worked == Localized.string("chat.run.failures.none"))
    }

    /// A tool result the app marked failed is a failed step, never a done
    /// one: a green check under "Navegador: ..." told the user it had worked.
    @Test func failedToolResultIsAFailedStep() {
        let call = ToolCallRef(id: "c1", name: "browser_type", arguments: "{}")
        let messages = [
            ChatMessage(role: .user, text: "Escribe en la página"),
            ChatMessage(isStatus: true, text: "Escribiendo…",
                        recall: Recall(role: .assistant, content: "", toolCalls: [call])),
            ChatMessage(isStatus: true, text: "Navegador: La llamada tenía argumentos inválidos.",
                        recall: Recall(role: .tool, content: "invalid", toolCallID: "c1"), stepFailed: true),
            ChatMessage(role: .assistant, text: "No pude escribir."),
        ]
        let run = ChatTurns.thread(messages).turns.last?.answer?.run
        #expect(run?.steps.map(\.status) == [.failed])
        #expect(run?.steps.first?.title == "Navegador: La llamada tenía argumentos inválidos.")
        #expect(run?.phase == .done, "an answered turn keeps its header; the failure stays on the step")
        let noAnswer = ChatTurns.thread([
            ChatMessage(role: .user, text: "Escribe"),
            ChatMessage(isStatus: true, text: "Escribiendo…",
                        recall: Recall(role: .assistant, content: "", toolCalls: [ToolCallRef(id: "c1", name: "browser_type", arguments: "{}")])),
            ChatMessage(isStatus: true, text: "Navegador: falló.",
                        recall: Recall(role: .tool, content: "x", toolCallID: "c1"), stepFailed: true),
            ChatMessage(isStatus: true, text: "El proveedor falló.", isFailure: true),
        ]).turns.last?.answer?.run
        #expect(noAnswer?.phase == .failed, "a turn that failed without an answer fails its header")
        #expect(run?.worked == Localized.string("chat.run.failures.one"))
    }

    /// The reply's "Fuentes" list leaves the prose and becomes citations.
    @Test func sourcesSectionBecomesCitations() {
        let text = """
        | Ciudad | Vuelos |
        |---|---|
        | Lima | 3 |

        Fuentes:
        - [Kayak](https://www.kayak.com/lima) precios del día
        - [LATAM](https://latam.com)
        """
        let messages = [ChatMessage(role: .user, text: "Vuelos"), ChatMessage(role: .assistant, text: text)]
        let reply = ChatTurns.thread(messages).turns.last?.answer
        #expect(reply?.sources.map(\.domain) == ["kayak.com", "latam.com"])
        #expect(reply?.sources.first?.snippet == "precios del día")
        #expect(reply?.text.contains("Fuentes") == false)
        #expect(reply?.text.contains("| Lima | 3 |") == true)
    }

    /// While the turn runs, the streamed words and the specialist's steps
    /// are the answer; thoughts become the reasoning fold.
    @Test func liveTurnStreamsWithStepsAndThoughts() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let job = JobTimeline(goal: "vuelos", startedAt: start, steps: [
            JobStepInfo(tool: JobSteps.Thinking.tool, label: "Busco precios", done: true, id: "t",
                        startedAt: start, finishedAt: start.addingTimeInterval(3)),
            JobStepInfo(tool: "WebSearch", label: "WebSearch: vuelos a Lima", id: "s1", startedAt: start),
            JobStepInfo(tool: "ToolSearch", label: "ToolSearch", id: "h", startedAt: start),
        ])
        let live = ChatLive(streaming: "", busy: true, job: job, now: start.addingTimeInterval(5))
        let turns = ChatTurns.thread([ChatMessage(role: .user, text: "Vuelos")], live: live).turns
        let reply = turns.last?.answer
        #expect(turns.last?.id == ChatTurns.liveID)
        #expect(reply?.status == .streaming, "a run on screen ends the thinking phase")
        #expect(reply?.thinking == "Busco precios")
        #expect(reply?.thoughtFor == 3)
        #expect(reply?.tools.isEmpty == true, "the specialist's steps are the run, not chips")
        #expect(reply?.run?.phase == .running)
        #expect(reply?.run?.worked == String(format: Localized.string("chat.run.worked"), "5s"))
        #expect(reply?.run?.steps.map(\.status) == [.active], "thoughts and bookkeeping stay off the rail")
        let words = ChatTurns.thread(
            [ChatMessage(role: .user, text: "Vuelos")],
            live: ChatLive(streaming: "Hay tres", busy: true, job: nil, now: start)).turns.last?.answer
        #expect(words?.text == "Hay tres")
        #expect(words?.status == .streaming)
        let waiting = ChatTurns.thread(
            [ChatMessage(role: .user, text: "Vuelos")],
            live: ChatLive(streaming: "", busy: true, job: nil, now: start)).turns.last?.answer
        #expect(waiting?.status == .thinking)
    }

    /// The job's record line keeps its run: once the live timeline is gone
    /// the answer folds it into its summary, with how the job ended.
    @Test func finishedJobStaysOnItsAnswer() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let job = JobTimeline(goal: "vuelos", startedAt: start, steps: [
            JobStepInfo(tool: "WebSearch", label: "WebSearch: vuelos a Lima", done: true, id: "s1",
                        startedAt: start, finishedAt: start.addingTimeInterval(4)),
            JobStepInfo(tool: "WebFetch", label: "WebFetch: kayak.com", id: "s2", startedAt: start.addingTimeInterval(4)),
        ])
        let end = start.addingTimeInterval(9)
        func reply(_ outcome: JobRecord.Outcome) -> AIChatAnswer? {
            ChatTurns.thread([
                ChatMessage(role: .user, text: "Vuelos"),
                ChatMessage(isStatus: true, text: "Encargo: vuelos",
                            job: JobRecord(timeline: job, finishedAt: end, outcome: outcome)),
                ChatMessage(role: .assistant, text: "Hay tres."),
            ]).turns.last?.answer
        }
        let done = reply(.done)
        #expect(done?.run?.phase == .done)
        #expect(done?.run?.worked == String(format: Localized.string("chat.run.worked"), "9s"))
        #expect(done?.run?.steps.map(\.status) == [.done, .done])
        #expect(done?.run?.steps.map(\.duration) == ["4s", "5s"])
        let stopped = reply(.stopped)
        #expect(stopped?.run?.phase == .stopped)
        #expect(stopped?.run?.steps.map(\.status) == [.done, .failed], "a step cut off by the stop did not finish")
    }

    /// A step's detail is its own line only when that says more than its
    /// title; a bare tool step has nothing to unfold.
    @Test func stepDetailOnlyWhenItAddsSomething() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let steps = ChatAgentRun.steps([
            JobStepInfo(tool: "Bash", label: "Bash: ls -la ~/Desktop", done: true, id: "b",
                        startedAt: start, finishedAt: start),
            JobStepInfo(tool: "mcp__x__y", label: "mcp__x__y: select:a,b", done: true, id: "m",
                        startedAt: start, finishedAt: start),
        ], now: start, language: .en)
        #expect(steps.first?.detail == nil, "the title already names the command")
        #expect(steps.last?.title == "Worked on a step")
        #expect(steps.last?.detail == "mcp__x__y: select:a,b")
    }

    /// The notch card summarises the newest turn's job, never an older one.
    @Test func latestRecordIsTheNewestTurns() {
        let record = JobRecord(timeline: JobTimeline(goal: "a"), finishedAt: .distantPast, outcome: .done)
        let older = [ChatMessage(role: .user, text: "Uno"), ChatMessage(isStatus: true, text: "Encargo: a", job: record)]
        #expect(ChatAgentRun.latestRecord(older) == record)
        #expect(ChatAgentRun.latestRecord(older + [ChatMessage(role: .user, text: "Dos")]) == nil)
    }

    /// A call whose result never arrived does not read as done once its turn
    /// is over; a failed turn shows its own words.
    @Test func settledTurnClosesToolsAndKeepsFailure() {
        let call = ToolCallRef(id: "c1", name: "open_url", arguments: "{}")
        let messages = [
            ChatMessage(role: .user, text: "Abre la web"),
            ChatMessage(isStatus: true, text: "Actuando…", recall: Recall(role: .assistant, content: "", toolCalls: [call])),
            ChatMessage(isStatus: true, text: "El proveedor falló.", isFailure: true),
        ]
        let reply = ChatTurns.thread(messages).turns.last?.answer
        #expect(reply?.run?.steps.map(\.status) == [.failed], "a call that never answered did not finish")
        #expect(reply?.status == .error)
        #expect(reply?.errorNote == "El proveedor falló.")
    }

    /// Cards painted from the tool channel ride under their answer.
    @Test func channelCardsAttachToTheirTurn() throws {
        let card = Card(payload: .stats(StatsBlock(title: nil, items: [])), source: .model)
        let messages = [
            ChatMessage(role: .user, text: "Stats"),
            ChatMessage(role: .assistant, text: "", card: card),
        ]
        let thread = ChatTurns.thread(messages)
        let id = try #require(thread.turns.last?.id)
        #expect(thread.cards[id] == [card])
    }
}

@MainActor
struct ConversationRouteTests {
    /// "Seguir en el chat" opens the island's conversation: its saved entry
    /// when there is one, a fresh one named by the question otherwise, and
    /// nothing (Home) when there is nothing to read.
    @Test func continueInChatOpensTheCurrentConversation() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let saved = ConversationMeta(id: "a", title: "Vuelos a Lima", updatedAt: now)
        let messages = [ChatMessage(role: .user, text: "¿Cuánto cuesta volar a Lima?")]
        #expect(ConversationRoute.current(id: "a", recents: [saved], messages: messages, now: now, fallbackTitle: "x") == saved)
        let fresh = ConversationRoute.current(id: "b", recents: [saved], messages: messages, now: now, fallbackTitle: "x")
        #expect(fresh?.id == "b")
        #expect(fresh?.title == "¿Cuánto cuesta volar a Lima?")
        #expect(ConversationRoute.current(
            id: "c", recents: [], messages: [ChatMessage(isStatus: true, text: "…")], now: now, fallbackTitle: "x") == nil)
    }
}
