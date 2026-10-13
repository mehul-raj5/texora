import Foundation
import Observation

/// Runs LaTeX builds for one project and keeps the latest result.
@MainActor
@Observable
final class CompileController {
    enum Status: Equatable { case idle, running, succeeded, failed, unavailable }

    var status: Status = .idle
    var issues: [CompileIssue] = []
    var pdfURL: URL?
    var pdfVersion = 0
    var lastDuration: Double?
    var log = ""
    var detail: String?
    var engineLabel: String?
    @ObservationIgnored var synctex: SyncTeX?

    var errors: [CompileIssue] { issues.filter { $0.severity == .error } }
    var warnings: [CompileIssue] { issues.filter { $0.severity == .warning } }
    var badboxes: [CompileIssue] { issues.filter { $0.severity == .badbox } }

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var queued = false
    @ObservationIgnored private var currentProcess: Process?
    @ObservationIgnored private var installedThisSession = Set<String>()
    /// Modification date of the PDF currently shown. Any newer PDF on disk gets loaded,
    /// including one Claude built itself (then latexmk has nothing left to do).
    @ObservationIgnored private var shownPDFDate: Date?

    struct Job {
        let root: URL
        let mainFile: String
        let engine: TexEngine
        let tools: ToolLocator
        let texBinOverride: String
    }

    /// Compiles, or queues one more run if a build is already going.
    func compile(_ job: Job) async {
        if isRunning { queued = true; return }
        isRunning = true
        defer { isRunning = false }
        repeat {
            queued = false
            await run(job, installRound: 0)
        } while queued
    }

    func cancel() {
        currentProcess?.terminate()
    }

    private func run(_ job: Job, installRound: Int) async {
        status = .running
        detail = nil
        let start = Date()
        let buildDir = job.root.appendingPathComponent(".build", isDirectory: true)
        try? FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        // \include'd files in sub-folders need matching folders for their .aux files.
        for f in ProjectImporter.listFiles(in: job.root, extensions: ["tex"]) where f.contains("/") {
            try? FileManager.default.createDirectory(at: buildDir.appendingPathComponent((f as NSString).deletingLastPathComponent), withIntermediateDirectories: true)
        }

        guard let command = resolveCommand(job) else {
            status = .unavailable
            detail = "No LaTeX engine found. Install TinyTeX from Settings → LaTeX, or install MacTeX."
            return
        }
        engineLabel = command.label
        if command.isTectonic && installRound == 0 { detail = "Compiling with Tectonic (first runs download packages)…" }

        // After installing a package, force latexmk to rebuild even though no source file changed.
        let args = (!command.isTectonic && installRound > 0) ? ["-g"] + command.args : command.args
        let result = await runProcess(command.executable, args, cwd: job.root, env: job.tools.environment, timeout: 240)
        lastDuration = Date().timeIntervalSince(start)

        let base = (job.mainFile as NSString).deletingPathExtension
        let jobName = (base as NSString).lastPathComponent
        let pdf = buildDir.appendingPathComponent(jobName + ".pdf")
        let logURL = buildDir.appendingPathComponent(jobName + ".log")
        log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? (try? String(contentsOf: logURL, encoding: .isoLatin1)) ?? ""
        if log.isEmpty { log = result.stdout + "\n" + result.stderr }

        // Missing packages: install them with TinyTeX's tlmgr and try again.
        if !command.isTectonic, installRound < 4, let tlmgr = tinyTeXManager(job.tools) {
            let missing = LogParser.missingFiles(log).filter { !installedThisSession.contains($0) }
            if !missing.isEmpty {
                var installedAny = false
                for file in missing {
                    installedThisSession.insert(file)
                    detail = "Installing the package that provides \(file)…"
                    if let pkg = await packageProviding(file, tlmgr: tlmgr, env: job.tools.environment) {
                        detail = "Installing \(pkg)…"
                        let r = await ProcessRunner.run(tlmgr, ["install", pkg], env: job.tools.environment)
                        if r.ok { installedAny = true }
                    }
                }
                if installedAny {
                    job.tools.invalidate()
                    await run(job, installRound: installRound + 1)
                    return
                }
            }
        }

        let projectFiles = Set(ProjectImporter.listFiles(in: job.root))
        var parsed = LogParser.parse(log, root: job.root, projectFiles: projectFiles)
        if parsed.isEmpty && !result.ok && !FileManager.default.fileExists(atPath: pdf.path) {
            let tail = (result.stderr.isEmpty ? result.stdout : result.stderr)
                .split(separator: "\n").suffix(6).joined(separator: "\n")
            parsed = [CompileIssue(severity: .error, message: tail.isEmpty ? "The build failed." : tail, file: nil, line: nil)]
        }
        issues = parsed

        await showPDFIfChanged(pdf, root: job.root)
        status = errors.isEmpty ? .succeeded : .failed
        detail = nil
    }

    /// Loads an existing PDF from a previous session, if there is one.
    func loadExisting(root: URL, mainFile: String) {
        Task { await showPDFIfChanged(Self.pdfURL(root: root, mainFile: mainFile), root: root) }
    }

    static func pdfURL(root: URL, mainFile: String) -> URL {
        let jobName = ((mainFile as NSString).deletingPathExtension as NSString).lastPathComponent
        return root.appendingPathComponent(".build/\(jobName).pdf")
    }

    /// Shows the PDF on disk if it's newer than the one on screen. Returns true if it reloaded.
    @discardableResult
    func showPDFIfChanged(_ pdf: URL, root: URL) async -> Bool {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: pdf.path))?[.modificationDate] as? Date else { return false }
        if pdfURL == pdf, let shown = shownPDFDate, shown == date { return false }
        shownPDFDate = date
        pdfURL = pdf
        pdfVersion += 1
        synctex = await Task.detached { SyncTeX.load(pdf: pdf, root: root) }.value
        return true
    }

    // MARK: Engines

    struct Command {
        let executable: String
        let args: [String]
        let label: String
        let isTectonic: Bool
    }

    func resolveCommand(_ job: Job) -> Command? {
        let tools = job.tools
        let override = job.texBinOverride.isEmpty ? nil : job.texBinOverride
        func find(_ name: String) -> String? {
            if let o = override {
                let p = ((o as NSString).expandingTildeInPath as NSString).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
            return tools.find(name)
        }
        let latexmk = find("latexmk")
        let tectonic = find("tectonic")
        let main = job.mainFile

        func latexmkCommand(_ path: String) -> Command {
            let flag: String
            switch job.engine {
            case .xelatex: flag = "-pdfxe"
            case .lualatex: flag = "-pdflua"
            default: flag = "-pdf"
            }
            return Command(executable: path,
                           args: [flag, "-interaction=nonstopmode", "-file-line-error", "-synctex=-1",
                                  "-outdir=.build", "-f", "-quiet", main],
                           label: job.engine == .tectonic ? "pdfLaTeX" : job.engine.label, isTectonic: false)
        }
        func tectonicCommand(_ path: String) -> Command {
            Command(executable: path,
                    args: ["-X", "compile", main, "--outdir", ".build", "--synctex", "--keep-logs", "--keep-intermediates"],
                    label: "Tectonic", isTectonic: true)
        }

        if job.engine == .tectonic {
            if let t = tectonic { return tectonicCommand(t) }
            if let l = latexmk { return latexmkCommand(l) }
            return nil
        }
        if let l = latexmk, find(job.engine.rawValue) != nil { return latexmkCommand(l) }
        if let t = tectonic { return tectonicCommand(t) }
        if let l = latexmk { return latexmkCommand(l) }
        return nil
    }

    private func tinyTeXManager(_ tools: ToolLocator) -> String? {
        let p = ToolLocator.tinyTeXBin + "/tlmgr"
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    private func packageProviding(_ file: String, tlmgr: String, env: [String: String]) async -> String? {
        let r = await ProcessRunner.run(tlmgr, ["search", "--global", "--file", "/" + file], env: env)
        // Output lines look like "pkgname:" followed by indented paths.
        for line in r.stdout.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasSuffix(":"), !s.contains(" "), !s.hasPrefix("tlmgr") {
                return String(s.dropLast())
            }
        }
        return nil
    }

    // MARK: Process

    private func runProcess(_ exe: String, _ args: [String], cwd: URL, env: [String: String], timeout: TimeInterval) async -> ProcessResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.currentDirectoryURL = cwd
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            currentProcess = p
            DispatchQueue.global(qos: .userInitiated).async {
                do { try p.run() } catch {
                    cont.resume(returning: ProcessResult(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                var outData = Data(), errData = Data()
                let group = DispatchGroup()
                group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.wait()
                p.waitUntilExit()
                killer.cancel()
                cont.resume(returning: ProcessResult(status: p.terminationStatus,
                                                     stdout: String(decoding: outData, as: UTF8.self),
                                                     stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}
