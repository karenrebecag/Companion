import Foundation

/// Wave 19-1. What the approval sheet says, decided from the raw request in
/// one pure place. The phrase leads and the subject carries the weight; the
/// full datum (URL, command, path) stays in `preview` because human-first
/// is hierarchy, never hiding — the user must always be able to audit
/// exactly what will run.
package struct ApprovalDisplay: Sendable, Equatable {
    /// What the sheet's tile draws: an SF Symbol, or the Claude logo when
    /// the bridge client says it is one (19-1b — the one client we ship a
    /// face for; the claim note still applies, a logo is not an identity).
    package enum Mark: Sendable, Equatable { case symbol(String), claude }
    package var mark: Mark
    /// Words before the subject ("Abrir"); nil when the subject opens the
    /// phrase (the bridge's client name does).
    package var lead: String?
    /// The one thing being asked about, painted with the visual weight.
    /// Capped at 80 with a visible mark: an unbounded subject could push
    /// the answer buttons off screen (security review 19-1).
    package var subject: String
    /// Words after the subject ("quiere usar tus manos").
    package var trail: String?
    /// The complete auditable datum, secondary and selectable. NEVER cut:
    /// the tail is part of what runs (15g M1, extended by review 19-1) —
    /// the sheet bounds it with a scroll, not with an ellipsis.
    package var preview: String?
    package var showsRemember: Bool

    /// The whole phrase, for accessibility and tests.
    package var title: String {
        [lead, subject, trail].compactMap { $0 }.joined(separator: " ")
    }
}

package enum ApprovalCopy {
    /// Keys whose value stands for the whole request when no tool rule
    /// applies (`goal`: a handoff is approved on what it would delegate,
    /// never on the word "delegate" — security review 2026-09-25).
    private static let interesting = ["command", "path", "url", "query", "content", "goal"]

    package static func display(for request: ApprovalRequest, language: AppLanguage) -> ApprovalDisplay {
        let arguments = ToolArguments.parse(request.inputJSON) ?? [:]
        if request.isMCP { return mcpTool(request, language) }
        if request.toolName == BridgePolicy.sessionApprovalTool {
            return bridge(arguments, language)
        }
        if let display = parentTool(request.toolName, arguments, language) { return display }
        if let display = nativeTool(request.toolName, arguments, language) { return display }
        if request.toolName.hasPrefix(appToolPrefix) { return appTool(request, language) }
        if request.toolName == WindowArrangeTool.name { return windowArrange(request, language) }
        return fallback(request.toolName, arguments, language)
    }

    /// 16k-3: the runner mints `app:<slug>:<tool>` requests for connected
    /// apps. The runner already built the human line ("Send Message ·
    /// Slack") in `summary`; the full arguments are the preview — they are
    /// what runs, same rule as type_text (15g M1).
    package static let appToolPrefix = "app:"

    private static func appTool(_ request: ApprovalRequest, _ language: AppLanguage) -> ApprovalDisplay {
        // No remember on purpose: `ApprovalKey.from` has no rule for app
        // tools, so a ticked toggle would promise a memory that never
        // happens. Every write asks, every time, until a key exists.
        ApprovalDisplay(
            mark: .symbol("app.connected.to.app.below.fill"),
            lead: word(.allow, language),
            subject: capped(request.summary.isEmpty ? request.toolName : request.summary),
            preview: request.inputJSON == "{}" ? nil : plainPreview(request.inputJSON),
            showsRemember: false)
    }

    /// No remember toggle: `ApprovalKey` has no rule for window moves, so a
    /// ticked box would promise a memory that never happens.
    private static func windowArrange(_ request: ApprovalRequest, _ language: AppLanguage) -> ApprovalDisplay {
        ApprovalDisplay(
            mark: .symbol("rectangle.split.2x1"), lead: word(.allow, language),
            subject: capped(request.summary.isEmpty ? request.toolName : request.summary),
            preview: nil, showsRemember: false)
    }

    /// A remote server's tool: its name and arguments are the server's and
    /// the model's words, and the click is the only authority (20c D2), so
    /// the sheet shows the name sanitized and EVERY argument, never the one
    /// key a generic rule happens to know. No remember: `ApprovalKey.from`
    /// has no rule for MCP, a ticked toggle would promise a memory that
    /// never happens.
    private static func mcpTool(_ request: ApprovalRequest, _ language: AppLanguage) -> ApprovalDisplay {
        let arguments = request.inputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        return ApprovalDisplay(
            mark: .symbol("network"), lead: word(.allow, language),
            subject: capped(plainPreview(request.toolName, keepingLayout: false)),
            preview: arguments.isEmpty || arguments == "{}" ? nil : plainPreview(arguments),
            showsRemember: false)
    }

    private static let hiddenCategories: Set<Unicode.GeneralCategory> = [
        .control, .format, .lineSeparator, .paragraphSeparator,
    ]

    /// The arguments came from the model and can quote a page or a chat:
    /// bidi and control scalars could visually reorder what the sheet
    /// shows, and a reordered preview approves something else (F-F,
    /// security review 16k-3). Every format scalar (zero-width, joiners,
    /// BOM, soft hyphen) and the Unicode line/paragraph separators go too:
    /// they hide or forge text the same way. Newlines and tabs stay — they
    /// are layout, not direction — unless the text is a one-line title.
    package static func plainPreview(_ text: String, keepingLayout: Bool = true) -> String {
        String(text.unicodeScalars.filter { scalar in
            if scalar == "\n" || scalar == "\t" { return keepingLayout }
            return !Self.hiddenCategories.contains(scalar.properties.generalCategory)
        }.map(Character.init))
    }

    /// The chat's "as before" line names what was remembered in words, not
    /// in tool ids. Singular on purpose: the memory is per PATTERN (this
    /// host, this command word — `ApprovalKey`), never a blanket grant, and
    /// "abrir enlaces" would overstate it (review 19-1). A tool without a
    /// noun here stays as its id.
    package static func toolLabel(_ tool: String, language: AppLanguage) -> String {
        let nouns: [String: (es: String, en: String)] = [
            ParentTool.openURL.rawValue: ("abrir un enlace", "open a link"),
            ParentTool.openApp.rawValue: ("abrir una app", "open an app"),
            ParentTool.openFile.rawValue: ("abrir un archivo", "open a file"),
            ParentTool.typeText.rawValue: ("escribir texto", "type text"),
            ParentTool.click.rawValue: ("pulsar un botón", "click a button"),
            ParentTool.pressKey.rawValue: ("pulsar una tecla", "press a key"),
            NativeTool.runShell.rawValue: ("ejecutar un comando", "run a command"),
            NativeTool.writeFile.rawValue: ("escribir un archivo", "write a file"),
            NativeTool.editFile.rawValue: ("editar un archivo", "edit a file"),
        ]
        guard let noun = nouns[tool] else { return tool }
        return language == .es ? noun.es : noun.en
    }

    private static func parentTool(
        _ tool: String, _ arguments: [String: Any], _ language: AppLanguage
    ) -> ApprovalDisplay? {
        switch ParentTool(rawValue: tool) {
        case .openURL:
            guard let raw = value(arguments, "url") else { return nil }
            // Parsed the way the executor parses: the subject must be the
            // host that will actually open (security review 2026-09-05); an
            // unparseable string shows as-is instead of hiding behind a
            // prettier guess — the error IS the display decision here, not
            // a swallowed failure.
            let host: String?
            do { host = try ParentToolPolicy.httpURL(raw).host } catch { host = nil }
            // 19-1c: with the host in the title the full URL box read as
            // noise (Karen). The preview survives only for an unparseable
            // string long enough that the capped subject hid part of it —
            // then the box is the only place the whole datum shows.
            return ApprovalDisplay(
                mark: .symbol("link"), lead: word(.open, language),
                subject: capped(host ?? raw),
                preview: host == nil && raw.count > 80 ? raw : nil,
                showsRemember: true)
        case .openApp:
            guard let name = value(arguments, "name") else { return nil }
            return ApprovalDisplay(
                mark: .symbol("macwindow"), lead: word(.openApp, language),
                subject: capped(name), preview: nil, showsRemember: true)
        case .openFile:
            guard let path = value(arguments, "path") else { return nil }
            return ApprovalDisplay(
                mark: .symbol("doc"), lead: word(.openFile, language),
                subject: filename(path), preview: path, showsRemember: true)
        case .typeText:
            guard let text = arguments["text"] as? String else { return nil }
            let app = value(arguments, "app")
            // The full text, never cut: the hands ask only about words the
            // user did not say, and a cut would hide the part that runs
            // (15g, review 2026-09-25 M1).
            return ApprovalDisplay(
                mark: .symbol("keyboard"), lead: word(.typeIn, language),
                subject: capped(app ?? word(.activeField, language)),
                preview: text, showsRemember: true)
        case .click:
            guard let label = value(arguments, "label") else { return nil }
            let app = value(arguments, "app")
            return ApprovalDisplay(
                mark: .symbol("cursorarrow.click"), lead: word(.press, language),
                subject: capped(label), preview: app, showsRemember: true)
        case .pressKey:
            guard let key = value(arguments, "key") else { return nil }
            let parts = [value(arguments, "app"), value(arguments, "line")].compactMap { $0 }
            return ApprovalDisplay(
                mark: .symbol("keyboard"), lead: word(.pressKey, language),
                subject: capped(key), preview: parts.isEmpty ? nil : parts.joined(separator: "\n"),
                showsRemember: true)
        case .menu:
            guard let path = value(arguments, "path") else { return nil }
            return ApprovalDisplay(
                mark: .symbol("filemenu.and.selection"), lead: word(.chooseMenu, language),
                subject: capped(path), preview: path.count > 80 ? path : nil,
                showsRemember: true)
        default:
            return nil
        }
    }

    private static func nativeTool(
        _ tool: String, _ arguments: [String: Any], _ language: AppLanguage
    ) -> ApprovalDisplay? {
        switch NativeTool(rawValue: tool) {
        case .runShell:
            guard let command = value(arguments, "command"),
                  let first = command.split(whereSeparator: { $0.isWhitespace }).first
            else { return nil }
            return ApprovalDisplay(
                mark: .symbol("terminal"), lead: word(.run, language),
                subject: capped(String(first)), preview: command, showsRemember: true)
        case .writeFile, .editFile:
            guard let path = value(arguments, "path") else { return nil }
            let writes = NativeTool(rawValue: tool) == .writeFile
            return ApprovalDisplay(
                mark: .symbol("square.and.pencil"),
                lead: word(writes ? .writeFile : .editFile, language),
                subject: filename(path), preview: path, showsRemember: true)
        case .sheetWrite:
            guard let range = value(arguments, "range") else { return nil }
            // Wave 20c D4: the workbook and every cell, uncut. The workbook
            // is the runner's (`SheetApproval.bind`), the cells are what runs.
            let app = value(arguments, "app").map { $0.capitalized + " · " } ?? ""
            return ApprovalDisplay(
                mark: .symbol("tablecells"), lead: word(.writeSheet, language),
                subject: capped(app + range.uppercased()),
                preview: SheetApproval.preview(arguments, language: language), showsRemember: true)
        default:
            return nil
        }
    }

    private static func bridge(_ arguments: [String: Any], _ language: AppLanguage) -> ApprovalDisplay {
        // The client name came off the wire and now holds the title slot:
        // ASCII-printable only (a Cyrillic homoglyph must not wear another
        // name), capped, and shown in guillemets — it is a self-claim, not
        // an identity, and the preview says so (security review 19-1).
        let raw = arguments["client"] as? String ?? ""
        let safe = String(raw.unicodeScalars
            .filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0)
                || $0 == "-" || $0 == "_" || $0 == "." || $0 == " ") }
            .prefix(32).map(Character.init))
            .trimmingCharacters(in: .whitespaces)
        // Exact allowlist, not a prefix: the name is attacker-influenced
        // and the logo reads as verification — "claude-evil" stays generic
        // (review 19-1b M2).
        let claudeClients: Set<String> = ["claude", "claude-code", "claude desktop", "claude-desktop"]
        let mark: ApprovalDisplay.Mark =
            claudeClients.contains(safe.lowercased()) ? .claude : .symbol("hand.raised")
        // 19-1c: no detail box — "quiere usar tu Mac" says it all (Karen,
        // who approved dropping the unverified-name sentence); the exact
        // allowlist above is what keeps a stranger from wearing the logo.
        // BridgeCopy.sheetClaim/sheetDetail are now unread outside tests —
        // remove in 19-4 cleanup.
        return ApprovalDisplay(
            mark: mark, lead: nil,
            subject: safe.isEmpty ? word(.someClient, language) : safe,
            trail: BridgeCopy.sheetTitle(language),
            preview: peerPreview(arguments, language),
            showsRemember: false)
    }

    /// 20c D5 (M2c): the kernel's view of the peer (pid, executable), the one
    /// line that is not the client's own claim. Nothing known, no box.
    private static func peerPreview(_ arguments: [String: Any], _ language: AppLanguage) -> String? {
        guard let pid = (arguments["pid"] as? NSNumber)?.intValue else { return nil }
        let process = value(arguments, "process").map { plainPreview($0, keepingLayout: false) }
        return BridgeCopy.peerLine(pid: pid, process: process, language: language)
    }

    /// A tool without a rule keeps its id in the visible title: the hover
    /// tooltip is a bonus, never the audit path (security review 19-1).
    private static func fallback(
        _ tool: String, _ arguments: [String: Any], _ language: AppLanguage
    ) -> ApprovalDisplay {
        let detail = interesting.lazy.compactMap { value(arguments, $0) }.first
        return ApprovalDisplay(
            mark: .symbol("questionmark.circle"), lead: word(.allow, language),
            subject: capped(tool), preview: detail, showsRemember: true)
    }

    /// A present-but-empty argument is nobody's subject; treating it as
    /// missing routes the request to the fallback instead of rendering a
    /// phrase that trails off ("Pulsar ").
    private static func value(_ arguments: [String: Any], _ key: String) -> String? {
        guard let value = arguments[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func filename(_ path: String) -> String {
        let component = (path as NSString).lastPathComponent
        return capped(component.isEmpty ? path : component)
    }

    /// One line, both ends: the cut is in the MIDDLE because on a host the
    /// registrable domain sits at the end — a padded
    /// `paypal.com.<filler>.evil.net` must show `evil.net`, not hide it
    /// behind the ellipsis (security review 19-1).
    private static func capped(_ value: String) -> String {
        let flat = value.replacingOccurrences(
            of: "[\\r\\n]+", with: " ", options: .regularExpression)
        guard flat.count > 80 else { return flat }
        return flat.prefix(40) + "…" + flat.suffix(39)
    }

    private enum Word {
        case open, openApp, openFile, typeIn, activeField, press, pressKey
        case chooseMenu, run, writeFile, editFile, allow, someClient, writeSheet
    }

    private static func word(_ word: Word, _ language: AppLanguage) -> String {
        switch (word, language) {
        case (.open, .es): "Abrir"
        case (.open, .en): "Open"
        case (.openApp, .es): "Abrir la app"
        case (.openApp, .en): "Open the app"
        case (.openFile, .es): "Abrir el archivo"
        case (.openFile, .en): "Open the file"
        case (.typeIn, .es): "Escribir en"
        case (.typeIn, .en): "Type in"
        case (.activeField, .es): "el campo activo"
        case (.activeField, .en): "the active field"
        case (.press, .es): "Pulsar"
        case (.press, .en): "Click"
        case (.pressKey, .es): "Pulsar la tecla"
        case (.pressKey, .en): "Press the key"
        case (.chooseMenu, .es): "Elegir del menú"
        case (.chooseMenu, .en): "Choose from the menu"
        case (.run, .es): "Ejecutar"
        case (.run, .en): "Run"
        case (.writeFile, .es): "Escribir el archivo"
        case (.writeFile, .en): "Write the file"
        case (.editFile, .es): "Editar el archivo"
        case (.editFile, .en): "Edit the file"
        case (.allow, .es): "Permitir"
        case (.allow, .en): "Allow"
        case (.writeSheet, .es): "Escribir en la hoja"
        case (.writeSheet, .en): "Write to the sheet"
        case (.someClient, .es): "El cliente"
        case (.someClient, .en): "The client"
        }
    }
}
