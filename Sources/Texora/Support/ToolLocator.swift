import Foundation

/// Finds command-line tools. GUI apps on macOS don't inherit the shell PATH,
/// so we search the usual install locations and also ask the login shell once.
final class ToolLocator: @unchecked Sendable {
    private let lock = NSLock()
    private var shellPath: [String] = []
    private var cache: [String: String] = [:]

    init() {
        loadShellPath()
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static var tinyTeXBin: String { "\(home)/Library/TinyTeX/bin/universal-darwin" }

    private var fixedDirs: [String] {
        let h = Self.home
        return [
            "\(h)/.local/bin",
            Self.tinyTeXBin,
            "/Library/TeX/texbin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(h)/bin",
        ]
    }

    /// Directories to put on PATH for every subprocess we launch.
    var searchPath: [String] {
        lock.lock(); defer { lock.unlock() }
        var seen = Set<String>()
        return (fixedDirs + shellPath).filter { seen.insert($0).inserted }
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath.joined(separator: ":")
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        return env
    }

    /// Absolute path of a tool, or nil if it isn't installed.
    func find(_ name: String, override: String? = nil) -> String? {
        if let override, !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) { return expanded }
        }
        lock.lock()
        if let c = cache[name], FileManager.default.isExecutableFile(atPath: c) { lock.unlock(); return c }
        lock.unlock()
        for dir in searchPath {
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) {
                lock.lock(); cache[name] = p; lock.unlock()
                return p
            }
        }
        return nil
    }

    func invalidate() {
        lock.lock(); cache.removeAll(); lock.unlock()
    }

    private func loadShellPath() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "printf %s \"$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
            DispatchQueue.global().async { [weak self] in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let s = String(decoding: data, as: UTF8.self)
                let dirs = s.split(separator: ":").map(String.init).filter { !$0.isEmpty }
                self?.lock.lock()
                self?.shellPath = dirs
                self?.cache.removeAll()
                self?.lock.unlock()
            }
        } catch {}
    }
}

struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
}

enum ProcessRunner {
    /// Runs a process to completion off the main thread.
    static func run(_ executable: String, _ args: [String], cwd: URL? = nil,
                    env: [String: String]? = nil, stdin: Data? = nil) async -> ProcessResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(executable, args, cwd: cwd, env: env, stdin: stdin))
            }
        }
    }

    static func runSync(_ executable: String, _ args: [String], cwd: URL? = nil,
                        env: [String: String]? = nil, stdin: Data? = nil) -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        if let env { p.environment = env }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let inPipe = Pipe()
        p.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe
        do { try p.run() } catch {
            return ProcessResult(status: -1, stdout: "", stderr: "\(error.localizedDescription)")
        }
        if let stdin {
            DispatchQueue.global().async {
                inPipe.fileHandleForWriting.write(stdin)
                try? inPipe.fileHandleForWriting.close()
            }
        }
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.wait()
        p.waitUntilExit()
        return ProcessResult(status: p.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}
