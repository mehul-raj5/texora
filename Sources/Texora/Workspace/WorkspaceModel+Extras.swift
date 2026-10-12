import Foundation
import AppKit

extension WorkspaceModel {
    func fixErrorsPrompt() -> String {
        let list = compiler.errors.prefix(15).map { e -> String in
            var s = "- "
            if let f = e.file { s += f + (e.line.map { ":\($0)" } ?? "") + ": " }
            s += e.message
            return s
        }.joined(separator: "\n")
        return "The project doesn't compile. Please fix these errors:\n\(list)"
    }

    func promptNewFile(in folder: String?) {
        if let name = askForName(title: "New file", placeholder: "section.tex") {
            let contents = name.hasSuffix(".tex") ? "% \(name)\n\n" : ""
            newFile(in: folder, name: name, contents: contents)
        }
    }

    func promptNewFolder(in folder: String?) {
        if let name = askForName(title: "New folder", placeholder: "figures") { newFolder(in: folder, name: name) }
    }

    // MARK: Developer automation (only reachable when launched with --automation)

    func handleAutomation(cmd: String, arg: String, arg2: String, info: [String: Any]) {
        switch cmd {
        case "openFile":
            open(arg, line: Int(arg2))
        case "compile":
            compile(reason: .manual)
        case "chat":
            chatVisible = true
            let attachments = chat.pendingAttachments
            if chat.send(text: arg, attachments: attachments) != nil { chat.pendingAttachments = [] }
        case "newChat":
            chat.newChat()
        case "stop":
            chat.stop()
        case "layout":
            if let l = Layout(rawValue: arg) { layout = l }
        case "tab":
            if let t = SidebarTab(rawValue: arg) { sidebarTab = t }
        case "chatVisible":
            chatVisible = arg != "false"
        case "issues":
            issuesVisible = arg != "false"
        case "select":
            // select <fromLine> <toLine> in the active editor, then open the Ask popup
            let from = Int(arg) ?? 1, to = Int(arg2) ?? from
            editor.reveal(from: from, to: to, select: true)
            if (info["ask"] as? String) == "1" {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    askClaudeAboutSelection()
                }
            }
        case "ask":
            submitAsk(arg)
        case "askPDF":
            // askPDF <page> <text>: simulates selecting text on a PDF page
            let page = Int(arg) ?? 0
            if let doc = pdf.view?.document, let p = doc.page(at: page), let sel = doc.findString(arg2, withOptions: .caseInsensitive).first(where: { $0.pages.contains(p) }) ?? doc.findString(arg2, withOptions: .caseInsensitive).first {
                pdf.view?.setCurrentSelection(sel, animate: false)
                pdf.view?.go(to: sel)
            }
        case "askSelection":
            askClaudeAboutSelection()
        case "syncInverse":
            // syncInverse <page> <x,y> in top-left PDF points
            let parts = arg2.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { pdf.onInverseSync?(Int(arg) ?? 0, CGPoint(x: parts[0], y: parts[1])) }
        case "closeAsk":
            ask = nil
        case "undoLast":
            if let m = chat.messages.last(where: { !$0.changedFiles.isEmpty && !$0.undone }) { chat.undo(messageID: m.id) }
        case "export":
            performExport(options: ExportOptions(includePDF: true, includeBbl: info["bbl"] as? String == "1",
                                                 includeChatAttachments: info["attachments"] as? String == "1"),
                          to: URL(fileURLWithPath: arg))
        case "restore":
            if let idx = Int(arg), idx < history.entries.count { restoreProject(to: history.entries[idx]) }
        case "diff":
            if let idx = Int(arg), idx < history.entries.count { diffEntry = history.entries[idx] }
        case "closeDiff":
            diffEntry = nil
        case "checkpoint":
            saveCheckpoint(named: arg)
        case "insert":
            editor.insert(arg)
        case "syncForward":
            forwardSync(path: arg, line: Int(arg2) ?? 1)
        case "attach":
            chat.pendingAttachments.append(URL(fileURLWithPath: arg))
        case "dump":
            dumpState(to: URL(fileURLWithPath: arg))
        default:
            break
        }
    }

    /// Writes a JSON summary of the workspace for tests to assert on.
    func dumpState(to url: URL) {
        var state: [String: Any] = [:]
        state["project"] = record.name
        state["root"] = root.path
        state["mainFile"] = record.mainFile ?? ""
        state["files"] = files
        state["openTabs"] = openTabs
        state["activePath"] = activePath ?? ""
        state["dirty"] = docs.filter { $0.value.isDirty }.map(\.key)
        state["cursorLine"] = cursorLine
        var outline: [[String: Any]] = []
        for o in outlineFlat { outline.append(["level": o.level, "title": o.title, "file": o.file, "line": o.line]) }
        state["outline"] = outline
        state["activeOutline"] = activeOutlineID ?? ""

        var issues: [[String: Any]] = []
        for i in compiler.issues {
            issues.append(["severity": i.severity.rawValue, "message": i.message, "file": i.file ?? "", "line": i.line ?? 0])
        }
        var comp: [String: Any] = [:]
        comp["status"] = "\(compiler.status)"
        comp["engine"] = compiler.engineLabel ?? ""
        comp["pdf"] = compiler.pdfURL?.path ?? ""
        comp["pdfVersion"] = compiler.pdfVersion
        comp["duration"] = compiler.lastDuration ?? 0
        comp["detail"] = compiler.detail ?? ""
        comp["issues"] = issues
        comp["synctex"] = compiler.synctex != nil
        state["compile"] = comp

        var msgs: [[String: Any]] = []
        for m in chat.messages {
            var d: [String: Any] = [:]
            d["role"] = m.role.rawValue
            d["text"] = m.text
            d["error"] = m.isError
            d["streaming"] = m.isStreaming
            d["activities"] = m.activities.map(\.text)
            d["changed"] = m.changedFiles.map(\.path)
            d["undone"] = m.undone
            d["context"] = m.contextLabel ?? ""
            msgs.append(d)
        }
        var chatState: [String: Any] = [:]
        chatState["activeChat"] = chat.activeChatID?.uuidString ?? ""
        chatState["running"] = chat.isRunning
        chatState["status"] = chat.statusText ?? ""
        chatState["messages"] = msgs
        state["chat"] = chatState

        var hist: [[String: Any]] = []
        for e in history.entries { hist.append(["id": e.id, "kind": e.kind.rawValue, "title": e.title, "files": e.files.map(\.path)]) }
        state["history"] = hist

        if let a = ask {
            var d: [String: Any] = [:]
            d["source"] = a.source == .editor ? "editor" : "pdf"
            d["path"] = a.path ?? ""
            d["from"] = a.fromLine ?? 0
            d["to"] = a.toLine ?? 0
            d["text"] = a.text
            d["reply"] = a.replyID?.uuidString ?? ""
            state["ask"] = d
        }
        if let p = pdfSelection { state["pdfSelection"] = ["text": p.text, "page": p.page] as [String: Any] }
        state["layout"] = layout.rawValue
        state["sidebarTab"] = sidebarTab.rawValue
        state["chatVisible"] = chatVisible
        state["theme"] = app.themes.current.id
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}
