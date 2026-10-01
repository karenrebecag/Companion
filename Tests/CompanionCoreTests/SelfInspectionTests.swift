import CompanionCore
import Foundation
import Testing

private let sentinel = "SENTINEL-7f3a-ZXQ"

private func encoded<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func user(_ text: String, status: Bool = false) -> ThreadMessageInput {
    ThreadMessageInput(role: .user, isStatus: status, origin: .typed, isFailure: false,
                       restored: false, attachments: 0, text: text)
}

private func assistant(_ text: String) -> ThreadMessageInput {
    ThreadMessageInput(role: .assistant, isStatus: false, origin: .typed, isFailure: false,
                       restored: false, attachments: 0, text: text)
}

@Suite struct SelfInspectionTests {
    // MARK: Tool specs

    @Test func companionToolWireNamesAreStableInBothLanguages() {
        let names = CompanionTool.allCases.map(\.rawValue)
        #expect(names == [
            "companion_state", "companion_island", "companion_settings",
            "companion_thread", "companion_last_message_matches", "companion_log",
        ])
        for language in AppLanguage.allCases {
            #expect(CompanionTool.allCases.map { $0.spec(language).name } == names)
        }
    }

    @Test func everyCompanionToolDescriptionEndsWithDataSuffix() {
        for language in AppLanguage.allCases {
            for tool in CompanionTool.allCases {
                #expect(tool.spec(language).description.hasSuffix(BridgeCopy.toolDataSuffix(language)))
            }
        }
        #expect(CompanionTool.state.spec(.en).description != CompanionTool.state.spec(.es).description)
    }

    @Test func logAndMatchToolsDeclareTheirArguments() {
        let log = CompanionTool.log.spec(.en)
        #expect(log.properties.map(\.name) == ["lines"])
        #expect(log.properties.first?.type == "integer")
        #expect(log.required.isEmpty)
        let match = CompanionTool.lastMessageMatches.spec(.en)
        #expect(match.properties.map(\.name) == ["expected"])
        #expect(match.required == ["expected"])
    }

    // MARK: Session

    @Test func sessionInspectionNamesApprovalToolButNeverSummaryOrInput() throws {
        var p = SessionProjection()
        p.approvalQueue = [
            ApprovalRequest(requestId: "r1", toolName: "Write", summary: sentinel,
                            inputJSON: "{\"p\":\"\(sentinel)\"}", isMCP: true),
            ApprovalRequest(requestId: "r2", toolName: "Bash", summary: sentinel, inputJSON: sentinel),
        ]
        let out = SessionInspection(p)
        #expect(out.approvalToolName == "Write")
        #expect(out.approvalIsMCP == true)
        #expect(out.approvalQueueSize == 2)
        #expect(!(try encoded(out)).contains(sentinel))
    }

    @Test func sessionInspectionJobGoalAndTargetsAreCountsOnly() throws {
        var p = SessionProjection()
        p.kind = .processing(.subAgentRunning)
        p.job = JobTimeline(goal: sentinel, steps: [
            JobStepInfo(tool: "Read", label: sentinel), JobStepInfo(tool: "Write", label: sentinel),
        ])
        p.queued = [JobTimeline(goal: sentinel)]
        p.targets = [sentinel, "Safari"]
        p.touched = [sentinel]
        p.partial = sentinel
        p.dictation = sentinel
        p.dictatedText = DictatedText(sentinel)
        p.handsLentTo = "claude-code"
        p.handsActing = true
        let out = SessionInspection(p)
        #expect(out.kind == "processing")
        #expect(out.phase == "subAgentRunning")
        #expect(out.jobActive)
        #expect(out.jobSteps == 2)
        #expect(out.jobGoalLength == sentinel.count)
        #expect(out.queuedJobs == 1)
        #expect(out.targetCount == 2)
        #expect(out.dictating)
        #expect(out.handsLentTo == "claude-code")
        #expect(out.handsActing)
        #expect(!(try encoded(out)).contains(sentinel))
    }

    @Test func sessionInspectionNamesNoticeCardsAndInterruptionCases() throws {
        var p = SessionProjection()
        p.notice = .replyCut
        p.cards = [.holdHint, .failure(.networkUnavailable)]
        p.interruption = .failure(.micDenied)
        p.voice = .live
        p.pipeline = .realtime
        let out = SessionInspection(p)
        #expect(out.notice == "replyCut")
        #expect(out.cards == ["holdHint", "failure"])
        #expect(out.interruption == "failure")
        #expect(out.voice == "live")
        #expect(out.pipeline == "realtime")
        #expect(out.kind == "idle")
        #expect(out.phase == nil)
    }

    // MARK: Island

    private func allLines() -> [IslandState.Line] {
        let receipt = ActionReceipt(lines: [sentinel])!
        return [
            .none, .holdHint, .keyBlocked, .pending, .thinking, .acting([sentinel]), .speaking,
            .job(goal: sentinel, step: sentinel, steps: 3), .completed, .couldntHear,
            .permission(.micDenied), .failure(.quotaExceeded), .dictating(sentinel), .pasting,
            .dictated(sentinel), .dictationResult(app: sentinel, text: DictatedText(sentinel)),
            .updateAvailable(tag: sentinel), .transcriptsDebug, .cancelled, .followUp(sentinel),
            .dropZones, .connectApp(slug: sentinel, name: sentinel),
            .signInApp(slug: sentinel, name: sentinel), .chatError(sentinel),
            .receipt(receipt), .replyCut,
        ]
    }

    @Test func islandInspectionNamesEveryLineCase() {
        let names = allLines().map { IslandInspection(PaintedIsland(state: IslandState(size: .bar, line: $0), catalogText: nil)).line }
        #expect(names == [
            "none", "holdHint", "keyBlocked", "pending", "thinking", "acting", "speaking",
            "job", "completed", "couldntHear", "permission", "failure", "dictating", "pasting",
            "dictated", "dictationResult", "updateAvailable", "transcriptsDebug", "cancelled",
            "followUp", "dropZones", "connectApp", "signInApp", "chatError", "receipt", "replyCut",
        ])
        #expect(Set(names).count == names.count)
    }

    @Test func islandAssociatedTextBecomesLength() throws {
        let n = sentinel.count
        func lengths(_ line: IslandState.Line) -> [Int] {
            IslandInspection(PaintedIsland(state: IslandState(size: .bar, line: line), catalogText: nil)).textLengths
        }
        #expect(lengths(.acting([sentinel, "ab"])) == [n, 2])
        #expect(lengths(.job(goal: sentinel, step: nil, steps: 1)) == [n])
        #expect(lengths(.dictationResult(app: "Notes", text: DictatedText(sentinel))) == [5, n])
        #expect(lengths(.connectApp(slug: "gh", name: sentinel)) == [2, n])
        #expect(lengths(.chatError(sentinel)) == [n])
        #expect(lengths(.thinking) == [])
        for line in allLines() {
            let painted = PaintedIsland(state: IslandState(size: .bar, line: line), catalogText: nil)
            #expect(!(try encoded(IslandInspection(painted))).contains(sentinel))
        }
    }

    @Test func islandInspectionDropsApprovalSummaryAndPartial() throws {
        var state = IslandState(size: .card)
        state.light = .amber
        state.approval = ApprovalRequest(requestId: "r", toolName: "Bash", summary: sentinel, inputJSON: sentinel)
        state.partial = sentinel
        state.hands = "claude-code"
        state.showsStop = true
        state.action = .stopHands
        let out = IslandInspection(PaintedIsland(state: state, catalogText: nil))
        #expect(out.approvalToolName == "Bash")
        #expect(out.partialLength == sentinel.count)
        #expect(out.hands == "claude-code")
        #expect(out.showsStop)
        #expect(out.light == "amber")
        #expect(out.action == "stopHands")
        #expect(out.size == "card")
        #expect(out.meter == "none")
        #expect(!(try encoded(out)).contains(sentinel))
    }

    @Test func islandCatalogTextOnlyForLinesWithoutText() {
        for line in allLines() {
            let painted = PaintedIsland(state: IslandState(size: .bar, line: line), catalogText: "catalog")
            let out = IslandInspection(painted)
            #expect((out.catalogText != nil) == !line.carriesText)
        }
        #expect(IslandState.Line.thinking.carriesText == false)
        #expect(IslandState.Line.failure(.micDenied).carriesText == false)
        #expect(IslandState.Line.followUp("x").carriesText)
    }

    // MARK: Settings

    private func settings(
        name: String = "", about: String = "", instructions: String = "", city: String = ""
    ) -> SettingsInspection {
        SettingsInspection(
            languageStored: nil, languageEffective: "es", appearance: "dark", voice: "marin",
            volume: 0.5, voiceMode: "automatic", dictationKey: .rightOption,
            interfaceSounds: true, thinkingSound: false, decision: true, handsLending: true,
            providerOrder: ["openai", "ollama"], ownerName: name, about: about,
            instructions: instructions, city: city, vocabularyWords: 4)
    }

    @Test func settingsInspectionFreeTextIsLengthOnly() throws {
        let out = settings(name: sentinel, about: sentinel, instructions: sentinel + sentinel, city: "CDMX")
        #expect(out.ownerNameLength == sentinel.count)
        #expect(out.aboutLength == sentinel.count)
        #expect(out.instructionsLength == sentinel.count * 2)
        #expect(out.cityLength == 4)
        #expect(out.vocabularyWords == 4)
        #expect(!(try encoded(out)).contains(sentinel))
    }

    @Test func settingsInspectionHasNoSecretField() throws {
        let json = try encoded(settings())
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(Set(object.keys) == [
            "languageEffective", "appearance", "voice", "volume", "voiceMode", "dictationKey",
            "interfaceSounds", "thinkingSound", "decision", "handsLending", "providerOrder",
            "ownerNameLength", "aboutLength", "instructionsLength", "cityLength", "vocabularyWords",
        ])
        #expect(object["dictationKey"] as? String == "rightOption")
        for forbidden in ["key", "token", "secret", "keychain"] {
            #expect(!object.keys.contains { $0.lowercased() == forbidden })
        }
    }

    @Test func settingsInspectionKeepsStoredLanguageWhenSet() throws {
        let stored = SettingsInspection(
            languageStored: "en", languageEffective: "en", appearance: "light", voice: "v",
            volume: 1, voiceMode: "m", dictationKey: .off, interfaceSounds: false,
            thinkingSound: false, decision: false, handsLending: false, providerOrder: [],
            ownerName: "", about: "", instructions: "", city: "", vocabularyWords: 0)
        #expect(stored.languageStored == "en")
        #expect(try encoded(stored).contains("\"languageStored\":\"en\""))
    }

    // MARK: Thread

    @Test func threadInputTypeIsNotEncodable() {
        #expect(!(ThreadMessageInput.self is Encodable.Type))
    }

    @Test func threadInputDescriptionIsRedacted() {
        let input = user(sentinel)
        #expect(!input.description.contains(sentinel))
        #expect(!"\(input)".contains(sentinel))
        #expect(!String(reflecting: input).contains(sentinel))
        var dumped = ""
        dump(input, to: &dumped)
        #expect(!dumped.contains(sentinel))
    }

    @Test func messageInspectionCarriesRoleOriginFlagsAndLength() throws {
        let input = ThreadMessageInput(
            role: .user, isStatus: false, origin: .choice, isFailure: true, restored: true,
            attachments: 2, text: sentinel)
        let out = MessageInspection(input, detected: DetectedLanguage(code: "es", confidence: 0.91))
        #expect(out.role == "user")
        #expect(out.origin == "choice")
        #expect(out.isFailure)
        #expect(out.restored)
        #expect(out.attachments == 2)
        #expect(out.length == sentinel.count)
        #expect(out.language == "es")
        #expect(out.confidence == 0.91)
        #expect(!(try encoded(out)).contains(sentinel))
        let bare = MessageInspection(user("hola"), detected: nil)
        #expect(bare.language == nil)
        #expect(bare.confidence == nil)
    }

    // MARK: Equality oracle

    @Test func lastMessageMatchTrimsButIsCaseSensitive() {
        let thread = [user("  Hola mundo \n")]
        #expect(LastMessageMatch.matches("Hola mundo", in: thread))
        #expect(LastMessageMatch.matches("\nHola mundo  ", in: thread))
        #expect(!LastMessageMatch.matches("hola mundo", in: thread))
        #expect(!LastMessageMatch.matches("Hola  mundo", in: thread))
    }

    @Test func lastMessageMatchUsesCanonicalEquivalence() {
        let thread = [user("caf\u{00E9}")]
        #expect(LastMessageMatch.matches("cafe\u{0301}", in: thread))
    }

    @Test func lastMessageMatchOnlyAgainstLastUserMessage() {
        let thread = [user("primero"), user("segundo"), assistant("segundo"), user("   ", status: true)]
        #expect(LastMessageMatch.matches("segundo", in: thread))
        #expect(!LastMessageMatch.matches("primero", in: thread))
        #expect(!LastMessageMatch.matches("segundo respuesta", in: thread))
        #expect(!LastMessageMatch.matches("", in: thread))
    }

    @Test func lastMessageMatchWithNoUserMessageIsFalse() {
        #expect(!LastMessageMatch.matches("x", in: []))
        #expect(!LastMessageMatch.matches("x", in: [assistant("x")]))
        #expect(!LastMessageMatch.matches("", in: []))
    }

    @Test func lastMessageMatchRefusesOversizeExpected() {
        let big = String(repeating: "a", count: LastMessageMatch.maxExpectedScalars + 1)
        #expect(!LastMessageMatch.matches(big, in: [user(big)]))
        let ok = String(repeating: "a", count: LastMessageMatch.maxExpectedScalars)
        #expect(LastMessageMatch.matches(ok, in: [user(ok)]))
    }

    @Test func equalityLimitAdmitsTenPerMinuteThenRefuses() {
        var limit = EqualityCheckLimit()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<EqualityCheckLimit.perMinute {
            let admitted = limit.admit(now: t0.addingTimeInterval(Double(i)))
            #expect(admitted)
        }
        #expect(EqualityCheckLimit.perMinute == 10)
        let refused = limit.admit(now: t0.addingTimeInterval(30))
        #expect(!refused)
        // The refused try is not recorded: the window slides on the admitted ones.
        let reopened = limit.admit(now: t0.addingTimeInterval(61))
        #expect(reopened)
    }

    // MARK: Sentinel sweep

    @Test func encodedOutputsNeverContainSentinel() throws {
        var p = SessionProjection()
        p.kind = .processing(.subAgentRunning)
        p.job = JobTimeline(goal: sentinel, steps: [JobStepInfo(tool: "t", label: sentinel)])
        p.approvalQueue = [ApprovalRequest(requestId: "r", toolName: "Bash", summary: sentinel, inputJSON: sentinel)]
        p.targets = [sentinel]
        p.partial = sentinel
        p.dictation = sentinel
        p.dictatedText = DictatedText(sentinel)
        p.notice = .receipt(ActionReceipt(lines: [sentinel])!)
        let island = IslandState.from(p, pebbleHidden: false, followUp: sentinel, errorText: sentinel)
        let outputs = try [
            encoded(SessionInspection(p)),
            encoded(IslandInspection(PaintedIsland(state: island, catalogText: "ok"))),
            encoded(settings(name: sentinel, about: sentinel, instructions: sentinel, city: sentinel)),
            encoded(MessageInspection(user(sentinel), detected: DetectedLanguage(code: "en", confidence: 0.5))),
        ]
        for output in outputs { #expect(!output.contains(sentinel)) }
    }
}

// MARK: Review round: oracle, carriesText, sweep, limiter

private let sentinelNeedle = String(sentinel.prefix(6)).lowercased()

private func leaks(_ output: String) -> Bool {
    output.lowercased().contains(sentinelNeedle)
}

private func keys<T: Encodable>(of value: T) throws -> Set<String> {
    let data = Data(try encoded(value).utf8)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return Set(object.keys)
}

/// Exhaustive on purpose: a new Line case stops compiling here until the
/// fixtures below are extended.
private func lineIndex(_ line: IslandState.Line) -> Int {
    switch line {
    case .none: 0
    case .holdHint: 1
    case .keyBlocked: 2
    case .pending: 3
    case .thinking: 4
    case .acting: 5
    case .speaking: 6
    case .job: 7
    case .completed: 8
    case .couldntHear: 9
    case .permission: 10
    case .failure: 11
    case .dictating: 12
    case .pasting: 13
    case .dictated: 14
    case .dictationResult: 15
    case .updateAvailable: 16
    case .transcriptsDebug: 17
    case .cancelled: 18
    case .followUp: 19
    case .dropZones: 20
    case .connectApp: 21
    case .signInApp: 22
    case .chatError: 23
    case .receipt: 24
    case .replyCut: 25
    }
}

private func state(_ line: IslandState.Line) -> IslandState {
    IslandState(size: .bar, line: line)
}

extension SelfInspectionTests {
    @Test func allLinesCoversEveryCaseOnce() {
        #expect(allLines().map(lineIndex) == Array(0..<26))
    }

    // MARK: Oracle role and empty probe

    @Test func lastMessageMatchPicksUserOverTrailingAssistant() {
        let thread = [user("a"), assistant("b")]
        #expect(LastMessageMatch.matches("a", in: thread))
        #expect(!LastMessageMatch.matches("b", in: thread))
    }

    @Test func lastMessageMatchSkipsNilRoleMessages() {
        let nilRole = ThreadMessageInput(
            role: nil, isStatus: false, origin: .typed, isFailure: false, restored: false,
            attachments: 0, text: "ghost")
        let thread = [user("a"), nilRole]
        #expect(LastMessageMatch.matches("a", in: thread))
        #expect(!LastMessageMatch.matches("ghost", in: thread))
        #expect(!LastMessageMatch.matches("ghost", in: [nilRole]))
    }

    @Test func emptyOrBlankProbeNeverMatchesBlankMessage() {
        for message in ["", "  "] {
            for probe in ["", "   \n"] {
                #expect(!LastMessageMatch.matches(probe, in: [user(message)]))
            }
        }
        #expect(!LastMessageMatch.matches("x", in: [user("   ")]))
    }

    @Test func oversizeIsCountedInScalarsNotCharacters() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let big = String(repeating: family, count: 401)
        #expect(big.count == 401)
        #expect(big.unicodeScalars.count > LastMessageMatch.maxExpectedScalars)
        #expect(!LastMessageMatch.matches(big, in: [user(big)]))
    }

    // MARK: carriesText is not its own oracle

    @Test func textCarryingLineSetIsPinned() {
        let carrying = allLines().filter(\.carriesText).map { inspectionName($0) }
        #expect(carrying == [
            "acting", "job", "dictating", "dictated", "dictationResult", "updateAvailable",
            "followUp", "connectApp", "signInApp", "chatError", "receipt",
        ])
        #expect(carrying.count == 11)
    }

    private func inspectionName(_ line: IslandState.Line) -> String {
        IslandInspection(PaintedIsland(state: state(line), catalogText: nil)).line
    }

    @Test func catalogSentinelNeverSurfacesForTextCarryingLines() throws {
        for line in allLines() {
            let out = IslandInspection(PaintedIsland(state: state(line), catalogText: sentinel))
            if line.carriesText {
                #expect(out.catalogText == nil)
                #expect(!leaks(try encoded(out)), "\(inspectionName(line))")
            } else {
                #expect(out.catalogText == sentinel)
            }
        }
    }

    @Test func islandTextLengthTableCoversAllTwentySixLines() {
        let n = sentinel.count
        let expected: [[Int]] = [
            [], [], [], [], [], [n], [], [n, n], [], [], [], [], [n], [], [n], [n, n], [n], [], [],
            [n], [], [n, n], [n, n], [n], [n], [],
        ]
        let actual = allLines().map {
            IslandInspection(PaintedIsland(state: state($0), catalogText: nil)).textLengths
        }
        #expect(expected.count == 26)
        #expect(actual == expected)
    }

    // MARK: Sentinel sweep

    @Test func idleOnlyLinesAreSweptThroughIslandFrom() throws {
        let p = SessionProjection()
        let followUp = IslandState.from(p, pebbleHidden: false, followUp: sentinel)
        let chatError = IslandState.from(p, pebbleHidden: false, errorText: sentinel)
        let update = IslandState.from(p, pebbleHidden: false, update: sentinel)
        #expect(IslandInspection(PaintedIsland(state: followUp, catalogText: sentinel)).line == "followUp")
        #expect(IslandInspection(PaintedIsland(state: chatError, catalogText: sentinel)).line == "chatError")
        #expect(IslandInspection(PaintedIsland(state: update, catalogText: sentinel)).line == "updateAvailable")
        for s in [followUp, chatError, update] {
            #expect(!leaks(try encoded(IslandInspection(PaintedIsland(state: s, catalogText: sentinel)))))
        }
    }

    @Test func everyUserStringSeededAcrossSessionAndIslandStaysOut() throws {
        var p = SessionProjection()
        p.kind = .processing(.subAgentRunning)
        p.job = JobTimeline(goal: sentinel, steps: [JobStepInfo(tool: sentinel, label: sentinel)])
        p.queued = [JobTimeline(goal: sentinel)]
        p.targets = [sentinel]
        p.touched = [sentinel]
        p.partial = sentinel
        p.dictation = sentinel
        p.dictatedText = DictatedText(sentinel)
        p.approvalQueue = [ApprovalRequest(requestId: sentinel, toolName: "Bash", summary: sentinel, inputJSON: sentinel)]
        p.cards = [
            .connectApp(slug: sentinel, name: sentinel), .signInApp(slug: sentinel, name: sentinel),
            .approval(p.approvalQueue[0]), .approvalAnswered(tool: sentinel, approved: true, remembered: false),
            .receipt(ActionReceipt(lines: [sentinel])!),
            .answer(Card(payload: .locations(LocationsBlock(title: sentinel, locations: [
                .init(id: sentinel, name: sentinel, eyebrow: sentinel, address: sentinel,
                      lat: 1, lng: 2, url: sentinel),
            ])), source: .tool)),
            .answer(Card(payload: .table(TableBlock(
                title: sentinel, columns: [sentinel], rows: [[sentinel]])), source: .tool)),
            .answer(Card(payload: .stats(StatsBlock(title: sentinel, items: [
                .init(label: sentinel, value: sentinel, delta: sentinel),
            ])), source: .tool)),
        ]
        p.notice = .connectApp(slug: sentinel, name: sentinel)
        p.interruption = .failure(.micDenied)
        let island = IslandState.from(p, pebbleHidden: false)
        var withLine = island
        for line in allLines() {
            withLine.line = line
            // catalogText is copy and is covered by its own test; here only user strings.
            #expect(!leaks(try encoded(IslandInspection(PaintedIsland(state: withLine, catalogText: nil)))))
        }
        #expect(SessionInspection(p).cards.filter { $0 == "answer" }.count == 3)
        #expect(!leaks(try encoded(SessionInspection(p))))
        #expect(!leaks(try encoded(MessageInspection(user(sentinel), detected: nil))))
        #expect(!leaks(try encoded(settings(name: sentinel, about: sentinel, instructions: sentinel, city: sentinel))))
    }

    /// Agent-declared names and closed-set labels are echoed on purpose. The
    /// UI source must feed enum raw values into the label fields (PR-4).
    @Test func intentionallyEchoedNamesAreTheOnlyStringsThatPassThrough() throws {
        var p = SessionProjection()
        p.handsLentTo = sentinel
        p.approvalQueue = [ApprovalRequest(requestId: "r", toolName: sentinel, summary: "s", inputJSON: "{}")]
        #expect(SessionInspection(p).handsLentTo == sentinel)
        #expect(SessionInspection(p).approvalToolName == sentinel)
        var s = IslandState(size: .nudge)
        s.hands = sentinel
        #expect(IslandInspection(PaintedIsland(state: s, catalogText: nil)).hands == sentinel)
        let labels = SettingsInspection(
            languageStored: sentinel, languageEffective: sentinel, appearance: sentinel,
            voice: sentinel, volume: 1, voiceMode: sentinel, dictationKey: .off,
            interfaceSounds: false, thinkingSound: false, decision: false, handsLending: false,
            providerOrder: [sentinel], ownerName: "", about: "", instructions: "", city: "",
            vocabularyWords: 0)
        #expect(labels.voice == sentinel && labels.providerOrder == [sentinel])
        let screen = InspectedScreen(settingsOpen: true, settingsTab: sentinel, page: sentinel)
        #expect(screen.settingsTab == sentinel && screen.page == sentinel)
    }

    @Test func encodableOutputKeySetsArePinnedExactly() throws {
        var p = SessionProjection()
        p.kind = .processing(.thinking)
        p.pipeline = .classic
        p.approvalQueue = [ApprovalRequest(requestId: "r", toolName: "Bash", summary: "s", inputJSON: "{}")]
        p.notice = .replyCut
        p.interruption = .userStopped
        p.handsLentTo = "agent"
        #expect(try keys(of: SessionInspection(p)) == [
            "kind", "phase", "voice", "pipeline", "holding", "dictating", "jobActive", "jobSteps",
            "jobGoalLength", "queuedJobs", "approvalToolName", "approvalIsMCP", "approvalQueueSize",
            "notice", "cards", "interruption", "targetCount", "handsLentTo", "handsActing", "hasReceipt",
        ])
        var s = IslandState(size: .card, line: .thinking)
        s.approval = p.approvalQueue[0]
        s.hands = "agent"
        s.action = .stopHands
        #expect(try keys(of: IslandInspection(PaintedIsland(state: s, catalogText: "c"))) == [
            "size", "meter", "line", "textLengths", "catalogText", "light", "action", "showsStop",
            "approvalToolName", "hands", "hasReceipt", "partialLength",
        ])
        let stored = SettingsInspection(
            languageStored: "en", languageEffective: "en", appearance: "a", voice: "v", volume: 1,
            voiceMode: "m", dictationKey: .off, interfaceSounds: false, thinkingSound: false,
            decision: false, handsLending: false, providerOrder: [], ownerName: "", about: "",
            instructions: "", city: "", vocabularyWords: 0)
        #expect(try keys(of: stored) == [
            "languageStored", "languageEffective", "appearance", "voice", "volume", "voiceMode",
            "dictationKey", "interfaceSounds", "thinkingSound", "decision", "handsLending",
            "providerOrder", "ownerNameLength", "aboutLength", "instructionsLength", "cityLength",
            "vocabularyWords",
        ])
        #expect(try keys(of: MessageInspection(user("x"), detected: DetectedLanguage(code: "es", confidence: 1))) == [
            "role", "origin", "isStatus", "isFailure", "restored", "attachments", "length",
            "language", "confidence",
        ])
        #expect(try keys(of: InspectedScreen(settingsOpen: true, settingsTab: "t", page: "p")) == [
            "settingsOpen", "settingsTab", "page",
        ])
    }

    // MARK: Limiter

    @Test func limiterWindowSlidesOnAdmittedEntries() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var limit = EqualityCheckLimit()
        for i in 0..<10 { _ = limit.admit(now: t0.addingTimeInterval(Double(i))) }
        let one = limit.admit(now: t0.addingTimeInterval(60.5))
        let two = limit.admit(now: t0.addingTimeInterval(60.5))
        #expect(one)
        #expect(!two)
    }

    @Test func limiterRefusalsDoNotExtendTheLockout() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var limit = EqualityCheckLimit()
        for _ in 0..<10 { _ = limit.admit(now: t0) }
        for _ in 0..<50 {
            let refused = limit.admit(now: t0.addingTimeInterval(59))
            #expect(!refused)
        }
        let later = limit.admit(now: t0.addingTimeInterval(61))
        #expect(later)
    }

    @Test func limiterReopensExactlyAtSixtySeconds() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var early = EqualityCheckLimit()
        var onTime = EqualityCheckLimit()
        for _ in 0..<10 {
            _ = early.admit(now: t0)
            _ = onTime.admit(now: t0)
        }
        let tooSoon = early.admit(now: t0.addingTimeInterval(59.9))
        let exact = onTime.admit(now: t0.addingTimeInterval(60))
        #expect(!tooSoon)
        #expect(exact)
    }

    // MARK: Per-message budget

    @Test func messageKeyDependsOnTextAndIndexButStoresNoText() {
        let a = LastMessageMatch.messageKey(in: [user("a")])
        #expect(a != nil)
        #expect(a == LastMessageMatch.messageKey(in: [user("a")]))
        #expect(a != LastMessageMatch.messageKey(in: [user("b")]))
        #expect(a != LastMessageMatch.messageKey(in: [assistant("x"), user("a")]))
        #expect(LastMessageMatch.messageKey(in: [assistant("a")]) == nil)
        #expect(LastMessageMatch.messageKey(in: []) == nil)
    }

    @Test func thirtyChecksPerMessageThenExhaustedUntilANewMessage() {
        var limit = EqualityCheckLimit()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let key = LastMessageMatch.messageKey(in: [user("a")])
        for i in 0..<EqualityCheckLimit.perMessage {
            // Spaced past the minute window so only the per-message budget binds.
            let verdict = limit.admit(now: t0.addingTimeInterval(Double(i) * 61), messageKey: key)
            #expect(verdict == .admitted)
        }
        #expect(EqualityCheckLimit.perMessage == 30)
        let after = t0.addingTimeInterval(31 * 61)
        #expect(limit.admit(now: after, messageKey: key) == .exhausted)
        #expect(limit.admit(now: after.addingTimeInterval(3600), messageKey: key) == .exhausted)
        let next = LastMessageMatch.messageKey(in: [user("a"), assistant("r"), user("a")])
        #expect(limit.admit(now: after.addingTimeInterval(7200), messageKey: next) == .admitted)
    }

    @Test func rateLimitedIsReportedBeforeBudgetIsSpent() {
        var limit = EqualityCheckLimit()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let key = LastMessageMatch.messageKey(in: [user("a")])
        for _ in 0..<10 { _ = limit.admit(now: t0, messageKey: key) }
        #expect(limit.admit(now: t0, messageKey: key) == .rateLimited)
        // A rate-limited try does not spend the per-message budget.
        for i in 0..<20 {
            #expect(limit.admit(now: t0.addingTimeInterval(61 + Double(i) * 61), messageKey: key) == .admitted)
        }
        #expect(limit.admit(now: t0.addingTimeInterval(2000), messageKey: key) == .exhausted)
    }
}
