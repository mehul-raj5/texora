import Foundation

/// One long-running `claude -p` process speaking stream-json over stdin/stdout.
/// Events are delivered on the main queue as parsed JSON dictionaries.
final class ClaudeSession: @unchecked Sendable {
    struct Config {
        var executable: String
        var workingDirectory: URL
        var environment: [String: String]
        var model: String?
        var resumeSessionID: String?
        var systemPrompt: String
        var fullAccess: Bool
        var allowScripts: Bool
        var addDirs: [String] = []
    }

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var buffer = Data()
    private var stderrTail = ""
    private let lock = NSLock()
    private var requestCounter = 0

    var onEvent: (([String: Any]) -> Void)?
    var onExit: ((Int32, String) -> Void)?

    var isRunning: Bool { process.isRunning }

    static func arguments(for c: Config) -> [String] {
        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-prompts", "none",
            "--strict-mcp-config",
            "--setting-sources", "project,local",
            "--disable-slash-commands",
            "--append-system-prompt", c.systemPrompt,
        ]
        let tools = ["Read", "Edit", "Write", "Glob", "Grep", "Bash", "WebSearch", "WebFetch", "TodoWrite"]
        if c.fullAccess {
            args += ["--permission-mode", "bypassPermissions"]
        } else {
            args += ["--permission-mode", "acceptEdits"]
            // Read/Edit/Write are deliberately NOT allow-listed: acceptEdits already permits them inside the
            // project folder, and leaving them out means anything outside the folder is denied.
            var allowed = ["WebSearch", "WebFetch"]
            let texTools = ["latexmk", "pdflatex", "xelatex", "lualatex", "bibtex", "biber", "tectonic",
                            "kpsewhich", "texcount", "makeindex", "makeglossaries", "synctex", "detex", "chktex", "lacheck"]
            let fileTools = ["ls", "wc", "head", "tail", "grep", "find", "sort", "uniq", "diff", "file", "mkdir", "cp", "mv", "touch", "cat", "sed", "awk", "unzip", "zip"]
            var cmds = texTools + fileTools
            if c.allowScripts { cmds += ["python3", "python", "Rscript", "gnuplot", "julia", "node", "pip3", "uv"] }
            for cmd in cmds { allowed.append("Bash(\(cmd):*)") }
            args += ["--allowedTools"] + allowed
            // Broad scans of the home folder or disk trip macOS privacy prompts (Desktop, Downloads, Photos).
            args += ["--disallowedTools"] + ["find ~", "find /", "find $HOME", "ls ~", "ls /Users", "mdfind", "du ~", "grep -r ~", "rg ~"].map { "Bash(\($0):*)" }
        }
        args += ["--tools", tools.joined(separator: ",")]
        if let m = c.model, !m.isEmpty { args += ["--model", m] }
        if let r = c.resumeSessionID, !r.isEmpty { args += ["--resume", r] }
        for d in c.addDirs { args += ["--add-dir", d] }
        return args
    }

    init(config: Config) {
        process.executableURL = URL(fileURLWithPath: config.executable)
        process.arguments = Self.arguments(for: config)
        process.currentDirectoryURL = config.workingDirectory
        process.environment = config.environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    func start() throws {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self else { return }
            if data.isEmpty { h.readabilityHandler = nil; return }
            self.consume(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self else { return }
            if data.isEmpty { h.readabilityHandler = nil; return }
            self.lock.lock()
            self.stderrTail = String((self.stderrTail + String(decoding: data, as: UTF8.self)).suffix(4000))
            self.lock.unlock()
        }
        process.terminationHandler = { [weak self] p in
            guard let self else { return }
            self.lock.lock(); let tail = self.stderrTail; self.lock.unlock()
            let status = p.terminationStatus
            DispatchQueue.main.async { self.onExit?(status, tail) }
        }
        try process.run()
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: buffer.startIndex..<nl))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines where !line.isEmpty {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            DispatchQueue.main.async { [weak self] in self?.onEvent?(obj) }
        }
    }

    private func write(_ object: [String: Any]) {
        guard process.isRunning,
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        do { try stdinPipe.fileHandleForWriting.write(contentsOf: data) } catch {}
    }

    /// Sends one user turn. `content` is a list of Anthropic content blocks (text / image).
    func send(content: [[String: Any]]) {
        write(["type": "user", "message": ["role": "user", "content": content]])
    }

    func interrupt() {
        lock.lock(); requestCounter += 1; let id = "req_\(requestCounter)"; lock.unlock()
        write(["type": "control_request", "request_id": id, "request": ["subtype": "interrupt"]])
    }

    func terminate() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
