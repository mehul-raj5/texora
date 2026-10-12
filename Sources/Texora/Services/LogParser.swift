import Foundation

struct CompileIssue: Identifiable, Hashable {
    enum Severity: String, Hashable { case error, warning, badbox }
    var id: String { "\(severity.rawValue)|\(file ?? "")|\(line ?? 0)|\(message)" }
    var severity: Severity
    var message: String
    var file: String?
    var line: Int?
    var detail: String?
}

/// Turns a TeX .log into a list of errors, warnings and bad boxes with file and line.
enum LogParser {
    private static let fileExts = "tex|ltx|sty|cls|bib|bbl|cfg|def|clo|fd|aux|toc|lof|lot|out|ldf|tikz|dtx|ins|dbx|cbx|bbx|lbx"
    private static let fileLineError = try! NSRegularExpression(pattern: #"^(.+?\.(?:"# + fileExts + #")):(\d+): (.*)$"#)
    private static let openFile = try! NSRegularExpression(pattern: #"^\(([^\s()\[\]{}"<>]+)"#)
    private static let knownExt = try! NSRegularExpression(pattern: #"\.(?:"# + fileExts + #"|out|bbl)$"#)
    private static let inputLine = try! NSRegularExpression(pattern: #"on input line (\d+)"#)
    private static let badbox = try! NSRegularExpression(pattern: #"^((?:Overfull|Underfull) \\[hv]box \([^)]*\))(.*?)(?:at lines? (\d+)(?:--(\d+))?)?$"#)
    private static let lDotLine = try! NSRegularExpression(pattern: #"^l\.(\d+)\s?(.*)$"#)

    static func parse(_ rawLog: String, root: URL, projectFiles: Set<String> = []) -> [CompileIssue] {
        let lines = unwrap(rawLog)
        var issues: [CompileIssue] = []
        var stack: [String] = []
        var seen = Set<String>()
        var i = 0

        func currentFile() -> String? {
            for f in stack.reversed() where !f.isEmpty && isProjectFile(f, root: root) { return resolve(f) }
            return stack.last(where: { !$0.isEmpty }).map { resolve($0) }
        }

        func resolve(_ f: String) -> String {
            let n = normalize(f, root: root)
            if (n as NSString).pathExtension.isEmpty, projectFiles.contains(n + ".tex") { return n + ".tex" }
            return n
        }

        func add(_ issue: CompileIssue) {
            if seen.insert(issue.id).inserted { issues.append(issue) }
        }

        while i < lines.count {
            let line = lines[i]
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)

            if let m = fileLineError.firstMatch(in: line, range: range) {
                let file = normalize(ns.substring(with: m.range(at: 1)), root: root)
                let lineNo = Int(ns.substring(with: m.range(at: 2)))
                var msg = ns.substring(with: m.range(at: 3))
                var detail: [String] = []
                var j = i + 1
                while j < lines.count, j < i + 8 {
                    let l = lines[j]
                    if l.isEmpty { j += 1; continue }
                    if lDotLine.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) != nil {
                        detail.append(l); break
                    }
                    if fileLineError.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) != nil { break }
                    detail.append(l)
                    j += 1
                }
                if msg.hasPrefix("LaTeX Error: ") { msg.removeFirst("LaTeX Error: ".count) }
                let trimmedMsg = msg.trimmingCharacters(in: .whitespaces)
                if trimmedMsg == "Emergency stop." || trimmedMsg.hasPrefix("==> Fatal error") { i += 1; continue }
                if msg.hasPrefix("Package ") || msg.hasPrefix("Class ") {
                    // "Package xyz Error: text" plus continuation lines in parentheses
                    for d in detail where d.hasPrefix("(") && !d.hasPrefix("(./") { msg += " " + d.drop(while: { $0 != ")" }).dropFirst().trimmingCharacters(in: .whitespaces) }
                }
                add(CompileIssue(severity: .error, message: msg, file: file, line: lineNo,
                                 detail: detail.isEmpty ? nil : detail.joined(separator: "\n")))
                i += 1
                continue
            }

            if line.hasPrefix("! ") {
                var msg = String(line.dropFirst(2))
                if msg.hasPrefix("LaTeX Error: ") { msg.removeFirst("LaTeX Error: ".count) }
                if msg == "Emergency stop." || msg.hasPrefix("==> Fatal error") { i += 1; continue }
                var lineNo: Int?
                var detail: [String] = []
                var j = i + 1
                while j < lines.count, j < i + 12 {
                    let l = lines[j]
                    if let lm = lDotLine.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) {
                        lineNo = Int((l as NSString).substring(with: lm.range(at: 1)))
                        detail.append(l)
                        break
                    }
                    if l.hasPrefix("! ") { break }
                    if !l.isEmpty { detail.append(l) }
                    j += 1
                }
                add(CompileIssue(severity: .error, message: msg, file: currentFile(), line: lineNo,
                                 detail: detail.isEmpty ? nil : detail.joined(separator: "\n")))
                i += 1
                continue
            }

            if let warn = warningStart(line) {
                var text = warn.text
                var j = i + 1
                while j < lines.count, !lines[j].isEmpty, j < i + 6 {
                    let l = lines[j]
                    if let pkg = warn.package, l.hasPrefix("(\(pkg))") {
                        text += " " + l.dropFirst(pkg.count + 2).trimmingCharacters(in: .whitespaces)
                    } else if warn.package == nil, !l.hasPrefix("("), !l.hasPrefix(")"), !l.hasPrefix("[") {
                        text += " " + l.trimmingCharacters(in: .whitespaces)
                    } else { break }
                    j += 1
                }
                var lineNo: Int?
                let tns = text as NSString
                if let m = inputLine.firstMatch(in: text, range: NSRange(location: 0, length: tns.length)) {
                    lineNo = Int(tns.substring(with: m.range(at: 1)))
                }
                text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                if !isNoise(text) {
                    add(CompileIssue(severity: .warning, message: text.trimmingCharacters(in: .whitespaces), file: currentFile(), line: lineNo))
                }
                scanParens(line, stack: &stack, projectFiles: projectFiles)
                i = max(i + 1, j)
                continue
            }

            if line.hasPrefix("Overfull \\") || line.hasPrefix("Underfull \\") {
                if let m = badbox.firstMatch(in: line, range: range) {
                    var msg = ns.substring(with: m.range(at: 1))
                    let ctx = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    if ctx.hasPrefix("in paragraph") { msg += " in paragraph" } else if ctx.hasPrefix("in alignment") { msg += " in alignment" }
                    let lineNo = m.range(at: 3).location != NSNotFound ? Int(ns.substring(with: m.range(at: 3))) : nil
                    add(CompileIssue(severity: .badbox, message: msg, file: currentFile(), line: lineNo))
                }
                i += 1
                continue
            }

            scanParens(line, stack: &stack, projectFiles: projectFiles)
            i += 1
        }
        return issues.sorted { rank($0.severity) < rank($1.severity) }
    }

    /// Missing .sty/.cls/.bst files ("File `x.sty' not found").
    static func missingFiles(_ log: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"File `([^']+\.(?:sty|cls|bst|def|cfg|fd|tex|clo|ldf))' not found"#)
        let ns = log as NSString
        var out: [String] = []
        for m in re.matches(in: log, range: NSRange(location: 0, length: ns.length)) {
            let f = ns.substring(with: m.range(at: 1))
            if !out.contains(f) { out.append(f) }
        }
        let font = try! NSRegularExpression(pattern: #"Metric \(TFM\) file(?: or installed font)? not found|! Font \\[^=]+=([a-zA-Z0-9-]+)"#)
        for m in font.matches(in: log, range: NSRange(location: 0, length: ns.length)) where m.range(at: 1).location != NSNotFound {
            let f = ns.substring(with: m.range(at: 1)) + ".tfm"
            if !out.contains(f) { out.append(f) }
        }
        return out
    }

    private static func rank(_ s: CompileIssue.Severity) -> Int {
        switch s { case .error: return 0; case .warning: return 1; case .badbox: return 2 }
    }

    private static func warningStart(_ line: String) -> (text: String, package: String?)? {
        if line.hasPrefix("LaTeX Warning: ") { return (String(line.dropFirst(15)), nil) }
        if line.hasPrefix("LaTeX Font Warning:") { return nil }
        for prefix in ["Package ", "Class "] where line.hasPrefix(prefix) {
            let rest = line.dropFirst(prefix.count)
            if let r = rest.range(of: " Warning: ") {
                let pkg = String(rest[..<r.lowerBound])
                if pkg.contains(" ") { return nil }
                return (String(rest[r.upperBound...]), pkg)
            }
        }
        return nil
    }

    private static func isNoise(_ text: String) -> Bool {
        text.contains("Font shape") || text.hasPrefix("Size substitutions")
            || text.contains("Unused global option") || text.contains("inputenc package ignored")
    }

    /// Tracks which file TeX is reading from "(./file.tex" … ")" pairs.
    private static func scanParens(_ line: String, stack: inout [String], projectFiles: Set<String>) {
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "(" {
                let rest = String(chars[i...])
                let ns = rest as NSString
                if let m = openFile.firstMatch(in: rest, range: NSRange(location: 0, length: min(ns.length, 600))) {
                    let path = ns.substring(with: m.range(at: 1))
                    let pns = path as NSString
                    let looksLikeFile = knownExt.firstMatch(in: path, range: NSRange(location: 0, length: pns.length)) != nil
                        || projectFiles.contains(path) || projectFiles.contains(path + ".tex")
                        || (path.contains("/") && !path.hasPrefix("http"))
                    if looksLikeFile {
                        stack.append(path)
                        i += m.range.length
                        continue
                    }
                }
                stack.append("")
            } else if c == ")" {
                if !stack.isEmpty { stack.removeLast() }
            }
            i += 1
        }
    }

    /// TeX wraps log lines at 79 characters; glue them back together.
    static func unwrap(_ log: String) -> [String] {
        var out: [String] = []
        var buffer = ""
        for raw in log.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            buffer += line
            if line.utf8.count == 79 { continue }
            out.append(buffer)
            buffer = ""
        }
        if !buffer.isEmpty { out.append(buffer) }
        return out
    }

    static func isProjectFile(_ path: String, root: URL) -> Bool {
        guard !path.isEmpty else { return false }
        if path.hasPrefix("./") || (!path.hasPrefix("/") && !path.contains("texmf") && !path.contains("texlive")) { return true }
        return path.hasPrefix(root.standardizedFileURL.path + "/")
    }

    static func normalize(_ path: String, root: URL) -> String {
        var p = path
        let rootPath = root.standardizedFileURL.path
        if p.hasPrefix(rootPath + "/") { p.removeFirst(rootPath.count + 1) }
        while p.hasPrefix("./") { p.removeFirst(2) }
        return p
    }
}
