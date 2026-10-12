import XCTest
@testable import Texora

/// Compiles a real document with Tectonic (if installed) and checks SyncTeX round trips.
final class SyncTeXIntegrationTests: XCTestCase {
    func testRealSyncTeXRoundTrip() async throws {
        let tools = ToolLocator()
        guard tools.find("tectonic") != nil || tools.find("latexmk") != nil else { throw XCTSkip("no TeX engine") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sec"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        \\documentclass{article}
        \\begin{document}
        \\section{First}
        Alpha paragraph text on line four of the main file.

        \\input{sec/two}
        \\end{document}
        """.write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        var body = "\\section{Second}\n"
        for i in 1...30 { body += "Line \(i) of the second file with some words to fill the page nicely.\n\n" }
        try body.write(to: root.appendingPathComponent("sec/two.tex"), atomically: true, encoding: .utf8)

        let compiler = await CompileController()
        let job = CompileController.Job(root: root, mainFile: "main.tex", engine: .tectonic, tools: tools, texBinOverride: "")
        await compiler.compile(job)
        let st = await compiler.synctex
        let synctex = try XCTUnwrap(st, "SyncTeX data should load after compiling")

        for (file, line) in [("main.tex", 4), ("sec/two.tex", 11), ("sec/two.tex", 41)] {
            let fwd = try XCTUnwrap(synctex.forward(file: file, line: line), "forward \(file):\(line)")
            let back = try XCTUnwrap(synctex.inverse(page: fwd.page, point: CGPoint(x: fwd.rect.minX + 20, y: fwd.rect.midY)))
            XCTAssertEqual(back.file, file)
            XCTAssertLessThanOrEqual(abs(back.line - line), 1, "\(file):\(line) came back as \(back.line)")
        }
    }
}
