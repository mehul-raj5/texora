import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers

struct EditorSelection: Equatable {
    var path: String
    var fromLine: Int
    var toLine: Int
    var text: String
}

/// A request from the "Ask Claude" popup, opened from a selection in the editor or the PDF.
struct AskRequest: Identifiable, Equatable {
    enum Source: Equatable { case editor, pdf }
    let id = UUID()
    var source: Source
    var path: String?
    var fromLine: Int?
    var toLine: Int?
    var text: String
    var anchor: CGRect          // in the coordinate space of the source pane (top-left origin)
    var page: Int?
    var instruction = ""
    var replyID: UUID?
}

struct PDFSelectionInfo: Equatable {
    var text: String
    var page: Int
    var rectInView: CGRect      // top-left origin within the PDF pane
    var pagePoint: CGPoint      // top-left origin within the page, PDF points
}

@MainActor
@Observable
final class WorkspaceModel {
    enum SidebarTab: String { case files, outline, history }
    enum Layout: String { case code, split, pdf }
    enum CompileReason { case manual, save, claude, open }

    struct Doc {
        var saved: String
        var text: String
        var conflictDisk: String?
        var isDirty: Bool { text != saved }
    }

    let projectID: UUID
    var record: ProjectRecord
    @ObservationIgnored unowned let app: AppModel
    let root: URL

    // Layout
    var sidebarTab: SidebarTab = .files
    var layout: Layout = .split
    var chatVisible = true
    var issuesVisible = false
    var splitFraction: CGFloat = 0.5
    var chatWidth: CGFloat = 380

    // Files and documents
    var tree: [FileNode] = []
    var files: [String] = []
    var expandedFolders: Set<String> = []
    var docs: [String: Doc] = [:]
    var openTabs: [String] = []
    var activePath: String?

    // Editor
    @ObservationIgnored let editor = EditorBridge()
    var editorReady = false
    var cursorLine = 1
    var selection: EditorSelection?

    // Outline and index
    var outlineFlat: [OutlineItem] = []
    var outlineTree: [OutlineItem] = []
    var activeOutlineID: String?

    // Services
    let compiler = CompileController()
    @ObservationIgnored let historyService: HistoryService
    let history: HistoryController
    let chat = ChatController()
    @ObservationIgnored let pdf = PDFController()

    // Popups
    var ask: AskRequest?
    var pdfSelection: PDFSelectionInfo?
    var showExport = false
    var diffEntry: HistoryEntry?
    var chatSelection: EditorSelection?   // selection attached to the next chat message (⌘L)

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    @ObservationIgnored private var userSnapshotTask: Task<Void, Never>?
    @ObservationIgnored private var recentlySaved: [String: Date] = [:]

    init(record: ProjectRecord, app: AppModel) {
        self.projectID = record.id
        self.record = record
        self.app = app
        self.root = record.url.standardizedFileURL
        self.historyService = HistoryService(projectID: record.id, workTree: record.url.standardizedFileURL)
        self.history = HistoryController(service: historyService)
        chat.workspace = self
        if record.mainFile == nil {
            let main = ProjectImporter.detectMainFiles(in: root).first
            self.record.mainFile = main
            app.library.update(record.id) { $0.mainFile = main }
        }
        editor.onMessage = { [weak self] msg in self?.handleEditorMessage(msg) }
        pdf.onInverseSync = { [weak self] page, point in self?.inverseSync(page: page, point: point) }
        pdf.onSelection = { [weak self] info in self?.pdfSelection = info }
        rebuildTree()
        if let main = self.record.mainFile, files.contains(main) {
            open(main)
            expandFolders(containing: main)
        }
        compiler.loadExisting(root: root, mainFile: self.record.mainFile ?? "main.tex")
        watcher = FileWatcher(url: root) { [weak self] paths in self?.filesChanged(paths) }
        chat.loadInitial()
        refreshIndex(immediately: true)
        Task {
            let service = historyService
            let created = await Task.detached { service.ensureRepo() }.value
            await history.snapshot(kind: created ? .created : .user, title: created ? "Project opened in Texora" : nil)
            if compiler.pdfURL == nil { compile(reason: .open) }
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        autosaveTask?.cancel()
        // Write unsaved text synchronously; the web view may already be gone.
        for (path, doc) in docs where doc.isDirty { writeFile(path, doc.text) }
        chat.persist()
        chat.endSession()
        compiler.cancel()
    }

    var mainFile: String? { record.mainFile }

    func setMainFile(_ path: String) {
        record.mainFile = path
        app.library.update(projectID) { $0.mainFile = path }
        refreshIndex(immediately: true)
        compile(reason: .manual)
    }

    var engine: TexEngine { record.engine ?? app.settings.defaultEngine }

    func setEngine(_ e: TexEngine) {
        record.engine = e
        app.library.update(projectID) { $0.engine = e }
        compile(reason: .manual)
    }

    // MARK: Files

    func rebuildTree() {
        tree = FileTreeBuilder.build(root: root)
        files = FileTreeBuilder.flatten(tree)
    }

    func expandFolders(containing path: String) {
        var parts = path.split(separator: "/").dropLast()
        while !parts.isEmpty {
            expandedFolders.insert(parts.joined(separator: "/"))
            parts = parts.dropLast()
        }
    }

    func relativePath(_ absolute: String) -> String {
        let std = URL(fileURLWithPath: absolute).standardizedFileURL.path
        let rootPath = root.path
        for prefix in [rootPath, "/private" + rootPath] where std.hasPrefix(prefix + "/") {
            return String(std.dropFirst(prefix.count + 1))
        }
        return absolute
    }

    func fileExists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    func url(for relative: String) -> URL { root.appendingPathComponent(relative) }

    private func readFile(_ path: String) -> String? {
        let u = url(for: path)
        guard let data = try? Data(contentsOf: u) else { return nil }
        if data.count > 8_000_000 { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private func writeFile(_ path: String, _ text: String) {
        recentlySaved[path] = Date()
        try? text.write(to: url(for: path), atomically: true, encoding: .utf8)
    }

    func newFile(in folder: String?, name: String, contents: String = "") {
        let rel = folder.map { "\($0)/\(name)" } ?? name
        let u = url(for: rel)
        guard !FileManager.default.fileExists(atPath: u.path) else { app.showError("“\(rel)” already exists."); return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents.write(to: u, atomically: true, encoding: .utf8)
        rebuildTree()
        if FileKind(path: rel, isDirectory: false).isEditableText { open(rel) }
    }

    func newFolder(in folder: String?, name: String) {
        let rel = folder.map { "\($0)/\(name)" } ?? name
        try? FileManager.default.createDirectory(at: url(for: rel), withIntermediateDirectories: true)
        expandedFolders.insert(rel)
        rebuildTree()
    }

    func rename(_ path: String, to newName: String) {
        let parent = (path as NSString).deletingLastPathComponent
        let newRel = parent.isEmpty ? newName : "\(parent)/\(newName)"
        guard newRel != path else { return }
        do {
            try FileManager.default.moveItem(at: url(for: path), to: url(for: newRel))
        } catch {
            app.showError("Couldn't rename: \(error.localizedDescription)")
            return
        }
        if let d = docs.removeValue(forKey: path) { docs[newRel] = d }
        openTabs = openTabs.map { $0 == path ? newRel : $0 }
        if activePath == path { activePath = newRel }
        editor.rename(from: path, to: newRel)
        if record.mainFile == path { setMainFile(newRel) }
        rebuildTree()
    }

    /// Moves a file or folder to the Trash (recoverable).
    func trash(_ path: String) {
        NSWorkspace.shared.recycle([url(for: path)]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.app.showError(error.localizedDescription); return }
                for tab in self.openTabs where tab == path || tab.hasPrefix(path + "/") { self.closeTab(tab, save: false) }
                self.rebuildTree()
            }
        }
    }

    /// Copies files from Finder into a project folder.
    func addFiles(_ urls: [URL], to folder: String?) {
        let dest = folder.map { url(for: $0) } ?? root
        for u in urls {
            let target = uniqueURL(dest.appendingPathComponent(u.lastPathComponent))
            try? FileManager.default.copyItem(at: u, to: target)
        }
        rebuildTree()
    }

    func copyChatAttachments(_ urls: [URL]) -> [SavedAttachment] {
        guard !urls.isEmpty else { return [] }
        let dir = root.appendingPathComponent("chatattachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [SavedAttachment] = []
        for u in urls {
            // Files already inside the project are referenced in place.
            let std = u.standardizedFileURL.path
            if std.hasPrefix(root.path + "/") {
                out.append(SavedAttachment(url: u, relative: relativePath(std)))
                continue
            }
            let target = uniqueURL(dir.appendingPathComponent(u.lastPathComponent))
            do {
                try FileManager.default.copyItem(at: u, to: target)
                out.append(SavedAttachment(url: target, relative: "chatattachments/\(target.lastPathComponent)"))
            } catch {
                app.showError("Couldn't attach \(u.lastPathComponent): \(error.localizedDescription)")
            }
        }
        rebuildTree()
        return out
    }

    private func uniqueURL(_ u: URL) -> URL {
        var candidate = u
        var n = 2
        let base = u.deletingPathExtension().lastPathComponent
        let ext = u.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = u.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: Tabs

    func open(_ path: String, line: Int? = nil) {
        if !openTabs.contains(path) { openTabs.append(path) }
        activePath = path
        let kind = FileKind(path: path, isDirectory: false)
        guard kind.isEditableText else { return }
        if docs[path] == nil {
            guard let text = readFile(path) else { return }
            docs[path] = Doc(saved: text, text: text)
        }
        editor.open(path: path, text: docs[path]?.text, line: line)
        pushDiagnostics()
        updateActiveOutline()
    }

    func closeTab(_ path: String, save: Bool = true) {
        if save, let d = docs[path], d.isDirty { writeFile(path, d.text) }
        let idx = openTabs.firstIndex(of: path)
        openTabs.removeAll { $0 == path }
        docs.removeValue(forKey: path)
        editor.close(path: path)
        if activePath == path {
            if let idx, !openTabs.isEmpty {
                open(openTabs[min(idx, openTabs.count - 1)])
            } else {
                activePath = nil
            }
        }
    }

    var isActiveEditable: Bool {
        activePath.map { FileKind(path: $0, isDirectory: false).isEditableText && docs[$0] != nil } ?? false
    }

    // MARK: Saving

    func save(_ path: String) {
        guard let d = docs[path], d.isDirty else { return }
        writeFile(path, d.text)
        docs[path]?.saved = d.text
        scheduleUserSnapshot()
    }

    func saveAll() async {
        let pending = await editor.collect()
        for (path, text) in pending { docs[path]?.text = text }
        for (path, d) in docs where d.isDirty { save(path) }
    }

    func saveAll() {
        Task { await saveAll() }
    }

    private func scheduleAutosave() {
        guard app.settings.autoSave else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            let anyDirty = docs.values.contains { $0.isDirty }
            guard anyDirty else { return }
            for (path, d) in docs where d.isDirty { save(path) }
            if app.settings.autoCompile && !chat.isRunning { compile(reason: .save) }
        }
    }

    /// Groups the user's saves into history entries (one per few minutes of editing).
    private func scheduleUserSnapshot() {
        userSnapshotTask?.cancel()
        userSnapshotTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !chat.isRunning else { return }
            await history.snapshot(kind: .user)
        }
    }

    func resolveConflict(_ path: String, keepMine: Bool) {
        guard var d = docs[path], let disk = d.conflictDisk else { return }
        if keepMine {
            d.conflictDisk = nil
            docs[path] = d
            writeFile(path, d.text)
            docs[path]?.saved = d.text
        } else {
            d.text = disk; d.saved = disk; d.conflictDisk = nil
            docs[path] = d
            editor.setText(path: path, text: disk, flash: true)
        }
    }

    // MARK: Disk changes

    private func filesChanged(_ paths: [String]) {
        let rels = paths.map { relativePath($0) }.filter {
            !$0.hasPrefix(".build") && !$0.hasPrefix("/") && !$0.contains("/.build/") && !$0.hasPrefix(".texora")
        }
        guard !rels.isEmpty else { return }
        let before = Set(files)
        rebuildTree()
        let structural = Set(files) != before
        for path in docs.keys where rels.contains(path) || structural {
            reloadFromDisk(path, flash: chat.isRunning)
        }
        refreshIndex()
    }

    private func reloadFromDisk(_ path: String, flash: Bool) {
        if let t = recentlySaved[path], Date().timeIntervalSince(t) < 1.0 { return }
        guard var d = docs[path] else { return }
        guard let disk = readFile(path) else {
            if !fileExists(path) { closeTab(path, save: false) }
            return
        }
        guard disk != d.saved else { return }
        if d.isDirty && disk != d.text {
            d.conflictDisk = disk
            docs[path] = d
        } else {
            d.saved = disk; d.text = disk; d.conflictDisk = nil
            docs[path] = d
            editor.setText(path: path, text: disk, flash: flash)
        }
    }

    /// Called after Claude finished a turn (or a turn was undone).
    func claudeChangedFiles(_ paths: [String]) async {
        rebuildTree()
        for p in paths where docs[p] != nil { reloadFromDisk(p, flash: true) }
        refreshIndex(immediately: true)
        let relevant = paths.contains { p in
            let k = FileKind(path: p, isDirectory: false)
            return [.tex, .bib, .style, .image, .pdf, .data, .other].contains(k)
        }
        if relevant { compile(reason: .claude) }
        await history.reload()
    }

    // MARK: Compile

    func compile(reason: CompileReason) {
        guard let main = record.mainFile else {
            compiler.status = .unavailable
            compiler.detail = "Choose a main file: right-click a .tex file and pick “Set as main file”."
            return
        }
        Task {
            if reason == .manual || reason == .claude { await saveAll() }
            let job = CompileController.Job(root: root, mainFile: main, engine: engine,
                                            tools: app.tools, texBinOverride: app.settings.texBinOverride)
            await compiler.compile(job)
            pushDiagnostics()
            if !compiler.errors.isEmpty && reason == .manual { issuesVisible = true }
        }
    }

    func pushDiagnostics() {
        guard let path = activePath else { return }
        let diags: [[String: Any]] = compiler.issues.filter { $0.file == path && $0.line != nil && $0.severity != .badbox }.map {
            ["line": $0.line ?? 1, "severity": $0.severity == .error ? "error" : "warning", "message": $0.message]
        }
        editor.setDiagnostics(path: path, diags)
    }

    func reveal(issue: CompileIssue) {
        guard let file = issue.file, files.contains(file) else { return }
        open(file, line: issue.line)
        if let line = issue.line { editor.reveal(from: line) }
    }

    // MARK: SyncTeX

    func forwardSync(path: String, line: Int) {
        guard let st = compiler.synctex, let hit = st.forward(file: path, line: line) else { return }
        if layout == .code { layout = .split }
        pdf.highlight(page: hit.page, rect: hit.rect)
    }

    private func inverseSync(page: Int, point: CGPoint) {
        guard let st = compiler.synctex, let hit = st.inverse(page: page, point: point) else { return }
        guard files.contains(hit.file) else { return }
        if layout == .pdf { layout = .split }
        open(hit.file, line: hit.line)
        editor.reveal(from: hit.line)
    }

    func jump(to item: OutlineItem) {
        open(item.file, line: item.line)
        editor.reveal(from: item.line)
        forwardSync(path: item.file, line: item.line)
    }

    // MARK: Outline and completions

    func refreshIndex(immediately: Bool = false) {
        indexTask?.cancel()
        let texts = docs.mapValues(\.text)
        let rootURL = root
        let main = record.mainFile
        let fileList = files
        indexTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            let result = await Task.detached { () -> ([OutlineItem], [LabelInfo], [BibEntry], [(String, Int)]) in
                let provider: (String) -> String? = { path in
                    if let t = texts[path] { return t }
                    return try? String(contentsOf: rootURL.appendingPathComponent(path), encoding: .utf8)
                }
                let outline = ProjectIndex.outline(root: rootURL, mainFile: main, text: provider)
                let labels = ProjectIndex.labels(root: rootURL, files: fileList, text: provider)
                let bib = ProjectIndex.bibEntries(root: rootURL, files: fileList)
                let cmds = ProjectIndex.userCommands(files: fileList, text: provider)
                return (outline, labels, bib, cmds)
            }.value
            guard !Task.isCancelled else { return }
            outlineFlat = result.0
            outlineTree = ProjectIndex.tree(result.0)
            updateActiveOutline()
            editor.setCompletions([
                "labels": result.1.map { ["label": $0.label, "file": $0.file, "line": $0.line, "context": $0.context] },
                "cites": result.2.map { ["key": $0.key, "title": $0.title, "author": $0.author, "year": $0.year] },
                "files": fileList,
                "commands": result.3.map { ["name": $0.0, "args": $0.1] },
            ])
        }
    }

    private func updateActiveOutline() {
        guard let path = activePath else { activeOutlineID = nil; return }
        activeOutlineID = outlineFlat.last { $0.file == path && $0.line <= cursorLine }?.id
    }

    // MARK: Editor messages

    private func handleEditorMessage(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }
        switch type {
        case "loaded":
            let s = app.settings
            editor.initialize(theme: app.themes.current, fontSize: s.editorFontSize, wrap: s.lineWrap, vim: s.vimMode)
        case "ready":
            editor.markReady()
            editorReady = true
            if let p = activePath, docs[p] != nil { editor.open(path: p, text: docs[p]?.text) }
            refreshIndex(immediately: true)
            pushDiagnostics()
        case "change":
            guard let path = msg["path"] as? String, let text = msg["text"] as? String, docs[path] != nil else { return }
            docs[path]?.text = text
            scheduleAutosave()
            if path.hasSuffix(".tex") || path.hasSuffix(".bib") { refreshIndex() }
        case "cursor":
            if let line = msg["line"] as? Int { cursorLine = line }
            if let path = msg["path"] as? String {
                let text = msg["selText"] as? String ?? ""
                let from = msg["fromLine"] as? Int ?? cursorLine
                let to = msg["toLine"] as? Int ?? cursorLine
                selection = text.isEmpty ? nil : EditorSelection(path: path, fromLine: from, toLine: to, text: text)
            }
            updateActiveOutline()
        case "command":
            switch msg["name"] as? String {
            case "save", "compile": compile(reason: .manual)
            case "toggleSidebar": app.sidebarVisible.toggle()
            case "toggleChat": chatVisible.toggle()
            default: break
            }
        case "askClaude":
            guard let text = msg["text"] as? String, !text.isEmpty else { return }
            let r = msg["rect"] as? [String: Any]
            let rect = CGRect(x: r?["x"] as? Double ?? 40, y: r?["y"] as? Double ?? 40,
                              width: r?["width"] as? Double ?? 10, height: r?["height"] as? Double ?? 18)
            pdfSelection = nil
            ask = AskRequest(source: .editor, path: msg["path"] as? String, fromLine: msg["fromLine"] as? Int,
                             toLine: msg["toLine"] as? Int, text: text, anchor: rect)
        case "sendToChat":
            guard let text = msg["text"] as? String, !text.isEmpty, let path = msg["path"] as? String else { return }
            chatSelection = EditorSelection(path: path, fromLine: msg["fromLine"] as? Int ?? 1,
                                            toLine: msg["toLine"] as? Int ?? 1, text: text)
            chatVisible = true
            NotificationCenter.default.post(name: .focusChatInput, object: nil)
        case "syncToPdf":
            if let path = msg["path"] as? String, let line = msg["line"] as? Int { forwardSync(path: path, line: line) }
        default:
            break
        }
    }

    // MARK: Ask Claude

    func askClaudeAboutSelection() {
        if let s = pdfSelection {
            askFromPDF(s)
        } else {
            editor.hidePill()
            Task {
                if let info = await editor.selection(), let text = info["text"] as? String, !text.isEmpty {
                    handleEditorMessage(info.merging(["type": "askClaude"]) { _, b in b })
                }
            }
        }
    }

    func askFromPDF(_ s: PDFSelectionInfo) {
        var req = AskRequest(source: .pdf, path: nil, fromLine: nil, toLine: nil, text: s.text, anchor: s.rectInView, page: s.page)
        if let st = compiler.synctex, let hit = st.inverse(page: s.page, point: s.pagePoint) {
            req.path = hit.file
            let range = locate(text: s.text, in: hit.file, near: hit.line)
            req.fromLine = range.lowerBound
            req.toLine = range.upperBound
        }
        ask = req
    }

    /// Finds the source lines that best match text selected in the PDF, near a SyncTeX hint.
    func locate(text: String, in file: String, near line: Int) -> ClosedRange<Int> {
        guard let content = docs[file]?.text ?? readFile(file) else { return line...line }
        let lines = content.components(separatedBy: "\n")
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 }
        guard !words.isEmpty, !lines.isEmpty else { return line...line }
        let lo = max(0, line - 60), hi = min(lines.count - 1, line + 60)
        guard lo <= hi else { return line...line }
        func score(_ i: Int, _ ws: ArraySlice<String>) -> Int {
            let l = lines[i].lowercased()
            return ws.reduce(0) { $0 + (l.contains($1) ? 1 : 0) }
        }
        let head = words.prefix(5), tail = words.suffix(5)
        var bestStart = min(max(line - 1, lo), hi), bestStartScore = Int.min
        for i in lo...hi {
            let s1 = score(i, head) * 10 - abs(i - (line - 1))
            if s1 > bestStartScore { bestStartScore = s1; bestStart = i }
        }
        var bestEnd = bestStart, bestEndScore = Int.min
        for i in bestStart...min(hi, bestStart + 40) {
            let s2 = score(i, tail) * 10 - abs(i - bestStart) / 4
            if s2 > bestEndScore { bestEndScore = s2; bestEnd = i }
        }
        return (bestStart + 1)...max(bestStart + 1, bestEnd + 1)
    }

    func submitAsk(_ instruction: String) {
        guard var req = ask else { return }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var ctx = ""
        var label: String?
        if req.source == .editor, let path = req.path, let a = req.fromLine, let b = req.toLine {
            label = "\(path) · \(a == b ? "line \(a)" : "lines \(a)–\(b)")"
            ctx = "The user highlighted this text in \(path), \(a == b ? "line \(a)" : "lines \(a)–\(b)"):\n```latex\n\(req.text)\n```"
        } else {
            let pageLabel = req.page.map { "page \($0 + 1) of the PDF" } ?? "the PDF"
            if let path = req.path, let a = req.fromLine, let b = req.toLine {
                label = "PDF p.\((req.page ?? 0) + 1) → \(path) · lines \(a)–\(b)"
                ctx = "The user highlighted this text on \(pageLabel). It comes from \(path), around lines \(a)–\(b) (find the exact source):\n```\n\(req.text)\n```"
            } else {
                label = "PDF p.\((req.page ?? 0) + 1)"
                ctx = "The user highlighted this text on \(pageLabel). Find where it comes from in the source:\n```\n\(req.text)\n```"
            }
        }
        ctx += "\nApply their request to exactly this passage (edit the source file directly). Keep the change focused, keep LaTeX valid, and reply in one or two sentences."
        req.instruction = trimmed
        req.replyID = chat.send(text: trimmed, context: .init(label: label, text: ctx), fromPopup: true)
        ask = req
    }

    func sendSelectionToChat() {
        editor.hidePill()
        Task {
            if let info = await editor.selection(), let text = info["text"] as? String, !text.isEmpty {
                handleEditorMessage(info.merging(["type": "sendToChat"]) { _, b in b })
            }
        }
    }

    // MARK: Claude prompt

    func claudeSystemPrompt() -> String {
        let main = record.mainFile ?? "(not set)"
        let compileCmd: String
        if let cmd = compiler.resolveCommand(.init(root: root, mainFile: main, engine: engine, tools: app.tools, texBinOverride: app.settings.texBinOverride)) {
            compileCmd = ([(cmd.executable as NSString).lastPathComponent] + cmd.args).joined(separator: " ")
        } else {
            compileCmd = "(no LaTeX engine installed)"
        }
        return """
        You are the writing and LaTeX assistant built into Texora, a LaTeX editor for macOS. The user talks to you through a chat panel and an "Ask Claude" popup inside the app. They cannot see your tool calls, terminal output, or diffs, so describe what you did in plain words.

        Project: \(record.name)
        Project folder (your working directory): \(root.path)
        Main file: \(main)
        Compiler: \(engine.label). To check your work you may run: \(compileCmd)

        How to work:
        - Make requested changes by editing the files directly. Prefer small, targeted edits; keep the author's voice, structure and formatting.
        - Afterwards, say briefly what you changed and where (file and section), in 1–4 sentences. Don't paste whole files or long diffs unless asked.
        - The app saves the user's open files before each message and recompiles the PDF automatically after you finish. Build output lives in .build/; never edit files there.
        - Files the user attaches in chat are copied into chatattachments/ in the project.
        - Keep the document compiling: escape special characters, don't add packages unnecessarily, and match the existing bibliography style.
        - Only touch files inside the project folder. Don't delete or rename files unless asked.
        - If the user asks a question or wants feedback, answer concisely without editing files.
        """
    }

    // MARK: Export

    func exportZip() { showExport = true }

    func performExport(options: ExportOptions, to dest: URL? = nil) {
        var destination = dest
        if destination == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.zip]
            panel.nameFieldStringValue = "\(record.name).zip"
            panel.message = "Export the whole project as a ZIP"
            guard panel.runModal() == .OK, let u = panel.url else { return }
            destination = u
        }
        guard let target = destination else { return }
        let reveal = dest == nil
        Task {
            await saveAll()
            app.busyMessage = "Exporting…"
            let rootURL = root, name = record.name, main = record.mainFile
            let error: String? = await Task.detached {
                do { try ExportService.exportZip(root: rootURL, projectName: name, mainFile: main, to: target, options: options); return nil }
                catch { return error.localizedDescription }
            }.value
            app.busyMessage = nil
            if let error { app.showError(error) } else if reveal { NSWorkspace.shared.activateFileViewerSelecting([target]) }
        }
    }

    func exportPDF() {
        guard let pdfURL = compiler.pdfURL, FileManager.default.fileExists(atPath: pdfURL.path) else {
            app.showError("There's no PDF yet. Press ⌘S to compile first.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(record.name).pdf"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: pdfURL, to: dest) } catch { app.showError(error.localizedDescription) }
    }

    // MARK: History

    func promptCheckpoint() {
        let alert = NSAlert()
        alert.messageText = "Save a checkpoint"
        alert.informativeText = "Name this version so it's easy to find in History."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Before submission"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        saveCheckpoint(named: field.stringValue)
    }

    func saveCheckpoint(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        Task {
            await saveAll()
            let service = historyService
            _ = await Task.detached { service.snapshot(kind: .checkpoint, title: "⚑ " + (name.isEmpty ? "Checkpoint" : name), force: true) }.value
            await history.reload()
        }
    }

    func restoreProject(to entry: HistoryEntry) {
        Task {
            await saveAll()
            await history.snapshot(kind: .user)
            let service = historyService
            await Task.detached { service.restoreProject(to: entry.id) }.value
            await history.snapshot(kind: .restore, title: "Restored to “\(entry.title)”")
            rebuildTree()
            await claudeChangedFiles(Array(Set(files + Array(docs.keys))))
        }
    }

    func restoreFile(_ path: String, to entry: HistoryEntry) {
        Task {
            await saveAll()
            await history.snapshot(kind: .user)
            let service = historyService
            await Task.detached { service.restoreFile(path, to: entry.id) }.value
            await history.snapshot(kind: .restore, title: "Restored \((path as NSString).lastPathComponent) from “\(entry.title)”")
            await claudeChangedFiles([path])
        }
    }
}

extension Notification.Name {
    static let focusChatInput = Notification.Name("texora.focusChatInput")
}
