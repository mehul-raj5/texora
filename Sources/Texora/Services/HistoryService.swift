import Foundation
import Observation

struct HistoryEntry: Identifiable, Hashable {
    enum Kind: String { case claude, user, restore, created, checkpoint }
    let id: String          // commit hash
    let date: Date
    let kind: Kind
    let title: String
    let files: [FileStat]
    var added: Int { files.reduce(0) { $0 + $1.added } }
    var removed: Int { files.reduce(0) { $0 + $1.removed } }
}

struct FileStat: Hashable, Identifiable, Codable {
    let path: String
    let added: Int
    let removed: Int
    var id: String { path }
}

/// Keeps every version of a project in a private git repository stored in Application Support,
/// so the project folder never gets a .git directory.
final class HistoryService: @unchecked Sendable {
    let gitDir: URL
    let workTree: URL
    private let git: String
    private let queue = DispatchQueue(label: "texora.history")

    static let excludes = """
    .build/
    .texora*
    .DS_Store
    __MACOSX/
    *.aux
    *.log
    *.synctex
    *.synctex.gz
    *.synctex(busy)
    *.fdb_latexmk
    *.fls
    *.out
    *.toc
    *.lof
    *.lot
    *.blg
    *.bcf
    *.run.xml
    *.xdv
    *.nav
    *.snm
    *.vrb
    *.idx
    *.ilg
    *.ind
    *.pdfsync

    """

    init(projectID: UUID, workTree: URL) {
        self.gitDir = Paths.historyDir.appendingPathComponent("\(projectID.uuidString).git", isDirectory: true)
        self.workTree = workTree
        self.git = FileManager.default.isExecutableFile(atPath: "/usr/bin/git") ? "/usr/bin/git" : "/opt/homebrew/bin/git"
    }

    private var baseArgs: [String] {
        ["--git-dir=\(gitDir.path)", "--work-tree=\(workTree.path)",
         "-c", "user.name=Texora", "-c", "user.email=history@texora.app",
         "-c", "core.quotepath=false", "-c", "core.precomposeunicode=true", "-c", "commit.gpgsign=false",
         "-c", "core.autocrlf=false", "-c", "core.fsmonitor=false", "-c", "gc.auto=0"]
    }

    @discardableResult
    private func run(_ args: [String], stdin: Data? = nil) -> ProcessResult {
        ProcessRunner.runSync(git, baseArgs + args, cwd: workTree, env: ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"], stdin: stdin)
    }

    var isInitialized: Bool { FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("HEAD").path) }

    /// Creates the repository on first use. Returns true if it was just created.
    @discardableResult
    func ensureRepo() -> Bool {
        if isInitialized { return false }
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        run(["init", "-q"])
        let info = gitDir.appendingPathComponent("info", isDirectory: true)
        try? FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        try? Self.excludes.write(to: info.appendingPathComponent("exclude"), atomically: true, encoding: .utf8)
        return true
    }

    var head: String? {
        let r = run(["rev-parse", "--verify", "-q", "HEAD"])
        let h = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && !h.isEmpty ? h : nil
    }

    /// Records the current state. Returns the commit that represents it (new or existing HEAD).
    /// User edits made within `mergeWindow` of the previous user entry are folded into it.
    func snapshot(kind: HistoryEntry.Kind, title: String?, mergeWindow: TimeInterval = 300, force: Bool = false) -> String? {
        queue.sync {
            ensureRepo()
            run(["add", "-A", "."])
            let changed = !run(["diff", "--cached", "--quiet"]).ok || head == nil
            if !changed && !force { return head }

            var amend = false
            if kind == .user, let h = head, let last = entry(for: h), last.kind == .user,
               Date().timeIntervalSince(last.date) < mergeWindow, parent(of: h) != nil {
                amend = true
            }
            let names: [String]
            if amend, let h = head, let p = parent(of: h) {
                names = run(["diff", "--cached", "--name-only", p]).stdout.split(separator: "\n").map(String.init)
            } else {
                names = run(["diff", "--cached", "--name-only"] + (head == nil ? [] : ["HEAD"])).stdout.split(separator: "\n").map(String.init)
            }
            let subject = title ?? Self.describeEdit(names)
            let message = "\(subject)\n\nTexora-Kind: \(kind.rawValue)\n"
            var args = ["commit", "-q", "--allow-empty", "-F", "-"]
            if amend { args.insert("--amend", at: 1) }
            let r = run(args, stdin: message.data(using: .utf8))
            return r.ok ? head : nil
        }
    }

    static func describeEdit(_ files: [String]) -> String {
        let names = files.map { ($0 as NSString).lastPathComponent }
        guard !names.isEmpty else { return "Edited files" }
        if names.count <= 3 { return "Edited " + names.joined(separator: ", ") }
        return "Edited \(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
    }

    func parent(of commit: String) -> String? {
        let r = run(["rev-parse", "--verify", "-q", "\(commit)^"])
        let s = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && !s.isEmpty ? s : nil
    }

    private func entry(for commit: String) -> HistoryEntry? {
        entries(limit: 1, from: commit).first
    }

    /// Newest first.
    func entries(limit: Int = 300, from rev: String = "HEAD") -> [HistoryEntry] {
        guard head != nil else { return [] }
        let r = run(["log", "-n", "\(limit)", "--format=%x1e%H%x1f%at%x1f%s%x1f%b%x1f", "--numstat", rev])
        var out: [HistoryEntry] = []
        for block in r.stdout.split(separator: "\u{1e}") {
            let fields = block.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count >= 5 else { continue }
            let hash = String(fields[0])
            let date = Date(timeIntervalSince1970: TimeInterval(fields[1]) ?? 0)
            let subject = String(fields[2])
            let body = String(fields[3])
            var kind = HistoryEntry.Kind.user
            for line in body.split(separator: "\n") where line.hasPrefix("Texora-Kind: ") {
                kind = HistoryEntry.Kind(rawValue: String(line.dropFirst(13)).trimmingCharacters(in: .whitespaces)) ?? .user
            }
            var files: [FileStat] = []
            for line in fields[4].split(separator: "\n") {
                let cols = line.split(separator: "\t", maxSplits: 2)
                guard cols.count == 3 else { continue }
                files.append(FileStat(path: String(cols[2]), added: Int(cols[0]) ?? 0, removed: Int(cols[1]) ?? 0))
            }
            out.append(HistoryEntry(id: hash, date: date, kind: kind, title: subject, files: files))
        }
        return out
    }

    /// Files changed between two commits.
    func changedFiles(from a: String, to b: String) -> [FileStat] {
        let r = run(["diff", "--numstat", a, b])
        return r.stdout.split(separator: "\n").compactMap { line in
            let cols = line.split(separator: "\t", maxSplits: 2)
            guard cols.count == 3 else { return nil }
            return FileStat(path: String(cols[2]), added: Int(cols[0]) ?? 0, removed: Int(cols[1]) ?? 0)
        }
    }

    /// File content at a commit, or nil if it didn't exist there.
    func content(of path: String, at commit: String) -> String? {
        let r = run(["show", "\(commit):\(path)"])
        return r.ok ? r.stdout : nil
    }

    func exists(_ path: String, at commit: String) -> Bool {
        run(["cat-file", "-e", "\(commit):\(path)"]).ok
    }

    /// Puts one file back to how it was at `commit` (deleting it if it didn't exist then).
    func restoreFile(_ path: String, to commit: String) {
        queue.sync {
            if exists(path, at: commit) {
                run(["checkout", commit, "--", path])
            } else {
                try? FileManager.default.removeItem(at: workTree.appendingPathComponent(path))
            }
        }
    }

    /// Makes the whole project match `commit`. Files added since then are removed (they stay in history).
    func restoreProject(to commit: String) {
        queue.sync {
            run(["add", "-A", "."])
            let added = run(["diff", "--name-only", "--diff-filter=A", commit, "--cached"]).stdout
                .split(separator: "\n").map(String.init)
            run(["checkout", commit, "--", "."])
            for path in added where !path.isEmpty {
                try? FileManager.default.removeItem(at: workTree.appendingPathComponent(path))
            }
        }
    }
}

/// Observable list of history entries for the sidebar.
@MainActor
@Observable
final class HistoryController {
    var entries: [HistoryEntry] = []
    var selected: HistoryEntry?
    @ObservationIgnored let service: HistoryService

    init(service: HistoryService) {
        self.service = service
    }

    func reload() async {
        let s = service
        entries = await Task.detached { s.entries() }.value
        if let sel = selected, !entries.contains(where: { $0.id == sel.id }) { selected = nil }
    }

    @discardableResult
    func snapshot(kind: HistoryEntry.Kind, title: String? = nil) async -> String? {
        let s = service
        let h = await Task.detached { s.snapshot(kind: kind, title: title) }.value
        await reload()
        return h
    }
}
