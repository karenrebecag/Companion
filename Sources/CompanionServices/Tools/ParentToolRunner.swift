import CompanionCore
import Foundation

/// The parent's hands. Same shape as `NativeToolRunner` minus `approved:`:
/// none of these asks permission — except, since 15g, Return in a terminal — and `run_shell` is never here. Everything
/// goes through `WorkspaceOpening`; the runner never touches `Process`.
package struct ParentToolRunner: ParentToolExecuting, Sendable {
    /// Enough to find a name in; more than this is a list, not an answer.
    package static let maxAppListing = 100

    private let workspace: any WorkspaceOpening
    private let home: URL
    private let places: (any PlacesSearching)?
    /// 16h-3: the user's city for "nearby" lookups.
    private let location: UserLocationSource?
    private let locationChannelOn: @Sendable () -> Bool
    /// The catalog behind read_skill (Wave 11a). Without it the tool is not
    /// offered: an unbacked tool captures the intent and dies.
    private let skills: (any SkillReading)?
    /// The hands (Wave 15g). Offered only while Accessibility is trusted,
    /// read per call: the grant can vanish while the app runs.
    private let hands: ScreenHands?
    /// Wave 20b D2: the deliverables, offered only with their backing. The
    /// workdir is the native runner's write barrier for create_document.
    let workdir: String?
    let documents: (any DocumentRendering)?
    let sheets: (any SpreadsheetDriving)?
    let versions: FileVersions?
    let deliverableTickets = ApprovalTickets()
    /// Whether this turn read outside the work folder; reset by `beginTurn`.
    let taint: TurnTaint
    /// Wave 20d B: told when a deliverable ran without the sheet, so the island
    /// can show it and offer the way back.
    let onAct: (@Sendable (UndoReceipt) -> Void)?

    package init(
        workspace: any WorkspaceOpening,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        places: (any PlacesSearching)? = nil,
        skills: (any SkillReading)? = nil,
        hands: ScreenHands? = nil,
        workdir: String? = nil,
        documents: (any DocumentRendering)? = nil,
        sheets: (any SpreadsheetDriving)? = nil,
        versions: FileVersions? = nil,
        onAct: (@Sendable (UndoReceipt) -> Void)? = nil,
        location: UserLocationSource? = nil,
        taint: TurnTaint = TurnTaint(),
        // Fail closed: a caller that forgets to wire the switch gets "off".
        // Last on purpose: the gate's wiring check reads it as the call's end.
        locationChannelOn: @escaping @Sendable () -> Bool = { false }
    ) {
        self.location = location
        self.taint = taint
        self.locationChannelOn = locationChannelOn
        self.onAct = onAct
        self.workspace = workspace
        self.home = home
        self.places = places
        self.skills = skills
        self.hands = hands
        self.workdir = workdir
        self.documents = documents
        self.sheets = sheets
        self.versions = versions
    }

    /// Wired at all, ready or not: a call can then say why it cannot act.
    var installedHands: ScreenHands? { hands }

    var readyHands: ScreenHands? {
        // Typed chat has Companion in front; `target` is the last app that was not Companion.
        guard let hands, hands.trusted() else { return nil }
        return hands
    }

    /// Called when the user starts speaking or sends: the hands act only on
    /// the app that was in front then.
    package func beginTurn() {
        taint.reset()
        guard let hands else { return }
        hands.turn.begin(hands.target())
    }

    /// A tool without backing is not advertised (NativeToolRunner's rule):
    /// `find_places` needs no disk and no specialist, so it is offered here
    /// too — when there is a lookup behind it.
    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        var specs = ParentTool.specs(language)
            .filter { $0.name != ParentTool.readSkill.rawValue || skills != nil }
        if places != nil { specs.append(NativeTool.findPlaces.spec) }
        specs += deliverables.map(\.spec)
        if let hands = readyHands {
            specs += ParentTool.handsSpecs(
                language, sight: hands.screen != nil, see: hands.see != nil)
        }
        return specs
    }

    package func handles(_ name: String) -> Bool {
        if let tool = ParentTool(rawValue: name) {
            if tool == .see { return readyHands?.see != nil }
            if tool.isSight { return readyHands?.screen != nil }
            if tool.isHands { return readyHands != nil }
            return tool != .readSkill || skills != nil
        }
        if deliverables.contains(where: { $0.rawValue == name }) { return true }
        return name == NativeTool.findPlaces.rawValue && places != nil
    }

    package func unavailability(for name: String) -> String? {
        guard let tool = ParentTool(rawValue: name), !handles(name) else { return nil }
        guard tool.isHands || tool.isSight else { return BridgeCode.notAvailable }
        guard let hands else { return BridgeCode.notAvailable }
        let backed = tool == .see ? hands.see != nil : (!tool.isSight || hands.screen != nil)
        guard backed else { return BridgeCode.notAvailable }
        if !hands.trusted() { return BridgeCode.needsAccessibility }
        return BridgeCode.notAvailable
    }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard handles(name) else {
            return .failed(.notFound("unknown tool: \(name)"))
        }
        // Never `[:]` on a parse failure, and never the raw arguments back:
        // they can hold text meant for another app (review 2026-09-25).
        guard let arguments = ToolArguments.parse(argumentsJSON) else {
            return .failed(.invalidArgs(
                "could not parse arguments (\(argumentsJSON.count) chars); send one JSON object"))
        }
        guard let tool = ParentTool(rawValue: name) else {
            if let deliverable = NativeTool(rawValue: name),
               deliverables.contains(deliverable) {
                return await runDeliverable(deliverable, arguments: arguments, argumentsJSON: argumentsJSON)
            }
            return await findPlaces(arguments)
        }
        switch tool {
        case .openApp, .openURL, .openFile:
            // Opened behind the lock screen, it would be a success nobody saw.
            if hands?.locked() == true {
                return .failed(ContractError(code: BridgeCode.screenLocked, message: BridgeMessages.screenLocked),
                               tool: tool.rawValue)
            }
            let outcome: ParentToolOutcome
            // open_file and open_url land in an app the model never named
            // (a folder opens Finder): it is the one the hands must follow.
            var opened: String?
            switch tool {
            case .openApp:
                outcome = await openApp(arguments)
                opened = outcome.target
            case .openURL: (outcome, opened) = await openURL(arguments)
            default: (outcome, opened) = await openFile(arguments)
            }
            // The user asked for this app to come up: the hands follow it
            // for the rest of the turn instead of refusing it as a switch.
            // The per-call check that the front did not move still holds.
            guard outcome.ok else { return outcome }
            guard let opened, !opened.isEmpty, let hands, let launch = hands.launch else {
                hands?.turn.release()
                return outcome
            }
            return await settleLaunch(
                outcome, app: opened, strict: tool == .openApp, hands: hands, launch: launch)
        case .listApps: return listApps()
        case .readSkill: return readSkill(arguments)
        case .findBlock: return findBlock(arguments)
        case .typeText, .pressKey, .focusWindow, .readFocused, .look, .click, .scroll, .menu, .see:
            let call = ToolCallRef(id: "", name: name, arguments: argumentsJSON)
            return await runHands(tool, call, arguments)
        }
    }

    /// An opened app is not ready until it is the front one and has a window:
    /// typing a moment earlier lands in the app the user was in. The turn is
    /// pinned to the launched pid, so a late activation cannot move it back.
    private func settleLaunch(
        _ outcome: ParentToolOutcome, app name: String, strict: Bool, hands: ScreenHands, launch: any AppWindowProbing
    ) async -> ParentToolOutcome {
        let pid = await hands.windowWait.wait {
            guard let pid = launch.pid(ofApp: name), launch.hasWindow(pid: pid),
                  hands.target() == pid else { return nil }
            return pid
        }
        guard let pid else {
            // A repin here took whatever came to the front next: a Cmd-N
            // meant for TextEdit landed in Slack (2026-10-06). Hold the turn
            // to the launched app, or to the app it already had.
            if let launched = launch.pid(ofApp: name) { hands.turn.begin(launched) }
            // The file or URL did open; only open_app promised a ready window.
            if !strict {
                if launch.pid(ofApp: name) == nil { hands.turn.release() }
                return outcome
            }
            // A cut turn is not an app without a window: say which it was.
            if Task.isCancelled {
                return .failed(Self.handsError("cancelled", "the turn was cut before \(name) was ready"),
                               target: name)
            }
            Log.app("hands: open window_not_ready")
            return .failed(Self.handsError(
                "window_not_ready",
                "\(name) was opened but has no window in front yet; look, or try again in a moment"),
                target: name)
        }
        hands.turn.begin(pid)
        return outcome
    }

    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        // After a read outside the work folder every address asks, unless the
        // user's own words named its host (read, then open evil.tld?d=<it>).
        if let request = ParentToolGate.approval(for: call, said: said, strictHost: taint.isTainted) {
            return request
        }
        if let request = deliverableApproval(for: call) { return request }
        guard ParentTool(rawValue: call.name)?.isHands == true else { return nil }
        return handsApproval(for: call, said: said)
    }

    package func granted(_ request: ApprovalRequest) {
        hands?.tickets.grant(id: request.requestId)
        deliverableTickets.grant(id: request.requestId)
    }

    package func withdraw(_ call: ToolCallRef) {
        hands?.tickets.revoke(name: call.name, arguments: call.arguments)
        deliverableTickets.revoke(name: call.name, arguments: call.arguments)
    }

    /// By catalog name only. A path is not a valid name, so it is not found
    /// before anything looks at the disk.
    private func findBlock(_ arguments: [String: Any]) -> ParentToolOutcome {
        guard let query = arguments["query"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failed(.invalidArgs("missing query")) }
        return ParentToolOutcome(
            ok: true,
            output: BlockCatalog.reply(for: BlockCatalog.find(query)),
            tool: ParentTool.findBlock.rawValue)
    }

    private func readSkill(_ arguments: [String: Any]) -> ParentToolOutcome {
        guard let raw = arguments["name"] as? String else {
            return .failed(.invalidArgs("missing name"))
        }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SkillFrontmatter.isValidName(name), let body = skills?.body(named: name) else {
            return .failed(.notFound(
                "no skill or knowledge named \"\(name)\"; use a name listed in "
                    + "<active_skills> or <active_knowledge>"),
                target: name, tool: ParentTool.readSkill.rawValue)
        }
        let scalars = body.unicodeScalars
        let output = scalars.count > NativeToolRunner.maxSkillBody
            ? String(String.UnicodeScalarView(scalars.prefix(NativeToolRunner.maxSkillBody))) + "…"
            : body
        return ParentToolOutcome(
            ok: true, output: output, target: name, tool: ParentTool.readSkill.rawValue)
    }

    // MARK: - tools

    private func openApp(_ arguments: [String: Any]) async -> ParentToolOutcome {
        guard let raw = arguments["name"] as? String else {
            return .failed(.invalidArgs("missing name"))
        }
        let name: String
        do {
            name = try ParentToolPolicy.appName(raw)
        } catch {
            return .failed(error, target: raw)
        }
        // Resolved against what is actually here, so the adapter only ever
        // opens an exact name and a near miss comes back with candidates.
        let known = workspace.runningApplications() + workspace.installedApplications()
        switch ParentToolPolicy.resolveApp(
            name, among: known, localized: workspace.localizedApplicationNames()) {
        case .failure(let error):
            return .failed(error, target: name)
        case .success(let exact):
            do {
                try await workspace.openApplication(named: exact)
            } catch {
                return .failed(error, target: exact)
            }
            return ParentToolOutcome(ok: true, output: "opened \(exact)", target: exact)
        }
    }

    private func openURL(_ arguments: [String: Any]) async -> (ParentToolOutcome, String?) {
        guard let raw = arguments["url"] as? String else {
            return (.failed(.invalidArgs("missing url")), nil)
        }
        let url: URL
        do {
            url = try ParentToolPolicy.httpURL(raw)
        } catch {
            return (.failed(error, target: raw), nil)
        }
        let app = workspace.applicationName(toOpen: url)
        do {
            try await workspace.open(url)
        } catch {
            return (.failed(error, target: url.absoluteString), nil)
        }
        return (ParentToolOutcome(
            ok: true, output: "opened \(url.absoluteString)", target: url.absoluteString), app)
    }

    private func openFile(_ arguments: [String: Any]) async -> (ParentToolOutcome, String?) {
        guard let raw = arguments["path"] as? String else {
            return (.failed(.invalidArgs("missing path")), nil)
        }
        let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        do {
            url = try ParentToolPolicy.homePath(raw, home: home, workdir: workdir)
        } catch {
            return (.failed(error, target: target), nil)
        }
        let app = workspace.applicationName(toOpen: url)
        do {
            try await workspace.open(url)
        } catch {
            return (.failed(error, target: target), nil)
        }
        return (ParentToolOutcome(ok: true, output: "opened \(url.path)", target: target), app)
    }

    private func listApps() -> ParentToolOutcome {
        let running = workspace.runningApplications()
        var seen: Set<String> = []
        var lines: [String] = []
        // Both names, so the model can match what the user said either way.
        let localized = Dictionary(
            workspace.localizedApplicationNames().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func label(_ name: String) -> String {
            guard let other = localized[name], other != name.lowercased() else { return name }
            return "\(name) (\(other.capitalized))"
        }
        for name in running where seen.insert(name).inserted {
            lines.append("- \(label(name)) (running)")
        }
        for name in workspace.installedApplications() where seen.insert(name).inserted {
            lines.append("- \(label(name))")
        }
        let shown = lines.prefix(Self.maxAppListing)
        var output = shown.joined(separator: "\n")
        let hidden = lines.count - shown.count
        if hidden > 0 {
            output += "\n… and \(hidden) more not shown"
        }
        if output.isEmpty { output = "no applications found" }
        return ParentToolOutcome(ok: true, output: output)
    }

    /// Reuses the native runner's lookup and card verbatim: `find_places` is
    /// `.safe`, so the approval gate it passes through is a no-op.
    private func findPlaces(_ arguments: [String: Any]) async -> ParentToolOutcome {
        let native = NativeToolRunner(workdir: nil, places: places, webSearch: nil, location: location,
                                       locationChannelOn: locationChannelOn)
        let query = arguments["query"] as? String ?? ""
        do {
            let result = try await native.execute(
                tool: NativeTool.findPlaces.rawValue, arguments: arguments, approved: false)
            return ParentToolOutcome(
                ok: result.ok, output: result.output, target: query, card: result.card)
        } catch {
            return .failed(.notFound("place lookup failed: \(error)"), target: query)
        }
    }
}
