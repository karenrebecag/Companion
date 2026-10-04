import CompanionCore
import Foundation

/// `browser_set_files`. The sheet is parked, never issued: a spoken yes is
/// not consent to hand a file to a site. The ticket's item holds the whole
/// identity of the file the sheet named, so a yes is never spent on a file
/// that changed after it; a fresh `lstat` is still compared again right
/// before the send, for a change that lands after the ticket is redeemed.
extension BrowserToolRunner {
    private struct SetFilesCall {
        var tab: Int
        var element: Int
        var path: String
    }

    /// `String` is not an `Error`, and the refusal text must stay a message,
    /// not a code the sheet could render.
    private struct SetFilesShape: Error {
        var message: String
    }

    /// The model's arguments, checked before a sheet and before `requireControl`.
    /// A path that cannot be a file must not adopt a tab: that lists and takes.
    private static func setFilesCall(_ arguments: [String: Any]) -> Result<SetFilesCall, SetFilesShape> {
        guard let tab = tab(arguments) else { return .failure(SetFilesShape(message: "missing or invalid tab")) }
        guard let element = ParentToolRunner.intArgument(arguments["element"]), element >= 0 else {
            return .failure(SetFilesShape(message: "missing or invalid element"))
        }
        guard let path = arguments["path"] as? String else {
            return .failure(SetFilesShape(message: "missing or invalid path"))
        }
        // The extension's shape check counts UTF-16 and rejects a null or a
        // line break. `homePath` also refuses a path whose UTF-8 exceeds the
        // same ceiling, so both are a bad argument, not a missing file.
        if path.unicodeScalars.contains(where: { $0.value == 0 || $0 == "\n" || $0 == "\r" }) {
            return .failure(SetFilesShape(message: "path contains a line break or a null"))
        }
        if path.utf16.count > ParentToolPolicy.maxInputLength
            || path.utf8.count > ParentToolPolicy.maxInputLength {
            return .failure(SetFilesShape(message: "path is too long"))
        }
        if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(SetFilesShape(message: "missing or invalid path"))
        }
        return .success(SetFilesCall(tab: tab, element: element, path: path))
    }

    private static var uploadHome: URL { FileManager.default.homeDirectoryForCurrentUser }

    func setFilesApproval(_ call: ToolCallRef, arguments: [String: Any]) -> ApprovalRequest? {
        guard mayUpload, case .success(let shaped) = Self.setFilesCall(arguments), mayAct(shaped.tab) else {
            return nil
        }
        guard let page = freshPage(shaped.tab),
              let element = page.elements.first(where: { $0.id == shaped.element }),
              Self.isUploadableFileInput(element),
              let host = PageHost.display(of: page.origin)
        else { return nil }
        guard case .success(let file) = Self.judge(shaped.path), file.size >= 0 else { return nil }
        // The sheet renders `inputJSON`. Host, size, path and label are the
        // page and the lstat: a model can put anything in its own arguments.
        let shown: [String: Any] = [
            "bytes": NSNumber(value: file.size),
            "host": host,
            "label": element.label,
            "path": file.path,
        ]
        let json: String
        do {
            let data = try JSONSerialization.data(
                withJSONObject: shown, options: [.sortedKeys, .withoutEscapingSlashes])
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            json = text
        } catch {
            // No sheet is the closed answer: a sheet that cannot be built cannot be agreed to.
            return nil
        }
        let request = ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: "upload a file to \(host)", inputJSON: json)
        let ticket = Self.fileTicket(call.arguments, tab: shaped.tab, element: element, page: page, file: file)
        tickets.park(ticket, id: request.requestId)
        return request
    }

    /// D5: the bridge allowlist already hides this tool; a bridge caller that
    /// reaches the runner anyway still gets no sheet and no upload.
    private var mayUpload: Bool { caller == Self.chatCaller }

    func setFiles(_ arguments: [String: Any], _ raw: String) async -> ParentToolOutcome {
        guard mayUpload else {
            return fail(.setFiles, BridgeCode.unknownTool, "unknown tool: \(BrowserTool.setFiles.rawValue)")
        }
        switch Self.setFilesCall(arguments) {
        case .failure(let error):
            return fail(.setFiles, BridgeCode.invalidArgs, error.message)
        case .success(let call):
            return await upload(call, raw: raw)
        }
    }

    private func upload(_ call: SetFilesCall, raw: String) async -> ParentToolOutcome {
        let tool = BrowserTool.setFiles
        let wasControlled = controls(call.tab)
        if let denied = await requireControl(tool, call.tab) { return denied }
        let adopted = !wasControlled
        guard let page = freshPage(call.tab) else { return stale(tool) }
        guard let element = page.elements.first(where: { $0.id == call.element }) else { return stale(tool) }
        guard Self.isUploadableFileInput(element) else {
            return fail(tool, BridgeCode.notFileInput, BrowserCopy.failure(code: BridgeCode.notFileInput, language()))
        }
        guard PageHost.display(of: page.origin) != nil else {
            // The origin is not repeated: it may carry userinfo or a script.
            return fail(tool, BridgeCode.invalidArgs, "only an http or https page can receive a file")
        }
        let file: BrowserFilePolicy.File
        switch Self.judge(call.path) {
        case .failure(let error): return failed(tool, error)
        case .success(let judged): file = judged
        }
        guard tickets.redeem(Self.fileTicket(raw, tab: call.tab, element: element, page: page, file: file)) else {
            return needsApproval(tool, adopted: adopted)
        }
        guard await tabIsStillAt(call.tab, origin: page.origin) else { return leftItsOrigin(tool, call.tab) }
        // HACK: by-path ceiling. Chrome opens the path we send, so a swap in the
        // gap after this lstat still lands on the page. Upgrade trigger: the
        // extension accepts a descriptor or the bytes instead of a path.
        let again: BrowserFilePolicy.File
        switch Self.judge(file.path) {
        case .failure(let error): return failed(tool, error)
        case .success(let judged): again = judged
        }
        guard Self.sameIdentity(file, again) else { return changed(tool) }
        return await deliver(file, element: element, page: page)
    }

    private func deliver(
        _ file: BrowserFilePolicy.File, element: BrowserElement, page: BrowserPage
    ) async -> ParentToolOutcome {
        let tool = BrowserTool.setFiles
        switch await channel.send(
            .setFiles(tab: page.tab, generation: page.generation, element: element.id, path: file.path),
            timeout: Self.actTimeout)
        {
        case .failure(let error):
            // Whatever the extension refused, the page it saw is not the one
            // that was read, or may have changed before it refused.
            forget(page.tab)
            return failed(tool, error)
        case .success(.done):
            return ParentToolOutcome(
                ok: true, output: "uploaded [\(element.id)]; read the tab again to see the result",
                target: page.origin, tool: tool.rawValue)
        case .success:
            return fail(tool, BridgeCode.badFrame, "unexpected reply")
        }
    }

    /// inode, device and ctime, and the rest of the stat. Userspace cannot
    /// put ctime back, so an in-place rewrite that restores mtime still differs.
    private static func sameIdentity(_ left: BrowserFilePolicy.File, _ right: BrowserFilePolicy.File) -> Bool {
        left.inode == right.inode && left.device == right.device && left.ctime == right.ctime && left == right
    }

    private static func isUploadableFileInput(_ element: BrowserElement) -> Bool {
        element.frame == 0 && element.frameOrigin == nil && element.inputType?.lowercased() == "file"
    }

    /// Length-prefixed, so no field can borrow a character from its neighbour:
    /// the label and the origin come from the page. The origin is the one the
    /// read cached, not the host painted on the sheet.
    static func fileTicket(
        _ arguments: String, tab: Int, element: BrowserElement, page: BrowserPage, file: BrowserFilePolicy.File
    ) -> ApprovalTickets.Ticket {
        let fields = [
            element.label, page.origin, file.path, String(file.size), String(file.mtime), String(file.ctime),
            String(file.inode), String(file.device),
        ]
        let item = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return ApprovalTickets.Ticket(
            name: BrowserTool.setFiles.rawValue, arguments: arguments, pid: Int32(clamping: tab),
            item: item, node: element.id, generation: page.generation)
    }

    private static func judge(_ path: String) -> Result<BrowserFilePolicy.File, ContractError> {
        do {
            return .success(try BrowserFilePolicy.judge(path, home: uploadHome))
        } catch let error as ContractError {
            return .failure(error)
        } catch {
            return .failure(.invalidArgs("that file cannot be uploaded"))
        }
    }

    private func stale(_ tool: BrowserTool) -> ParentToolOutcome {
        fail(tool, BridgeCode.staleId, BrowserCopy.failure(code: BridgeCode.staleId, language()))
    }

    private func changed(_ tool: BrowserTool) -> ParentToolOutcome {
        fail(tool, BridgeCode.targetChanged, BrowserCopy.failure(code: BridgeCode.targetChanged, language()))
    }
}

/// The host painted on the sheet, as the verified origin spells it: ASCII
/// only (a non-ASCII or percent-encoded host is refused, never decoded), with
/// the scheme written out whenever it is not https so an http page never reads
/// as a secure one. Never a URL that carries userinfo.
private enum PageHost {
    static func display(of origin: String) -> String? {
        // `URL`, not `URLComponents`: the latter decodes punycode into Unicode.
        let text = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty,
              host.unicodeScalars.allSatisfy({ $0.value < 128 }), !host.contains("%")
        else { return nil }
        let prefix = scheme == "https" ? "" : "\(scheme)://"
        guard let port = url.port, port != (scheme == "https" ? 443 : 80) else { return prefix + host }
        return "\(prefix)\(host):\(port)"
    }
}
