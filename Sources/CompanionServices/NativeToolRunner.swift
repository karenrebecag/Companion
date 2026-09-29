import CompanionCore
import Foundation

public struct ToolResult: Sendable {
    /// What the model reads. `content`, in the vocabulary of the Apps SDK.
    public var ok: Bool
    public var output: String
    /// What the interface paints, on its own channel. The model never reads
    /// this, which is the point: a coordinate it cannot see is a coordinate it
    /// cannot rewrite wrong.
    public var card: Card?

    public init(ok: Bool, output: String, card: Card? = nil) {
        self.ok = ok
        self.output = output
        self.card = card
    }
}

/// Single entry point for tool execution: enforces approval gate for risky tools
/// and applies double-barrier path validation (lexical + symlink resolution).
public struct NativeToolRunner: Sendable {
    private let workdir: String?
    private let pathValidator: PathValidator
    private let places: (any PlacesSearching)?
    private let webSearch: (any WebSearching)?
    /// 16h-3: where "nearby" means. Absent, the lookup runs as it always did.
    private let location: UserLocationSource?
    private let timeout: TimeInterval
    /// The denial is copy a model reads; it follows the user's language.
    private let language: AppLanguage
    /// The app's own folders (Wave 11a): readable beyond the workdir, and
    /// the place where a write earns a sync line.
    private let skills: SkillsLocation?
    /// Wave 20: absent, the tool is not offered (a tool without a backing
    /// captures the intent and then dies).
    let documents: (any DocumentRendering)?
    let sheets: (any SpreadsheetDriving)?
    /// A skill body is a few hundred lines; a 10 MB read_file cap is not a
    /// cap for this.
    static let maxSkillBody = 40_000
    /// Enough to recognise a name, short of pasting a whole disk into the
    /// model's context.
    private static let maxListEntries = 250
    private static let maxListDepth = 3

    /// Injectable timeout: the tests must not sit through a real minute of
    /// shell, and a blocking test starves everything else on the main actor.
    public init(
        workdir: String?,
        shellTimeout: TimeInterval = 60,
        places: (any PlacesSearching)? = MapKitPlacesSearch(),
        webSearch: (any WebSearching)? = nil,
        language: AppLanguage = .en,
        skills: SkillsLocation? = nil,
        documents: (any DocumentRendering)? = nil,
        sheets: (any SpreadsheetDriving)? = nil,
        location: UserLocationSource? = nil
    ) {
        self.workdir = workdir
        self.pathValidator = PathValidator(workdir: workdir, extraRoots: skills?.roots ?? [])
        self.timeout = shellTimeout
        self.places = places
        self.webSearch = webSearch
        self.location = location
        self.language = language
        self.skills = skills
        self.documents = documents
        self.sheets = sheets
    }

    /// What the model is allowed to see it has. A tool whose backing is not
    /// configured is not advertised: offering one that always fails captures
    /// the intent and then dies, which is how "buscar cines" ended in "no
    /// puedo buscar en la web" instead of falling through to find_places.
    public var availableTools: [NativeTool] {
        NativeTool.allCases.filter { tool in
            switch tool {
            case .webSearch: return webSearch?.isConfigured == true
            case .createDocument: return documents != nil
            case .sheetRead, .sheetWrite: return sheets != nil
            default: return true
            }
        }
    }

    /// Execute a tool with approval gate and path barrier.
    /// Returns error BEFORE touching disk/shell if risky tool lacks approval.
    public func execute(
        tool: String,
        arguments: [String: Any],
        approved: Bool
    ) async throws -> ToolResult {
        guard let nativeTool = NativeTool(rawValue: tool) else {
            return ToolResult(ok: false, output: "Unknown tool: \(tool)")
        }

        // First gate: a refused permission is an instruction to the model,
        // not a system error it should retry (Wave 10c 3B.4).
        if nativeTool.riskLevel == .requiresApproval && !approved {
            return ToolResult(ok: false, output: Escalation.deniedByUser(language))
        }

        // Dispatch to implementation
        switch nativeTool {
        case .findPlaces:
            return await findPlaces(arguments: arguments)
        case .listDirectory:
            return listDirectory(arguments: arguments)
        case .readFile:
            return try readFile(arguments: arguments)
        case .writeFile:
            return try writeFile(arguments: arguments)
        case .editFile:
            return try editFile(arguments: arguments)
        case .runShell:
            return await runShell(arguments: arguments)
        case .webFetch:
            return try await webFetch(arguments: arguments)
        case .webSearch:
            return await runWebSearch(arguments: arguments)
        case .createDocument:
            return await createDocument(arguments: arguments)
        case .sheetRead:
            return await sheetRead(arguments: arguments)
        case .sheetWrite:
            return await sheetWrite(arguments: arguments)
        }
    }

    // MARK: - Tool Implementations

    private func readFile(arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(ok: false, output: "Missing path argument")
        }

        // Double barrier: lexical validation + real path resolution
        guard pathValidator.isAllowed(path) else {
            return ToolResult(ok: false, output: "Path outside working directory")
        }

        let realPath = resolveRealPath(path)
        guard pathValidator.isAllowed(realPath) else {
            return ToolResult(ok: false, output: "Resolved path outside working directory")
        }

        do {
            let content = try String(contentsOfFile: realPath, encoding: .utf8)
            // Limit size to prevent memory exhaustion
            let maxSize = 10 * 1024 * 1024 // 10 MB
            if content.count > maxSize {
                return ToolResult(
                    ok: true,
                    output: content.prefix(maxSize) + "\n... (truncated)"
                )
            }
            return ToolResult(ok: true, output: content)
        } catch {
            return ToolResult(ok: false, output: "Failed to read file: \(error)")
        }
    }

    private func writeFile(arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(ok: false, output: "Missing path argument")
        }
        guard let content = arguments["content"] as? String else {
            return ToolResult(ok: false, output: "Missing content argument")
        }

        let realPath: String
        switch writeBarrier(path) {
        case .success(let resolved): realPath = resolved
        case .failure(let refused): return refused
        }

        let entry = skills?.classify(realPath)
        if entry != nil, content.utf8.count > SkillCatalog.Caps.fileBytes {
            return ToolResult(ok: false, output: oversize(realPath, content.utf8.count).wire)
        }
        let previous = existingText(realPath)
        do {
            // The folder may not exist yet: a new skill starts with its
            // folder, and "No such file" would send the model to run_shell.
            // Catalog folders are the user's alone (0700/0600, like
            // attachments); a plain workdir write keeps the folder's umask.
            let folder = (realPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: folder, withIntermediateDirectories: true,
                attributes: entry == nil ? nil : [.posixPermissions: 0o700])
            try content.write(toFile: realPath, atomically: true, encoding: .utf8)
            if entry != nil {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: realPath)
            }
            return ToolResult(
                ok: true,
                output: "File written successfully"
                    + syncSuffix(realPath, previous: previous, content: content))
        } catch {
            return ToolResult(ok: false, output: "Failed to write file: \(error)")
        }
    }

    /// Read barrier, then write barrier, lexical and real. A path inside a
    /// read-only root answers with the contract code the model recovers by
    /// (`denied_path`, LAYERING §3), not with "outside".
    /// HACK: check-then-write on a path string. A process running as the
    /// same user could swap a folder for a symlink in between; that process
    /// already owns the home folder. Trigger: a second writer on these roots
    /// (a CLI executor writing concurrently) — then `open(O_NOFOLLOW)`.
    enum WriteBarrier {
        case success(String)
        case failure(ToolResult)
    }

    func writeBarrier(_ path: String) -> WriteBarrier {
        guard pathValidator.isAllowed(path) else {
            return .failure(ToolResult(ok: false, output: "Path outside working directory"))
        }
        guard pathValidator.isAllowed(path, forWrite: true) else {
            return .failure(ToolResult(ok: false, output: readOnly(path).wire))
        }
        let realPath = resolveRealPath(path)
        guard pathValidator.isAllowed(realPath) else {
            return .failure(ToolResult(ok: false, output: "Resolved path outside working directory"))
        }
        guard pathValidator.isAllowed(realPath, forWrite: true) else {
            return .failure(ToolResult(ok: false, output: readOnly(realPath).wire))
        }
        return .success(realPath)
    }

    private func readOnly(_ path: String) -> ContractError {
        let custom = skills?.customSkills.path ?? "the custom skills folder"
        return .deniedPath(
            "\(path) is read-only: system skills belong to Companion. "
                + "Write your own skill under \(custom)")
    }

    private func existingText(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0
            guard size <= SkillCatalog.Caps.fileBytes else { return nil }
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func oversize(_ path: String, _ bytes: Int) -> ContractError {
        .invalidArgs(
            "\(path) would be \(bytes) bytes; a skill or knowledge file must stay under "
                + "\(SkillCatalog.Caps.fileBytes) bytes. Keep SKILL.md short and move "
                + "reference material to a references/ file")
    }

    /// The sync line (corpus spec 12): only on a catalog file, and always
    /// with the why, so the model rewrites instead of guessing. The file is
    /// written either way — the user can fix it by hand.
    private func syncSuffix(_ realPath: String, previous: String?, content: String) -> String {
        guard let skills, let entry = skills.classify(realPath) else { return "" }
        let outcome: SkillSync.Outcome
        if previous == content {
            outcome = .upToDate
        } else {
            do {
                outcome = .saved(try SkillFrontmatter.parse(content, folder: entry.name).name)
            } catch {
                outcome = .failed(error.why)
            }
        }
        return "\n" + SkillSync.line(entry.kind, outcome)
    }

    private func editFile(arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(ok: false, output: "Missing path argument")
        }
        guard let oldString = arguments["old_string"] as? String else {
            return ToolResult(ok: false, output: "Missing old_string argument")
        }
        guard let newString = arguments["new_string"] as? String else {
            return ToolResult(ok: false, output: "Missing new_string argument")
        }

        let realPath: String
        switch writeBarrier(path) {
        case .success(let resolved): realPath = resolved
        case .failure(let refused): return refused
        }

        do {
            let previous = try String(contentsOfFile: realPath, encoding: .utf8)
            guard previous.contains(oldString) else {
                return ToolResult(ok: false, output: "old_string not found in file")
            }
            let content = previous.replacingOccurrences(of: oldString, with: newString)
            if skills?.classify(realPath) != nil, content.utf8.count > SkillCatalog.Caps.fileBytes {
                return ToolResult(ok: false, output: oversize(realPath, content.utf8.count).wire)
            }
            try content.write(toFile: realPath, atomically: true, encoding: .utf8)
            return ToolResult(
                ok: true,
                output: "File edited successfully"
                    + syncSuffix(realPath, previous: previous, content: content))
        } catch {
            return ToolResult(ok: false, output: "Failed to edit file: \(error)")
        }
    }

    /// The model picks WHAT to show; the lookup decides WITH WHAT. That split
    /// is the whole contract: the names and addresses go back as text so the
    /// model can talk about them, and the coordinates travel on the card
    /// channel where the model cannot reach them.
    private func findPlaces(arguments: [String: Any]) async -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(ok: false, output: "Missing query argument")
        }
        guard let places else {
            return ToolResult(ok: false, output: "Place lookup is unavailable")
        }
        var near = arguments["near"] as? String
        if let location, NearMe.isNearby(query: query, near: near) {
            // The lookup the user asked for is where the Location dialog may
            // appear; a turn's context sensing never asks.
            guard let city = await location.current(prompting: true) else {
                return ToolResult(ok: false, output: NearMe.needsCity(language))
            }
            near = city.label
        }
        let found = await places.search(query, near: near)
        guard !found.isEmpty else {
            // An empty map is worse than no map: it reads as "the place does
            // not exist" when it only means this query missed.
            return ToolResult(
                ok: false, output: "No places found for: \(query)")
        }

        let lines = found.map { place in
            place.address.isEmpty
                ? "- \(place.name)"
                : "- \(place.name) — \(place.address)"
        }
        let block = LocationsBlock(
            title: query,
            locations: found.map { place in
                LocationsBlock.Location(
                    id: nil, name: place.name, eyebrow: nil,
                    address: place.address.isEmpty ? nil : place.address,
                    lat: place.lat, lng: place.lng, url: nil)
            })
        return ToolResult(
            ok: true,
            output: lines.joined(separator: "\n"),
            card: Card(payload: .locations(block), source: .tool))
    }

    /// The cheapest way to stop being wrong about a name. Safe on purpose:
    /// if looking cost an approval, exploring a folder would cost one click
    /// per level and the specialist would guess instead of look.
    private func listDirectory(arguments: [String: Any]) -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(ok: false, output: "Missing path argument")
        }
        // JSON numbers arrive as Int, but a model that writes "2" is not
        // wrong enough to deserve a failure.
        let asked = (arguments["depth"] as? Int)
            ?? (arguments["depth"] as? String).flatMap(Int.init)
            ?? 1
        let depth = min(max(asked, 1), Self.maxListDepth)

        guard pathValidator.isAllowed(path) else {
            return ToolResult(
                ok: false, output: "Path outside working directory: \(path)")
        }
        let realPath = resolveRealPath(path)
        guard pathValidator.isAllowed(realPath) else {
            return ToolResult(
                ok: false, output: "Path outside working directory: \(path)")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: realPath, isDirectory: &isDirectory)
        else {
            return ToolResult(ok: false, output: "No such folder: \(path)")
        }
        guard isDirectory.boolValue else {
            return ToolResult(ok: false, output: "Not a folder: \(path)")
        }

        var lines: [String] = []
        var total = 0
        collect(realPath, prefix: "", depth: depth, into: &lines, total: &total)

        if lines.isEmpty {
            return ToolResult(ok: true, output: "(empty folder)")
        }
        var output = lines.joined(separator: "\n")
        if total > lines.count {
            // Never a silent cap: a truncated listing that does not say so
            // reads as "this is everything", which is a lie about the folder.
            output += "\n… \(total) entries in total, \(lines.count) shown."
        }
        return ToolResult(ok: true, output: output)
    }

    private func collect(
        _ dir: String, prefix: String, depth: Int,
        into lines: inout [String], total: inout Int
    ) {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: dir)
        } catch {
            lines.append("\(prefix)(unreadable folder)")
            return
        }
        // Dotfiles are noise for the question this tool answers, and a home
        // folder has hundreds of them.
        let visible = names.filter { !$0.hasPrefix(".") }.sorted()
        total += visible.count
        for name in visible {
            guard lines.count < Self.maxListEntries else { return }
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
            lines.append(prefix + name + (isDir.boolValue ? "/" : ""))
            if isDir.boolValue, depth > 1 {
                collect(
                    full, prefix: prefix + "  ", depth: depth - 1,
                    into: &lines, total: &total)
            }
        }
    }

    private func runShell(arguments: [String: Any]) async -> ToolResult {
        guard let command = arguments["command"] as? String else {
            return ToolResult(ok: false, output: "Missing command argument")
        }

        guard let workdir = workdir else {
            return ToolResult(ok: false, output: "No working directory configured")
        }

        // Delegated to ProcessGroupRunner for two reasons the old inline
        // version got wrong: it read the pipes only after waiting (so any
        // output past ~64 KB blocked the child and surfaced as a bogus
        // timeout), and it killed the shell without its descendants, leaving
        // whatever the command had started behind.
        let outcome = await ProcessGroupRunner.run(
            executable: "/bin/sh", arguments: ["-c", command],
            cwd: workdir, timeout: timeout)

        var output = outcome.stdout
        if !outcome.stderr.isEmpty {
            output += output.isEmpty ? outcome.stderr : "\n" + outcome.stderr
        }
        if outcome.timedOut {
            // What it managed to print before hanging is usually the clue to
            // WHY it hung, so it travels with the failure instead of being
            // thrown away.
            let notice = "Command execution timeout exceeded (\(timeout)s)"
            return ToolResult(
                ok: false,
                output: output.isEmpty ? notice : notice + "\n" + output)
        }
        return ToolResult(ok: outcome.exitCode == 0, output: output)
    }

    private func webFetch(arguments: [String: Any]) async throws -> ToolResult {
        guard let urlString = arguments["url"] as? String else {
            return ToolResult(ok: false, output: "Missing url argument")
        }

        guard let url = URL(string: urlString) else {
            return ToolResult(ok: false, output: "Invalid URL")
        }

        // Validate endpoint policy
        guard EndpointPolicy.isAcceptable(url) else {
            return ToolResult(ok: false, output: "URL not acceptable by security policy")
        }

        let request = URLRequest(url: url, timeoutInterval: 30)
        let session = NoStoreSession.shared

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolResult(ok: false, output: "Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                return ToolResult(
                    ok: false,
                    output: "HTTP \(httpResponse.statusCode)")
            }

            let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""

            // Limit size to prevent memory exhaustion
            let maxSize = 1 * 1024 * 1024 // 1 MB for web
            if content.count > maxSize {
                return ToolResult(
                    ok: true,
                    output: content.prefix(maxSize) + "\n... (truncated)"
                )
            }

            return ToolResult(ok: true, output: content)
        } catch {
            return ToolResult(ok: false, output: "Failed to fetch URL: \(error)")
        }
    }

    private func runWebSearch(arguments: [String: Any]) async -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(ok: false, output: "Missing query argument")
        }
        guard let webSearch, webSearch.isConfigured else {
            // Reachable only if something called the tool without asking
            // `availableTools` first. Said plainly rather than pretending.
            return ToolResult(
                ok: false, output: "Web search is not configured")
        }
        do {
            let results = try await webSearch.search(query)
            guard !results.isEmpty else {
                return ToolResult(
                    ok: false, output: "No web results for: \(query)")
            }
            // Title, url and snippet: enough to answer, and the url is what
            // lets the answer cite instead of assert.
            let lines = results.map { result in
                "- \(result.title) — \(result.url)\n  \(result.snippet)"
            }
            return ToolResult(ok: true, output: lines.joined(separator: "\n"))
        } catch {
            return ToolResult(
                ok: false, output: "Web search failed: \(error)")
        }
    }

    // MARK: - Path Utilities

    /// Resolve symlinks to get the real path on disk, then re-validate.
    private func resolveRealPath(_ path: String) -> String {
        let absolutePath = path.hasPrefix("/")
            ? path
            : ((workdir ?? ".") as NSString).appendingPathComponent(path)

        // Use resolvingSymlinksInPath to follow symlinks
        return (absolutePath as NSString).resolvingSymlinksInPath
    }
}
