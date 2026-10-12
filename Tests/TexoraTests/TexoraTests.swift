import XCTest
@testable import Texora

final class ImportTests: XCTestCase {
    var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("texora-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    private func write(_ rel: String, _ text: String, in root: URL) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    private func zip(_ dir: URL, to out: URL, keepParent: Bool = true) {
        var args = ["-c", "-k", "--sequesterRsrc"]
        if keepParent { args.append("--keepParent") }
        _ = ProcessRunner.runSync("/usr/bin/ditto", args + [dir.path, out.path])
    }

    func testImportUnwrapsSingleFolderAndCleansJunk() throws {
        let src = tmp.appendingPathComponent("My Paper")
        write("main.tex", "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n", in: src)
        write("sections/a.tex", "\\section{A}", in: src)
        write(".DS_Store", "junk", in: src)
        let z = tmp.appendingPathComponent("paper.zip")
        zip(src, to: z)
        let dest = tmp.appendingPathComponent("projects")
        let root = try ProjectImporter.importZip(z, into: dest)
        XCTAssertEqual(root.lastPathComponent, "My Paper")
        let files = ProjectImporter.listFiles(in: root)
        XCTAssertEqual(Set(files), ["main.tex", "sections/a.tex"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("__MACOSX").path))
        // A second import of the same ZIP gets a unique folder name.
        let root2 = try ProjectImporter.importZip(z, into: dest)
        XCTAssertEqual(root2.lastPathComponent, "My Paper 2")
    }

    func testImportRejectsPathTraversal() throws {
        // Build a ZIP containing "../evil.tex" with Python's zipfile (ditto can't create one).
        let z = tmp.appendingPathComponent("evil.zip")
        let script = "import zipfile,sys\nz=zipfile.ZipFile(sys.argv[1],'w')\nz.writestr('../evil.tex','x')\nz.writestr('ok/main.tex','x')\nz.close()\n"
        let r = ProcessRunner.runSync("/usr/bin/python3", ["-I", "-c", script, z.path])
        XCTAssertTrue(r.ok, r.stderr)
        XCTAssertThrowsError(try ProjectImporter.importZip(z, into: tmp.appendingPathComponent("p"))) { err in
            guard case ImportError.unsafeEntry = err else { return XCTFail("wrong error \(err)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("evil.tex").path))
    }

    func testImportRejectsSymlinks() throws {
        let src = tmp.appendingPathComponent("linky")
        write("main.tex", "x", in: src)
        try FileManager.default.createSymbolicLink(atPath: src.appendingPathComponent("etc").path, withDestinationPath: "/etc")
        let z = tmp.appendingPathComponent("link.zip")
        _ = ProcessRunner.runSync("/usr/bin/zip", ["-r", "-y", "-q", z.path, "linky"], cwd: tmp)
        XCTAssertThrowsError(try ProjectImporter.importZip(z, into: tmp.appendingPathComponent("p")))
    }

    func testMainFileDetection() {
        let root = tmp.appendingPathComponent("proj")
        write("chapters/intro.tex", "% !TEX root = ../thesis.tex\n\\chapter{Intro}", in: root)
        write("thesis.tex", "\\documentclass{report}\n\\begin{document}\n\\include{chapters/intro}\n\\end{document}", in: root)
        write("notes.tex", "% \\documentclass{article}\nnot a root", in: root)
        write("other.tex", "\\documentclass{article}\n\\begin{document}x\\end{document}", in: root)
        let found = ProjectImporter.detectMainFiles(in: root)
        XCTAssertEqual(found.first, "thesis.tex")
        XCTAssertFalse(found.contains("notes.tex"))
    }

    func testTemplatesLoadAndCreate() throws {
        let templates = ProjectTemplate.loadAll()
        XCTAssertGreaterThanOrEqual(templates.count, 7)
        let t = try XCTUnwrap(templates.first { $0.id == "2-twocolumn" })
        let root = try ProjectImporter.create(from: t, name: "Rain & Snow", in: tmp)
        let main = try String(contentsOf: root.appendingPathComponent("main.tex"), encoding: .utf8)
        XCTAssertTrue(main.contains("Rain \\& Snow"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("template.json").path))
    }
}

final class IndexTests: XCTestCase {
    func testOutlineFollowsInputsAndPrettifies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("outline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "main.tex": "\\documentclass{article}\n\\begin{document}\n\\section{Intro}\n\\input{sec/method}\n% \\section{Commented}\n\\section*{End \\label{x}}\n\\end{document}",
            "sec/method.tex": "\\section[short]{Method}\n\\subsection{Codebook Tokens $\\to$ Adapter}\n\\subsubsection{Deep}",
        ]
        for (rel, text) in files {
            let u = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        let flat = ProjectIndex.outline(root: root, mainFile: "main.tex") { try? String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
        XCTAssertEqual(flat.map(\.title), ["Intro", "Method", "Codebook Tokens → Adapter", "Deep", "End"])
        XCTAssertEqual(flat[1].file, "sec/method.tex")
        let tree = ProjectIndex.tree(flat)
        XCTAssertEqual(tree.map(\.title), ["Intro", "Method", "End"])
        XCTAssertEqual(tree[1].children.first?.children.first?.title, "Deep")
    }

    func testBibParsing() {
        let bib = """
        @article{wang2009,
          author = {Xiaogang Wang and Xiaoou Tang},
          title = {Short-Range {Forecast} Correction},
          year = 2009
        }
        @comment{ignored}
        @inproceedings{ho2020, title="Denoising Diffusion", author={Ho, Jonathan and Jain, Ajay and Abbeel, Pieter}, year={2020}}
        """
        let entries = ProjectIndex.parseBib(bib)
        XCTAssertEqual(entries.map(\.key), ["wang2009", "ho2020"])
        XCTAssertEqual(entries[0].title, "Short-Range Forecast Correction")
        XCTAssertEqual(entries[0].author, "Wang & Tang")
        XCTAssertEqual(entries[1].author, "Ho et al.")
        XCTAssertEqual(entries[1].year, "2020")
    }

    func testCommentStripping() {
        XCTAssertEqual(ProjectIndex.stripComment("50\\% done % note"), "50\\% done ")
    }
}

final class LogParserTests: XCTestCase {
    let root = URL(fileURLWithPath: "/tmp/proj")

    func testFileLineErrorsAndWarnings() {
        let log = """
        This is pdfTeX, Version 3.141592653
        (./main.tex
        LaTeX2e <2024-11-01>
        (./sections/intro.tex
        ./sections/intro.tex:12: Undefined control sequence.
        l.12 This uses \\foo
                             here.

        LaTeX Warning: Reference `fig:x' on page 1 undefined on input line 20.

        )
        Overfull \\hbox (12.5pt too wide) in paragraph at lines 30--31
        []\\T1/lmr/m/n/10 text
        )
        """
        let issues = LogParser.parse(log, root: root, projectFiles: ["main.tex", "sections/intro.tex"])
        let err = issues.first { $0.severity == .error }
        XCTAssertEqual(err?.file, "sections/intro.tex")
        XCTAssertEqual(err?.line, 12)
        XCTAssertEqual(err?.message, "Undefined control sequence.")
        let warn = issues.first { $0.severity == .warning }
        XCTAssertEqual(warn?.file, "sections/intro.tex")
        XCTAssertEqual(warn?.line, 20)
        let box = issues.first { $0.severity == .badbox }
        XCTAssertEqual(box?.file, "main.tex")
        XCTAssertEqual(box?.line, 30)
        XCTAssertEqual(box?.message, "Overfull \\hbox (12.5pt too wide) in paragraph")
    }

    func testTectonicStyleFileNamesWithoutExtension() {
        let log = """
        (main.tex
        (sections/method
        Package hyperref Warning: Token not allowed in a PDF string (Unicode):
        (hyperref)                removing `\\to' on input line 32.

        ) (sections/results [1]))
        """
        let issues = LogParser.parse(log, root: root, projectFiles: ["main.tex", "sections/method.tex", "sections/results.tex"])
        XCTAssertEqual(issues.first?.file, "sections/method.tex")
        XCTAssertEqual(issues.first?.line, 32)
        XCTAssertTrue(issues.first?.message.contains("removing") ?? false)
    }

    func testMissingPackageDetection() {
        let log = "! LaTeX Error: File `algorithm2e.sty' not found.\nType X to quit."
        XCTAssertEqual(LogParser.missingFiles(log), ["algorithm2e.sty"])
    }

    func testUnwrapsLongLines() {
        let long = String(repeating: "a", count: 79)
        XCTAssertEqual(LogParser.unwrap("\(long)\nbc\nnext"), [long + "bc", "next"])
    }
}

final class SyncTeXTests: XCTestCase {
    func testForwardAndInverseRoundTrip() throws {
        // Minimal synthetic SyncTeX content: one hbox per source line on page 1.
        var text = "SyncTeX Version:1\nInput:1:/tmp/proj/./main.tex\nInput:2:./sections/intro.tex\nOutput:pdf\nMagnification:1000\nUnit:1\nX Offset:0\nY Offset:0\nContent:\n{1\n"
        let sp: (Double) -> Int = { Int($0 * 65536 * 72.27 / 72) }  // points → scaled points
        for line in 1...5 {
            let v = 100.0 + Double(line) * 14
            text += "(2,\(line):\(sp(72)),\(sp(v)):\(sp(300)),\(sp(8)),\(sp(2))\n"
            text += "x2,\(line):\(sp(80)),\(sp(v))\n"
            text += ")\n"
        }
        text += "}1\nPostamble:\n"
        let st = SyncTeX()
        st.parse(text, root: URL(fileURLWithPath: "/tmp/proj"))
        XCTAssertEqual(st.inputs[1], "main.tex")
        XCTAssertEqual(st.inputs[2], "sections/intro.tex")
        let hit = try XCTUnwrap(st.forward(file: "sections/intro.tex", line: 3))
        XCTAssertEqual(hit.page, 0)
        XCTAssertTrue(hit.rect.minY <= 134 && hit.rect.maxY >= 144, "rect should cover the line box: \(hit.rect)")
        let back = try XCTUnwrap(st.inverse(page: 0, point: CGPoint(x: hit.rect.midX, y: hit.rect.midY)))
        XCTAssertEqual(back.file, "sections/intro.tex")
        XCTAssertEqual(back.line, 3)
    }
}

final class HistoryTests: XCTestCase {
    func testSnapshotsDiffsAndRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let service = HistoryService(projectID: id, workTree: root)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: service.gitDir)
        }
        let main = root.appendingPathComponent("main.tex")
        try "one\n".write(to: main, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try "pdf".write(to: root.appendingPathComponent(".build/main.pdf"), atomically: true, encoding: .utf8)
        let c1 = try XCTUnwrap(service.snapshot(kind: .created, title: "Start"))
        try "two\n".write(to: main, atomically: true, encoding: .utf8)
        try "new".write(to: root.appendingPathComponent("extra.tex"), atomically: true, encoding: .utf8)
        let c2 = try XCTUnwrap(service.snapshot(kind: .claude, title: "Claude edit"))
        XCTAssertNotEqual(c1, c2)
        XCTAssertEqual(Set(service.changedFiles(from: c1, to: c2).map(\.path)), ["main.tex", "extra.tex"])
        // No changes → same commit.
        XCTAssertEqual(service.snapshot(kind: .user, title: nil), c2)
        let entries = service.entries()
        XCTAssertEqual(entries.map(\.kind), [.claude, .created])
        XCTAssertFalse(entries.flatMap(\.files).contains { $0.path.hasPrefix(".build") })
        XCTAssertEqual(service.content(of: "main.tex", at: c1), "one\n")

        service.restoreProject(to: c1)
        XCTAssertEqual(try String(contentsOf: main, encoding: .utf8), "one\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("extra.tex").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/main.pdf").path))

        service.restoreFile("extra.tex", to: c2)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("extra.tex"), encoding: .utf8), "new")
    }

    func testUserEditsMergeWithinWindow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = HistoryService(projectID: UUID(), workTree: root)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: service.gitDir) }
        try "a".write(to: root.appendingPathComponent("a.tex"), atomically: true, encoding: .utf8)
        _ = service.snapshot(kind: .created, title: "Start")
        try "b".write(to: root.appendingPathComponent("a.tex"), atomically: true, encoding: .utf8)
        _ = service.snapshot(kind: .user, title: nil)
        try "c".write(to: root.appendingPathComponent("b.tex"), atomically: true, encoding: .utf8)
        _ = service.snapshot(kind: .user, title: nil)
        let entries = service.entries()
        XCTAssertEqual(entries.count, 2, "two quick user edits should fold into one entry")
        XCTAssertEqual(entries.first?.title, "Edited a.tex, b.tex")
    }
}

final class ExportTests: XCTestCase {
    func testExportExcludesBuildAndAttachmentsByDefault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("exp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for rel in ["main.tex", "main.aux", "figs/a.png", "chatattachments/data.csv", ".build/main.pdf", "data/raw.csv.gz"] {
            let u = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x".write(to: u, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(Set(ExportService.exportFiles(root: root, options: ExportOptions())), ["main.tex", "figs/a.png", "data/raw.csv.gz"])
        var withAtt = ExportOptions(); withAtt.includeChatAttachments = true
        XCTAssertTrue(ExportService.exportFiles(root: root, options: withAtt).contains("chatattachments/data.csv"))

        let out = root.appendingPathComponent("out.zip")
        try ExportService.exportZip(root: root, projectName: "Paper", mainFile: "main.tex", to: out, options: ExportOptions())
        let list = ProcessRunner.runSync("/usr/bin/zipinfo", ["-1", out.path]).stdout
        XCTAssertTrue(list.contains("Paper/main.tex"))
        XCTAssertTrue(list.contains("Paper/main.pdf"))
        XCTAssertFalse(list.contains("main.aux"))
        XCTAssertFalse(list.contains(".build"))
    }
}

final class ClaudeArgsTests: XCTestCase {
    func testProjectOnlyModeNeverAllowListsFileWrites() {
        let c = ClaudeSession.Config(executable: "/x/claude", workingDirectory: URL(fileURLWithPath: "/tmp"), environment: [:],
                                     model: "sonnet", resumeSessionID: "abc", systemPrompt: "p", fullAccess: false, allowScripts: true)
        let args = ClaudeSession.arguments(for: c)
        let i = args.firstIndex(of: "--allowedTools")!
        let allowed = args[(i + 1)...].prefix { !$0.hasPrefix("--") }
        XCTAssertFalse(allowed.contains("Write"))
        XCTAssertFalse(allowed.contains("Edit"))
        XCTAssertFalse(allowed.contains("Read"))
        XCTAssertTrue(allowed.contains("Bash(python3:*)"))
        XCTAssertTrue(args.contains("acceptEdits"))
        XCTAssertEqual(args[args.firstIndex(of: "--resume")! + 1], "abc")
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "sonnet")
    }

    func testNoScriptsWhenDisabled() {
        let c = ClaudeSession.Config(executable: "/x/claude", workingDirectory: URL(fileURLWithPath: "/tmp"), environment: [:],
                                     model: nil, resumeSessionID: nil, systemPrompt: "p", fullAccess: false, allowScripts: false)
        let args = ClaudeSession.arguments(for: c)
        XCTAssertFalse(args.contains("Bash(python3:*)"))
        XCTAssertFalse(args.contains("--model"))
        XCTAssertFalse(args.contains("--resume"))
    }
}

final class DiffTests: XCTestCase {
    func testSideBySideRowsPairChanges() {
        let rows = LineDiff.rows(old: "a\nb\nc", new: "a\nB\nc\nd", context: 3)
        XCTAssertEqual(rows.map(\.kind).map { "\($0)" }, ["same", "changed", "same", "added"])
        XCTAssertEqual(rows[1].left, "b")
        XCTAssertEqual(rows[1].right, "B")
    }

    func testCollapsesLongUnchangedRuns() {
        let old = (1...40).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "\n20\n", with: "\nTWENTY\n")
        let rows = LineDiff.rows(old: old, new: new, context: 2)
        XCTAssertTrue(rows.contains { $0.kind == .gap })
        XCTAssertLessThan(rows.count, 12)
    }
}
