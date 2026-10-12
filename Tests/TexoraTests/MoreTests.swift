import XCTest
import AppKit
@testable import Texora

// MARK: - Helpers

func makeTempDir(_ prefix: String) -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func writeFile(_ rel: String, _ text: String, in root: URL, executable: Bool = false) {
    let u = root.appendingPathComponent(rel)
    try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? text.write(to: u, atomically: true, encoding: .utf8)
    if executable { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path) }
}

/// A one-page PDF made with Core Graphics, so tests don't need TeX.
func makeTinyPDF(at url: URL) {
    var box = CGRect(x: 0, y: 0, width: 200, height: 200)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    ctx.beginPDFPage(nil)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fill(CGRect(x: 20, y: 20, width: 50, height: 50))
    ctx.endPDFPage()
    ctx.closePDF()
}

// MARK: - Themes

final class ThemeTests: XCTestCase {
    func testThemeCatalogue() {
        XCTAssertEqual(Themes.all.count, 20)
        XCTAssertEqual(Set(Themes.all.map(\.id)).count, Themes.all.count, "theme ids must be unique")
        XCTAssertTrue(Themes.light.allSatisfy { !$0.isDark })
        XCTAssertTrue(Themes.dark.allSatisfy { $0.isDark })
        XCTAssertNotNil(Themes.byID("catppuccin-mocha"))
        XCTAssertNil(Themes.byID("nope"))
    }

    func testEveryColourIsValidHex() {
        let re = try! NSRegularExpression(pattern: "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")
        for t in Themes.all {
            for (key, value) in t.cssVariables {
                let ok = re.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
                XCTAssertTrue(ok, "\(t.id) \(key) = \(value)")
            }
        }
    }

    /// WCAG contrast: body text must be readable on every theme.
    func testTextContrast() {
        for t in Themes.all {
            XCTAssertGreaterThanOrEqual(contrast(t.text, t.bg), 4.5, "\(t.id): text on background")
            XCTAssertGreaterThanOrEqual(contrast(t.text, t.sidebar), 4.5, "\(t.id): text on sidebar")
            XCTAssertGreaterThanOrEqual(contrast(t.textSecondary, t.bg), 3.0, "\(t.id): secondary text")
        }
    }

    private func luminance(_ hex: String) -> Double {
        let c = NSColor(hex: hex)
        func ch(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c.redComponent) + 0.7152 * ch(c.greenComponent) + 0.0722 * ch(c.blueComponent)
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testHexParsing() {
        let c = NSColor(hex: "#FF8000")
        XCTAssertEqual(c.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(c.greenComponent, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(NSColor(hex: "#FFFFFF80").alphaComponent, 128.0 / 255, accuracy: 0.01)
        XCTAssertEqual(NSColor(hex: "fff").blueComponent, 1, accuracy: 0.001)
    }
}

// MARK: - Library

@MainActor
final class LibraryTests: XCTestCase {
    func testProjectsCollectionsChatsAndPersistence() throws {
        let dir = makeTempDir("lib")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        let lib = LibraryStore(fileURL: file)
        let p = lib.addProject(ProjectRecord(name: "Paper", path: "/tmp/x/Paper"))
        // Same path (even written differently) is not added twice.
        let again = lib.addProject(ProjectRecord(name: "Other", path: "/tmp/x/./Paper"))
        XCTAssertEqual(again.id, p.id)
        XCTAssertEqual(lib.projects.count, 1)

        let c = lib.addCollection(named: "Thesis")
        lib.update(p.id) { $0.collectionID = c.id }
        XCTAssertEqual(lib.projects(in: c.id).map(\.name), ["Paper"])

        let chat = lib.addChat(projectID: p.id)
        lib.updateChat(chat.id) { $0.title = "Fix intro"; $0.sessionID = "s1" }
        lib.saveNow()

        let reloaded = LibraryStore(fileURL: file)
        XCTAssertEqual(reloaded.projects.first?.collectionID, c.id)
        XCTAssertEqual(reloaded.chats(for: p.id).first?.title, "Fix intro")
        XCTAssertEqual(reloaded.chats(for: p.id).first?.sessionID, "s1")

        reloaded.removeCollection(c.id)
        XCTAssertNil(reloaded.projects.first?.collectionID)
        reloaded.removeProject(p.id)
        XCTAssertTrue(reloaded.projects.isEmpty)
        XCTAssertTrue(reloaded.chats.isEmpty, "removing a project removes its chats")
    }
}

// MARK: - Importer helpers and index

final class HelperTests: XCTestCase {
    func testLatexEscape() {
        XCTAssertEqual(ProjectImporter.latexEscape("R&D 100% $5 #1 a_b {x} ~ ^ \\"),
                       "R\\&D 100\\% \\$5 \\#1 a\\_b \\{x\\} \\textasciitilde{} \\textasciicircum{} \\textbackslash{}")
    }

    func testMagicRoot() {
        XCTAssertEqual(ProjectImporter.magicRoot("% !TEX root = ../main.tex"), "../main.tex")
        XCTAssertEqual(ProjectImporter.magicRoot("%!TeX root=paper.tex"), "paper.tex")
        XCTAssertNil(ProjectImporter.magicRoot("% just a comment"))
    }

    func testListFilesSkipsBuildAndHiddenFolders() {
        let root = makeTempDir("list")
        defer { try? FileManager.default.removeItem(at: root) }
        for f in ["main.tex", ".build/main.pdf", ".git/HEAD", "figs/a.png", ".latexmkrc", "__MACOSX/x"] { writeFile(f, "x", in: root) }
        XCTAssertEqual(Set(ProjectImporter.listFiles(in: root)), ["main.tex", "figs/a.png", ".latexmkrc"])
        XCTAssertEqual(ProjectImporter.listFiles(in: root, extensions: ["tex"]), ["main.tex"])
    }

    func testUniqueFolderNames() {
        let root = makeTempDir("unique")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = ProjectImporter.uniqueFolder(named: "A/B: C", in: root)
        XCTAssertEqual(a.lastPathComponent, "A-B- C")
        try? FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        XCTAssertEqual(ProjectImporter.uniqueFolder(named: "A/B: C", in: root).lastPathComponent, "A-B- C 2")
        XCTAssertEqual(ProjectImporter.uniqueFolder(named: "  ", in: root).lastPathComponent, "Untitled")
    }

    func testLabelsCommandsAndInputResolution() {
        let root = makeTempDir("idx")
        defer { try? FileManager.default.removeItem(at: root) }
        writeFile("main.tex", "\\newcommand{\\R}{\\mathbb{R}}\n\\DeclareMathOperator{\\argmax}{arg\\,max}\n\\section{A}\\label{sec:a}\n% \\label{commented}\n\\begin{equation}x\\label{eq:x}\\end{equation}", in: root)
        writeFile("sec/b.tex", "\\renewcommand*{\\vec}[1]{\\mathbf{#1}}\n\\label{sec:b}", in: root)
        let files = ["main.tex", "sec/b.tex"]
        let text: (String) -> String? = { try? String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
        let labels = ProjectIndex.labels(root: root, files: files, text: text)
        XCTAssertEqual(labels.map(\.label), ["sec:a", "eq:x", "sec:b"])
        XCTAssertEqual(labels.first?.line, 3)
        let cmds = ProjectIndex.userCommands(files: files, text: text)
        XCTAssertEqual(cmds.map(\.0), ["R", "argmax", "vec"])
        XCTAssertEqual(cmds.last?.1, 1)
        XCTAssertEqual(ProjectIndex.resolveTex("sec/b", from: "main.tex", root: root), "sec/b.tex")
        XCTAssertEqual(ProjectIndex.resolveTex("b", from: "sec/b.tex", root: root), "sec/b.tex")
        XCTAssertNil(ProjectIndex.resolveTex("missing", from: "main.tex", root: root))
    }

    func testPrettifyHeadings() {
        XCTAssertEqual(ProjectIndex.prettify("\\textbf{Fast} $\\alpha \\to \\beta$ Results~\\label{x}"), "Fast α → β Results")
        XCTAssertEqual(ProjectIndex.prettify(""), "Untitled")
    }

    func testFileKinds() {
        XCTAssertEqual(FileKind(path: "a/b.TEX", isDirectory: false), .tex)
        XCTAssertEqual(FileKind(path: "refs.bib", isDirectory: false), .bib)
        XCTAssertEqual(FileKind(path: "fig.png", isDirectory: false), .image)
        XCTAssertEqual(FileKind(path: "x", isDirectory: true), .folder)
        XCTAssertTrue(FileKind(path: "data.csv", isDirectory: false).isEditableText)
        XCTAssertFalse(FileKind(path: "fig.pdf", isDirectory: false).isEditableText)
        XCTAssertTrue(FileKind(path: ".latexmkrc", isDirectory: false).isEditableText)
    }
}

// MARK: - Log parser edge cases

final class MoreLogParserTests: XCTestCase {
    let root = URL(fileURLWithPath: "/tmp/proj")

    func testClassicErrorWithLineMarker() {
        let log = """
        (./main.tex
        ! Missing $ inserted.
        <inserted text>
                        $
        l.7 Math with a missing brace: $\\frac{a}{b$
                                                    .
        ! Emergency stop.
        )
        """
        let issues = LogParser.parse(log, root: root, projectFiles: ["main.tex"])
        XCTAssertEqual(issues.count, 1, "Emergency stop is not reported separately")
        XCTAssertEqual(issues[0].message, "Missing $ inserted.")
        XCTAssertEqual(issues[0].line, 7)
        XCTAssertEqual(issues[0].file, "main.tex")
    }

    func testPackageErrorAndNoiseFiltering() {
        let log = """
        (./main.tex
        ./main.tex:3: Package natbib Error: Bibliography not compatible with author-year citations.
        (natbib)                Press <return> to continue in numerical citation style.

        LaTeX Font Warning: Font shape `OT1/cmr/bx/sc' undefined on input line 5.

        Package inputenc Warning: inputenc package ignored with utf8 based engines.

        LaTeX Warning: There were undefined references.
        )
        """
        let issues = LogParser.parse(log, root: root, projectFiles: ["main.tex"])
        XCTAssertEqual(issues.filter { $0.severity == .error }.count, 1)
        XCTAssertTrue(issues[0].message.contains("Bibliography not compatible"))
        XCTAssertTrue(issues[0].message.contains("numerical citation style"))
        let warnings = issues.filter { $0.severity == .warning }.map(\.message)
        XCTAssertEqual(warnings, ["There were undefined references."])
    }

    func testDeduplicatesRepeatedWarnings() {
        let w = "LaTeX Warning: Citation `x' on page 1 undefined on input line 4.\n"
        let issues = LogParser.parse("(./main.tex\n" + w + "\n" + w + ")", root: root, projectFiles: ["main.tex"])
        XCTAssertEqual(issues.count, 1)
    }

    func testAbsolutePathsInsideProjectAreMadeRelative() {
        let log = "(/tmp/proj/chapters/one.tex\n/tmp/proj/chapters/one.tex:9: Undefined control sequence.\n)"
        let issues = LogParser.parse(log, root: root, projectFiles: ["chapters/one.tex"])
        XCTAssertEqual(issues.first?.file, "chapters/one.tex")
        XCTAssertEqual(issues.first?.line, 9)
    }
}

// MARK: - Compile pipeline with a fake engine

@MainActor
final class CompilePipelineTests: XCTestCase {
    /// Fake latexmk/pdflatex that write a PDF and a log, so the pipeline runs without TeX.
    private func fakeTeX(in bin: URL, pdf: URL, log: String) {
        writeFile("pdflatex", "#!/bin/sh\nexit 0\n", in: bin, executable: true)
        let script = """
        #!/bin/sh
        # args: flags… main.tex  (last argument)
        for a in "$@"; do main="$a"; done
        job=$(basename "$main" .tex)
        mkdir -p .build
        cp "\(pdf.path)" ".build/$job.pdf"
        cat > ".build/$job.log" <<'LOG'
        \(log)
        LOG
        echo "$@" > .build/args.txt
        exit 0
        """
        writeFile("latexmk", script, in: bin, executable: true)
    }

    func testSuccessfulBuildLoadsPDFAndUsesPdfLaTeXFlags() async throws {
        let root = makeTempDir("cp-ok"), bin = makeTempDir("bin")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bin) }
        writeFile("main.tex", "\\documentclass{article}\\begin{document}x\\end{document}", in: root)
        writeFile("chapters/one.tex", "x", in: root)
        let pdf = bin.appendingPathComponent("tiny.pdf"); makeTinyPDF(at: pdf)
        fakeTeX(in: bin, pdf: pdf, log: "(./main.tex\nLaTeX Warning: Reference `x' on page 1 undefined on input line 3.\n)")
        let c = CompileController()
        await c.compile(.init(root: root, mainFile: "main.tex", engine: .pdflatex, tools: ToolLocator(), texBinOverride: bin.path))
        XCTAssertEqual(c.status, .succeeded)
        XCTAssertEqual(c.pdfURL?.lastPathComponent, "main.pdf")
        XCTAssertEqual(c.pdfVersion, 1)
        XCTAssertEqual(c.warnings.first?.line, 3)
        XCTAssertEqual(c.engineLabel, "pdfLaTeX")
        let args = try String(contentsOf: root.appendingPathComponent(".build/args.txt"), encoding: .utf8)
        XCTAssertTrue(args.contains("-pdf "))
        XCTAssertTrue(args.contains("-synctex=-1"))
        XCTAssertTrue(args.contains("-outdir=.build"))
        // Sub-folders for \include'd files are prepared inside .build.
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/chapters").path))
    }

    func testFailedBuildReportsErrorsAndEngineFlags() async throws {
        let root = makeTempDir("cp-err"), bin = makeTempDir("bin")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bin) }
        writeFile("main.tex", "x", in: root)
        let pdf = bin.appendingPathComponent("tiny.pdf"); makeTinyPDF(at: pdf)
        fakeTeX(in: bin, pdf: pdf, log: "(./main.tex\n./main.tex:5: Undefined control sequence.\nl.5 \\foo\n)")
        writeFile("xelatex", "#!/bin/sh\nexit 0\n", in: bin, executable: true)
        let c = CompileController()
        await c.compile(.init(root: root, mainFile: "main.tex", engine: .xelatex, tools: ToolLocator(), texBinOverride: bin.path))
        XCTAssertEqual(c.status, .failed)
        XCTAssertEqual(c.errors.first?.line, 5)
        XCTAssertEqual(c.errors.first?.file, "main.tex")
        XCTAssertNotNil(c.pdfURL, "a PDF that was still produced is shown")
        let args = try String(contentsOf: root.appendingPathComponent(".build/args.txt"), encoding: .utf8)
        XCTAssertTrue(args.contains("-pdfxe"))
    }

    func testQueuedCompileRunsAgain() async {
        let root = makeTempDir("cp-q"), bin = makeTempDir("bin")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: bin) }
        writeFile("main.tex", "x", in: root)
        let pdf = bin.appendingPathComponent("tiny.pdf"); makeTinyPDF(at: pdf)
        fakeTeX(in: bin, pdf: pdf, log: "(./main.tex)")
        let c = CompileController()
        let job = CompileController.Job(root: root, mainFile: "main.tex", engine: .pdflatex, tools: ToolLocator(), texBinOverride: bin.path)
        async let first: Void = c.compile(job)
        async let second: Void = c.compile(job)
        _ = await (first, second)
        XCTAssertEqual(c.pdfVersion, 2, "a compile requested while one runs is queued, not dropped")
    }
}

// MARK: - Claude bridge with a fake CLI

final class ClaudeSessionTests: XCTestCase {
    func testStreamJsonRoundTripAndInterrupt() throws {
        let dir = makeTempDir("claude")
        defer { try? FileManager.default.removeItem(at: dir) }
        let argsFile = dir.appendingPathComponent("args.txt")
        let script = """
        #!/bin/bash
        printf '%s\\n' "$@" > "\(argsFile.path)"
        while IFS= read -r line; do
          if [[ "$line" == *control_request* ]]; then
            echo '{"type":"control_response","response":{"subtype":"success","request_id":"req_1"}}'
            continue
          fi
          echo '{"type":"system","subtype":"init","session_id":"sess-42"}'
          echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello "}}}'
          echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"world"}}}'
          echo '{"type":"result","subtype":"success","is_error":false,"result":"Hello world"}'
        done
        """
        writeFile("claude", script, in: dir, executable: true)
        let config = ClaudeSession.Config(executable: dir.appendingPathComponent("claude").path, workingDirectory: dir,
                                          environment: ["PATH": "/usr/bin:/bin"], model: "haiku", resumeSessionID: nil,
                                          systemPrompt: "be brief", fullAccess: false, allowScripts: false)
        let session = ClaudeSession(config: config)
        var events: [[String: Any]] = []
        let gotResult = expectation(description: "result")
        let gotControl = expectation(description: "control")
        session.onEvent = { e in
            events.append(e)
            if e["type"] as? String == "result" { gotResult.fulfill() }
            if e["type"] as? String == "control_response" { gotControl.fulfill() }
        }
        try session.start()
        session.send(content: [["type": "text", "text": "hi"]])
        wait(for: [gotResult], timeout: 10)
        let text = events.compactMap { e -> String? in
            guard let ev = e["event"] as? [String: Any], let d = ev["delta"] as? [String: Any] else { return nil }
            return d["text"] as? String
        }.joined()
        XCTAssertEqual(text, "Hello world")
        XCTAssertEqual(events.first?["session_id"] as? String, "sess-42")

        session.interrupt()
        wait(for: [gotControl], timeout: 10)
        let exited = expectation(description: "exit")
        session.onExit = { _, _ in exited.fulfill() }
        session.terminate()
        wait(for: [exited], timeout: 10)

        let args = try String(contentsOf: argsFile, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--include-partial-messages"))
        XCTAssertEqual(args[args.firstIndex(of: "--permission-prompts")! + 1], "none")
        XCTAssertEqual(args[args.firstIndex(of: "--append-system-prompt")! + 1], "be brief")
    }
}

@MainActor
final class ChatDescriptionTests: XCTestCase {
    func testFriendlyToolDescriptions() {
        let chat = ChatController()
        XCTAssertEqual(chat.describeTool(name: "Read", input: ["file_path": "main.tex"]).text, "Reading main.tex")
        XCTAssertEqual(chat.describeTool(name: "Edit", input: ["file_path": "sec/a.tex"]).text, "Editing sec/a.tex")
        XCTAssertEqual(chat.describeTool(name: "Bash", input: ["command": "latexmk -pdf main.tex"]).text, "Compiling to check for errors")
        XCTAssertEqual(chat.describeTool(name: "Bash", input: ["command": "python3 plot.py"]).text, "Running a Python script")
        XCTAssertEqual(chat.describeTool(name: "Grep", input: ["pattern": "abstract"]).text, "Searching for “abstract”")
        XCTAssertEqual(chat.describeTool(name: "WebSearch", input: ["query": "bibtex for attention"]).text, "Searching the web for “bibtex for attention”")
        XCTAssertEqual(chat.describeTool(name: "SomethingNew", input: [:]).text, "Working…")
    }
}

// MARK: - History and export options

final class MoreHistoryExportTests: XCTestCase {
    func testForcedCheckpointWithoutChanges() throws {
        let root = makeTempDir("cp")
        let service = HistoryService(projectID: UUID(), workTree: root)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: service.gitDir) }
        writeFile("main.tex", "x", in: root)
        let first = try XCTUnwrap(service.snapshot(kind: .created, title: "Start"))
        XCTAssertEqual(service.snapshot(kind: .checkpoint, title: "Before submission"), first, "no changes, not forced")
        let forced = try XCTUnwrap(service.snapshot(kind: .checkpoint, title: "⚑ Before submission", force: true))
        XCTAssertNotEqual(forced, first)
        XCTAssertEqual(service.entries().first?.kind, .checkpoint)
        XCTAssertEqual(service.entries().first?.title, "⚑ Before submission")
    }

    func testExportPlacesPdfAndBblNextToMainFile() throws {
        let root = makeTempDir("exp2")
        defer { try? FileManager.default.removeItem(at: root) }
        writeFile("paper/main.tex", "x", in: root)
        writeFile(".build/main.bbl", "bbl", in: root)
        makeTinyPDF(at: root.appendingPathComponent(".build/main.pdf"))
        let out = root.appendingPathComponent("out.zip")
        var opts = ExportOptions(); opts.includeBbl = true
        try ExportService.exportZip(root: root, projectName: "P", mainFile: "paper/main.tex", to: out, options: opts)
        let list = ProcessRunner.runSync("/usr/bin/zipinfo", ["-1", out.path]).stdout
        XCTAssertTrue(list.contains("P/paper/main.pdf"))
        XCTAssertTrue(list.contains("P/paper/main.bbl"))
        var noPDF = ExportOptions(); noPDF.includePDF = false
        try ExportService.exportZip(root: root, projectName: "P", mainFile: "paper/main.tex", to: out, options: noPDF)
        XCTAssertFalse(ProcessRunner.runSync("/usr/bin/zipinfo", ["-1", out.path]).stdout.contains(".pdf"))
    }
}

// MARK: - Markdown and tools

final class MarkdownTests: XCTestCase {
    func testBlockParsing() {
        let md = """
        # Title
        Some *text*.
        continued line

        - one
          - nested
        1. first
        > quote
        ```latex
        \\section{A}
        ```
        ---
        """
        let blocks = MarkdownText.parse(md)
        XCTAssertEqual(blocks, [
            .heading(1, "Title"),
            .paragraph("Some *text*.\ncontinued line"),
            .bullet("one", 0),
            .bullet("nested", 1),
            .numbered("1.", "first"),
            .quote("quote"),
            .code("latex", "\\section{A}"),
            .rule,
        ])
    }

    func testUnclosedCodeFenceKeepsContent() {
        XCTAssertEqual(MarkdownText.parse("```\nabc"), [.code("", "abc")])
    }
}

final class ToolLocatorTests: XCTestCase {
    func testOverrideAndSearchPath() {
        let bin = makeTempDir("tools")
        defer { try? FileManager.default.removeItem(at: bin) }
        writeFile("mytool", "#!/bin/sh\n", in: bin, executable: true)
        let tools = ToolLocator()
        XCTAssertEqual(tools.find("anything", override: bin.appendingPathComponent("mytool").path), bin.appendingPathComponent("mytool").path)
        XCTAssertNil(tools.find("definitely-not-a-real-tool-\(UUID().uuidString)"))
        XCTAssertNotNil(tools.find("ls"))
        XCTAssertTrue(tools.environment["PATH"]?.contains("/usr/bin") ?? false)
        XCTAssertTrue(tools.searchPath.contains(ToolLocator.tinyTeXBin))
    }
}
