import Foundation
import Observation
import UniformTypeIdentifiers

struct ChatActivity: Codable, Hashable, Identifiable {
    var id: String
    var icon: String
    var text: String
    var detail: String?
    var done = false
    var failed = false
}

struct ChatMessage: Codable, Hashable, Identifiable {
    enum Role: String, Codable { case user, assistant, notice }
    var id = UUID()
    var role: Role
    var text: String
    var activities: [ChatActivity] = []
    var changedFiles: [FileStat] = []
    var before: String?
    var after: String?
    var undone = false
    var isError = false
    var isStreaming = false
    var contextLabel: String?
    var attachments: [String] = []
    var fromPopup = false
    var createdAt = Date()
    var duration: Double?
}


/// Chat with Claude for one project. Each chat is a resumable Claude Code session.
@MainActor
@Observable
final class ChatController {
    @ObservationIgnored weak var workspace: WorkspaceModel?

    var activeChatID: UUID?
    var messages: [ChatMessage] = []
    var isRunning = false
    var statusText: String?
    var draft = ""
    var pendingAttachments: [URL] = []
    var includeSelection = true

    @ObservationIgnored private var session: ClaudeSession?
    @ObservationIgnored private var sessionChatID: UUID?
    @ObservationIgnored private var sessionModel: String?
    @ObservationIgnored private var assistantID: UUID?
    @ObservationIgnored private var streamingBlock = ""
    @ObservationIgnored private var finishedText = ""
    @ObservationIgnored private var sawStreamText = false
    @ObservationIgnored private var turnStart = Date()
    @ObservationIgnored private var turnBefore: String?
    @ObservationIgnored private var turnPrompt = ""
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var chats: [ChatRecord] {
        guard let ws = workspace else { return [] }
        return ws.app.library.chats(for: ws.projectID)
    }

    var activeChat: ChatRecord? { chats.first { $0.id == activeChatID } }

    // MARK: Chats

    func loadInitial() {
        if let first = chats.first { select(chatID: first.id) }
    }

    func select(chatID: UUID) {
        guard chatID != activeChatID else { return }
        if isRunning { stop() }
        persist()
        activeChatID = chatID
        messages = Self.load(chatID)
        if sessionChatID != chatID { endSession() }
    }

    func newChat() {
        guard let ws = workspace else { return }
        if isRunning { stop() }
        persist()
        let c = ws.app.library.addChat(projectID: ws.projectID)
        activeChatID = c.id
        messages = []
        endSession()
    }

    func deleteChat(_ id: UUID) {
        guard let ws = workspace else { return }
        if id == activeChatID {
            if isRunning { stop() }
            endSession()
            activeChatID = nil
            messages = []
        }
        ws.app.library.removeChat(id)
    }

    func endSession() {
        session?.terminate()
        session = nil
        sessionChatID = nil
    }

    // MARK: Sending

    struct Context {
        var label: String?
        var text: String
    }

    /// Sends a message. Returns the id of the assistant message that will hold the reply.
    @discardableResult
    func send(text: String, context: Context? = nil, attachments: [URL] = [], fromPopup: Bool = false) -> UUID? {
        guard let ws = workspace else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !isRunning else { return nil }

        if activeChatID == nil { newChat() }
        guard let chatID = activeChatID else { return nil }

        // Copy attachments into <project>/chatattachments/.
        let saved = ws.copyChatAttachments(attachments)

        var userMsg = ChatMessage(role: .user, text: trimmed)
        userMsg.contextLabel = context?.label
        userMsg.attachments = saved.map(\.relative)
        userMsg.fromPopup = fromPopup
        var reply = ChatMessage(role: .assistant, text: "")
        reply.isStreaming = true
        messages.append(userMsg)
        messages.append(reply)
        assistantID = reply.id
        isRunning = true
        statusText = "Thinking…"
        streamingBlock = ""
        finishedText = ""
        sawStreamText = false
        interrupted = false
        turnStart = Date()
        turnPrompt = trimmed

        if (ws.app.library.chats.first { $0.id == chatID }?.title ?? "New chat") == "New chat" {
            let title = trimmed.isEmpty ? "Attached files" : String(trimmed.prefix(60))
            ws.app.library.updateChat(chatID) { $0.title = title }
        }
        ws.app.library.updateChat(chatID) { $0.updatedAt = Date() }

        // Build the content blocks.
        var body = ""
        if let context { body += context.text + "\n\n" }
        body += trimmed
        if !saved.isEmpty {
            body += "\n\nAttached files (saved in the project under chatattachments/): "
                + saved.map(\.relative).joined(separator: ", ")
        }
        var content: [[String: Any]] = [["type": "text", "text": body]]
        for a in saved where a.isImage {
            if let data = try? Data(contentsOf: a.url), data.count < 4_500_000 {
                content.append(["type": "image", "source": ["type": "base64", "media_type": a.mediaType, "data": data.base64EncodedString()]])
            }
        }

        Task {
            await ws.saveAll()
            turnBefore = await ws.history.snapshot(kind: .user)
            guard ensureSession() else { return }
            session?.send(content: content)
        }
        return reply.id
    }

    func stop() {
        guard isRunning else { return }
        interrupted = true
        statusText = "Stopping…"
        session?.interrupt()
        // If the process doesn't respond, finish anyway.
        Task {
            try? await Task.sleep(for: .seconds(6))
            if isRunning { await finishTurn(resultText: nil, isError: false) }
        }
    }

    private func ensureSession() -> Bool {
        guard let ws = workspace, let chatID = activeChatID else { return false }
        let modelName = ws.app.settings.claudeModel.rawValue
        if let s = session, s.isRunning, sessionChatID == chatID, sessionModel == modelName { return true }
        endSession()
        guard let exe = ws.app.tools.find("claude", override: ws.app.settings.claudePathOverride) else {
            failTurn("Claude Code isn't installed or couldn't be found. Install it from claude.com/claude-code, or set its path in Settings → Claude.")
            return false
        }
        let resume = ws.app.library.chats.first { $0.id == chatID }?.sessionID
        let config = ClaudeSession.Config(
            executable: exe,
            workingDirectory: ws.root,
            environment: ws.app.tools.environment,
            model: modelName.isEmpty ? nil : modelName,
            resumeSessionID: resume,
            systemPrompt: ws.claudeSystemPrompt(),
            fullAccess: ws.app.settings.claudeAccess == .full,
            allowScripts: ws.app.settings.allowScripts)
        let s = ClaudeSession(config: config)
        s.onEvent = { [weak self] e in self?.handle(e) }
        s.onExit = { [weak self] status, tail in self?.sessionExited(status: status, stderr: tail) }
        do {
            try s.start()
        } catch {
            failTurn("Couldn't start Claude: \(error.localizedDescription)")
            return false
        }
        session = s
        sessionChatID = chatID
        sessionModel = modelName
        return true
    }

    private func sessionExited(status: Int32, stderr: String) {
        session = nil
        sessionChatID = nil
        guard isRunning else { return }
        let lower = stderr.lowercased()
        var msg = "Claude stopped unexpectedly."
        if lower.contains("not logged in") || lower.contains("login") || lower.contains("authenticat") {
            msg = "Claude Code isn't signed in. Open Terminal, run `claude`, and sign in, then try again."
        } else if lower.contains("session") && lower.contains("not found") {
            if let id = activeChatID { workspace?.app.library.updateChat(id) { $0.sessionID = nil } }
            msg = "That conversation couldn't be resumed, so the next message starts a fresh session."
        } else if !stderr.isEmpty {
            msg += "\n\n" + String(stderr.suffix(600))
        }
        failTurn(msg)
    }

    private func failTurn(_ text: String) {
        updateAssistant { m in
            m.text = text
            m.isError = true
            m.isStreaming = false
        }
        isRunning = false
        statusText = nil
        persist()
    }

    // MARK: Events

    private func handle(_ e: [String: Any]) {
        guard let type = e["type"] as? String else { return }
        switch type {
        case "system":
            if (e["subtype"] as? String) == "init", let sid = e["session_id"] as? String, let chatID = sessionChatID {
                workspace?.app.library.updateChat(chatID) { $0.sessionID = sid }
            }
        case "stream_event":
            guard let ev = e["event"] as? [String: Any], let et = ev["type"] as? String else { return }
            if et == "content_block_start", let block = ev["content_block"] as? [String: Any] {
                let bt = block["type"] as? String
                if bt == "text" { streamingBlock = "" }
                if bt == "thinking" { statusText = "Thinking…" }
                if bt == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                    let (icon, text, _) = describeTool(name: name, input: [:])
                    addActivity(ChatActivity(id: id, icon: icon, text: text))
                    statusText = text
                }
            } else if et == "content_block_delta", let delta = ev["delta"] as? [String: Any] {
                if (delta["type"] as? String) == "text_delta", let t = delta["text"] as? String {
                    streamingBlock += t
                    sawStreamText = true
                    statusText = nil
                    let combined = join(finishedText, streamingBlock)
                    updateAssistant { $0.text = combined }
                }
            } else if et == "content_block_stop" {
                if !streamingBlock.isEmpty {
                    finishedText = join(finishedText, streamingBlock)
                    streamingBlock = ""
                }
            }
        case "assistant":
            guard let msg = e["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { return }
            for block in content {
                let bt = block["type"] as? String
                if bt == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    let (icon, text, detail) = describeTool(name: name, input: input)
                    if activityIndex(id) == nil { addActivity(ChatActivity(id: id, icon: icon, text: text)) }
                    updateActivity(id) { $0.icon = icon; $0.text = text; $0.detail = detail }
                    statusText = text
                } else if bt == "text", !sawStreamText, let t = block["text"] as? String {
                    // No partial stream for this block (e.g. older CLI): use the full text.
                    finishedText = join(finishedText, t)
                    let combined = finishedText
                    updateAssistant { $0.text = combined }
                }
            }
            sawStreamText = false
        case "user":
            guard let msg = e["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { return }
            for block in content where (block["type"] as? String) == "tool_result" {
                if let id = block["tool_use_id"] as? String {
                    let failed = (block["is_error"] as? Bool) ?? false
                    updateActivity(id) { $0.done = true; $0.failed = failed }
                }
            }
            statusText = "Thinking…"
        case "result":
            let isError = (e["is_error"] as? Bool) ?? false
            let text = e["result"] as? String
            Task { await finishTurn(resultText: text, isError: isError && !interrupted) }
        default:
            break
        }
    }

    private func finishTurn(resultText: String?, isError: Bool) async {
        guard isRunning else { return }
        isRunning = false
        statusText = nil
        if !streamingBlock.isEmpty { finishedText = join(finishedText, streamingBlock); streamingBlock = "" }
        let duration = Date().timeIntervalSince(turnStart)
        let final = finishedText
        updateAssistant { m in
            m.isStreaming = false
            m.duration = duration
            for i in m.activities.indices { m.activities[i].done = true }
            if m.text.isEmpty {
                if let r = resultText, !r.isEmpty { m.text = r }
                else if self.interrupted { m.text = "Stopped." }
            } else if !final.isEmpty {
                m.text = final
            }
            if isError { m.isError = true; if m.text.isEmpty { m.text = "Something went wrong while Claude was working." } }
        }

        guard let ws = workspace else { return }
        let before = turnBefore
        let after = await ws.history.snapshot(kind: .claude, title: "✦ " + summarize(turnPrompt))
        var changed: [FileStat] = []
        if let b = before, let a = after, a != b {
            let service = ws.history.service
            changed = await Task.detached { service.changedFiles(from: b, to: a) }.value
        }
        updateAssistant { m in
            m.before = before
            m.after = after
            m.changedFiles = changed
        }
        persist()
        if !changed.isEmpty {
            await ws.claudeChangedFiles(changed.map(\.path))
        }
    }

    // MARK: Undo

    func undo(messageID: UUID) {
        guard let ws = workspace, let idx = messages.firstIndex(where: { $0.id == messageID }),
              let before = messages[idx].before, !messages[idx].changedFiles.isEmpty, !messages[idx].undone else { return }
        let files = messages[idx].changedFiles.map(\.path)
        let prompt = turnPromptFor(index: idx)
        Task {
            await ws.saveAll()
            await ws.history.snapshot(kind: .user)
            let service = ws.history.service
            await Task.detached { for f in files { service.restoreFile(f, to: before) } }.value
            await ws.history.snapshot(kind: .restore, title: "Undid Claude's change: \(summarize(prompt))")
            messages[idx].undone = true
            persist()
            await ws.claudeChangedFiles(files)
        }
    }

    private func turnPromptFor(index: Int) -> String {
        var i = index - 1
        while i >= 0 { if messages[i].role == .user { return messages[i].text }; i -= 1 }
        return ""
    }

    // MARK: Helpers

    private func summarize(_ s: String) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count > 70 ? String(one.prefix(68)) + "…" : (one.isEmpty ? "Claude edit" : one)
    }

    private func join(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + "\n\n" + b
    }

    private func updateAssistant(_ change: (inout ChatMessage) -> Void) {
        guard let id = assistantID, let i = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[i])
    }

    private func addActivity(_ a: ChatActivity) {
        updateAssistant { $0.activities.append(a) }
    }

    private func activityIndex(_ id: String) -> Int? {
        guard let aid = assistantID, let m = messages.first(where: { $0.id == aid }) else { return nil }
        return m.activities.firstIndex { $0.id == id }
    }

    private func updateActivity(_ id: String, _ change: (inout ChatActivity) -> Void) {
        updateAssistant { m in
            if let i = m.activities.firstIndex(where: { $0.id == id }) { change(&m.activities[i]) }
        }
    }

    /// Friendly wording for what Claude is doing. Raw tool calls are never shown.
    func describeTool(name: String, input: [String: Any]) -> (icon: String, text: String, detail: String?) {
        let path = (input["file_path"] as? String).map { workspace?.relativePath($0) ?? $0 }
        switch name {
        case "Read":
            return ("doc.text.magnifyingglass", path.map { "Reading \($0)" } ?? "Reading files", nil)
        case "Edit", "MultiEdit":
            return ("pencil", path.map { "Editing \($0)" } ?? "Editing", nil)
        case "Write":
            let exists = path.map { workspace?.fileExists($0) ?? false } ?? false
            return ("square.and.pencil", path.map { exists ? "Rewriting \($0)" : "Creating \($0)" } ?? "Writing a file", nil)
        case "Glob":
            return ("magnifyingglass", "Looking through the project files", nil)
        case "Grep":
            let p = input["pattern"] as? String
            return ("magnifyingglass", p.map { "Searching for “\(String($0.prefix(40)))”" } ?? "Searching the project", nil)
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            let lower = cmd.lowercased()
            if ["latexmk", "pdflatex", "xelatex", "lualatex", "tectonic"].contains(where: lower.contains) {
                return ("hammer", "Compiling to check for errors", cmd)
            }
            if ["bibtex", "biber"].contains(where: lower.contains) { return ("books.vertical", "Building the bibliography", cmd) }
            if lower.contains("python") { return ("chart.xyaxis.line", "Running a Python script", cmd) }
            if lower.contains("rscript") { return ("chart.xyaxis.line", "Running an R script", cmd) }
            if lower.contains("texcount") { return ("number", "Counting words", cmd) }
            let desc = input["description"] as? String
            return ("terminal", desc.map { String($0.prefix(60)) } ?? "Running a command", cmd)
        case "WebSearch":
            let q = input["query"] as? String
            return ("globe", q.map { "Searching the web for “\(String($0.prefix(50)))”" } ?? "Searching the web", nil)
        case "WebFetch":
            return ("globe", "Reading a web page", input["url"] as? String)
        case "TodoWrite":
            return ("checklist", "Planning the changes", nil)
        case "Task", "Agent":
            return ("person.2", "Working on a sub-task", input["description"] as? String)
        default:
            return ("sparkles", "Working…", nil)
        }
    }

    // MARK: Persistence

    func persist() {
        guard let id = activeChatID else { return }
        let msgs = messages.map { m -> ChatMessage in var c = m; c.isStreaming = false; return c }
        let url = Paths.chatsDir.appendingPathComponent("\(id.uuidString).json")
        if let data = try? LibraryStore.encoder.encode(msgs) { try? data.write(to: url, options: .atomic) }
    }

    static func load(_ id: UUID) -> [ChatMessage] {
        let url = Paths.chatsDir.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? LibraryStore.decoder.decode([ChatMessage].self, from: data)) ?? []
    }
}

struct SavedAttachment {
    let url: URL
    let relative: String
    var isImage: Bool { ["png", "jpg", "jpeg", "gif", "webp"].contains(url.pathExtension.lowercased()) }
    var mediaType: String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }
}
