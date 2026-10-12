import Foundation

struct OutlineItem: Identifiable, Hashable {
    let id: String          // file:line
    let level: Int          // 0 part … 6 subparagraph
    let title: String
    let file: String
    let line: Int
    var children: [OutlineItem] = []
}

struct LabelInfo: Hashable { let label: String; let file: String; let line: Int; let context: String }
struct BibEntry: Hashable { let key: String; let title: String; let author: String; let year: String }

/// Parses the document structure (sections across \input/\include), labels, citations keys
/// and user-defined commands.
enum ProjectIndex {
    private enum OutlineEvent { case heading(OutlineItem), input(String) }

    static let sectionLevels: [String: Int] = [
        "part": 0, "chapter": 1, "section": 2, "subsection": 3, "subsubsection": 4, "paragraph": 5, "subparagraph": 6,
    ]

    // MARK: Outline

    /// Flat list of headings in reading order, following \input and \include from the main file.
    static func outline(root: URL, mainFile: String?, text: (String) -> String?) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var visited = Set<String>()
        let start = mainFile ?? ProjectImporter.detectMainFiles(in: root).first
        guard let start else { return [] }
        walk(file: start, root: root, text: text, visited: &visited, items: &items, depth: 0)
        return items
    }

    private static let headingRegex = try! NSRegularExpression(
        pattern: #"\\(part|chapter|section|subsection|subsubsection|paragraph|subparagraph)(\*?)\s*(?:\[[^\]]*\])?\s*\{"#)
    private static let inputRegex = try! NSRegularExpression(
        pattern: #"\\(?:input|include|subfile)\s*\{([^}]+)\}"#)

    private static func walk(file: String, root: URL, text: (String) -> String?, visited: inout Set<String>,
                             items: inout [OutlineItem], depth: Int) {
        guard depth < 12, !visited.contains(file), let content = text(file) else { return }
        visited.insert(file)
        let lines = content.components(separatedBy: "\n")
        for (i, rawLine) in lines.enumerated() {
            let line = stripComment(rawLine)
            if line.isEmpty || !line.contains("\\") { continue }
            let ns = line as NSString
            // Collect headings and inputs on this line in order of position.
            var events: [(Int, OutlineEvent)] = []
            for m in headingRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let cmd = ns.substring(with: m.range(at: 1))
                let braceStart = m.range.location + m.range.length
                let title = balancedArgument(line, from: braceStart, continuation: Array(lines[(i + 1)...].prefix(4)))
                let level = sectionLevels[cmd] ?? 2
                let item = OutlineItem(id: "\(file):\(i + 1)", level: level, title: prettify(title), file: file, line: i + 1)
                events.append((m.range.location, .heading(item)))
            }
            for m in inputRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let target = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                events.append((m.range.location, .input(target)))
            }
            for (_, ev) in events.sorted(by: { $0.0 < $1.0 }) {
                switch ev {
                case .heading(let item): items.append(item)
                case .input(let target):
                    if let resolved = resolveTex(target, from: file, root: root) {
                        walk(file: resolved, root: root, text: text, visited: &visited, items: &items, depth: depth + 1)
                    }
                }
            }
        }
    }

    /// Resolves an \input target to a project-relative .tex path, trying root- and file-relative forms.
    static func resolveTex(_ target: String, from file: String, root: URL) -> String? {
        let withExt = (target as NSString).pathExtension.isEmpty ? target + ".tex" : target
        let fileDir = (file as NSString).deletingLastPathComponent
        let candidates = [withExt, (fileDir as NSString).appendingPathComponent(withExt), target]
        for c in candidates {
            let norm = (c as NSString).standardizingPath.replacingOccurrences(of: "./", with: "")
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(norm).path) { return norm }
        }
        return nil
    }

    /// Nests a flat outline by level.
    static func tree(_ flat: [OutlineItem]) -> [OutlineItem] {
        guard !flat.isEmpty else { return [] }
        var index = 0
        func build(parentLevel: Int) -> [OutlineItem] {
            var result: [OutlineItem] = []
            while index < flat.count {
                let item = flat[index]
                if item.level <= parentLevel { break }
                index += 1
                var node = item
                node.children = build(parentLevel: item.level)
                result.append(node)
            }
            return result
        }
        return build(parentLevel: -1)
    }

    static func stripComment(_ line: String) -> String {
        guard line.contains("%") else { return line }
        var prevBackslash = false
        var out = ""
        for ch in line {
            if ch == "%" && !prevBackslash { break }
            prevBackslash = (ch == "\\") && !prevBackslash
            out.append(ch)
        }
        return out
    }

    /// Reads a {...} argument starting just after the opening brace, allowing nested braces.
    static func balancedArgument(_ line: String, from start: Int, continuation: [String]) -> String {
        let chars = Array((line as NSString).substring(from: min(start, (line as NSString).length)))
        var depth = 1
        var out = ""
        var source = chars
        var lineIdx = 0
        var i = 0
        while true {
            if i >= source.count {
                guard lineIdx < continuation.count else { break }
                source = Array(" " + continuation[lineIdx]); lineIdx += 1; i = 0
                continue
            }
            let c = source[i]
            if c == "\\" && i + 1 < source.count { out.append(c); out.append(source[i + 1]); i += 2; continue }
            if c == "{" { depth += 1 }
            if c == "}" { depth -= 1; if depth == 0 { break } }
            out.append(c)
            i += 1
        }
        return out
    }

    static let symbolMap: [String: String] = [
        "\\to": "→", "\\rightarrow": "→", "\\leftarrow": "←", "\\Rightarrow": "⇒", "\\leftrightarrow": "↔",
        "\\times": "×", "\\cdot": "·", "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\lambda": "λ", "\\mu": "μ", "\\pi": "π", "\\sigma": "σ", "\\theta": "θ",
        "\\phi": "φ", "\\omega": "ω", "\\Delta": "Δ", "\\Sigma": "Σ", "\\infty": "∞", "\\leq": "≤",
        "\\geq": "≥", "\\neq": "≠", "\\approx": "≈", "\\pm": "±", "\\ldots": "…", "\\dots": "…",
        "\\&": "&", "\\%": "%", "\\$": "$", "\\_": "_", "\\#": "#", "\\LaTeX": "LaTeX", "\\TeX": "TeX",
    ]

    /// Turns a LaTeX heading into readable text: `Path 2: Tokens $\to$ Adapter` → `Path 2: Tokens → Adapter`.
    static func prettify(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"\\label\{[^}]*\}"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\(?:protect|noindent|xspace)\b"#, with: "", options: .regularExpression)
        for (k, v) in symbolMap.sorted(by: { $0.key.count > $1.key.count }) {
            t = t.replacingOccurrences(of: k, with: v)
        }
        // \textbf{X} → X, \emph{X} → X, etc.
        for _ in 0..<3 {
            t = t.replacingOccurrences(of: #"\\[a-zA-Z]+\*?\s*\{([^{}]*)\}"#, with: "$1", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"\\[a-zA-Z]+\*?"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "$", with: "")
        t = t.replacingOccurrences(of: "~", with: " ")
        t = t.replacingOccurrences(of: "\\\\", with: " ")
        t = t.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    // MARK: Labels, citations, commands

    private static let labelRegex = try! NSRegularExpression(pattern: #"\\label\s*\{([^}]+)\}"#)
    private static let newcommandRegex = try! NSRegularExpression(
        pattern: #"\\(?:newcommand|renewcommand|DeclareMathOperator|providecommand)\*?\s*\{?\\([a-zA-Z@]+)\}?\s*(?:\[(\d)\])?"#)

    static func labels(root: URL, files: [String], text: (String) -> String?) -> [LabelInfo] {
        var out: [LabelInfo] = []
        for f in files where f.hasSuffix(".tex") {
            guard let content = text(f) else { continue }
            let lines = content.components(separatedBy: "\n")
            for (i, raw) in lines.enumerated() where raw.contains("\\label") {
                let line = stripComment(raw)
                let ns = line as NSString
                for m in labelRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let label = ns.substring(with: m.range(at: 1))
                    let ctx = line.trimmingCharacters(in: .whitespaces)
                    out.append(LabelInfo(label: label, file: f, line: i + 1, context: String(ctx.prefix(120))))
                }
            }
        }
        return out
    }

    static func userCommands(files: [String], text: (String) -> String?) -> [(String, Int)] {
        var out: [(String, Int)] = []
        var seen = Set<String>()
        for f in files where f.hasSuffix(".tex") || f.hasSuffix(".sty") {
            guard let content = text(f), content.contains("command") || content.contains("Declare") else { continue }
            let ns = content as NSString
            for m in newcommandRegex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range(at: 1))
                let args = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) ?? 0 : 0
                if seen.insert(name).inserted { out.append((name, args)) }
            }
        }
        return out
    }

    static func bibEntries(root: URL, files: [String]) -> [BibEntry] {
        var out: [BibEntry] = []
        for f in files where f.lowercased().hasSuffix(".bib") {
            guard let content = try? String(contentsOf: root.appendingPathComponent(f), encoding: .utf8) else { continue }
            out.append(contentsOf: parseBib(content))
        }
        return out
    }

    static func parseBib(_ content: String) -> [BibEntry] {
        var out: [BibEntry] = []
        let chars = Array(content)
        var i = 0
        while i < chars.count {
            guard chars[i] == "@" else { i += 1; continue }
            var j = i + 1
            var type = ""
            while j < chars.count, chars[j].isLetter { type.append(chars[j]); j += 1 }
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            guard j < chars.count, chars[j] == "{" || chars[j] == "(" else { i = j; continue }
            let lowered = type.lowercased()
            // Find the end of the entry by brace matching.
            var depth = 0
            var k = j
            while k < chars.count {
                if chars[k] == "{" || chars[k] == "(" { depth += 1 }
                if chars[k] == "}" || chars[k] == ")" { depth -= 1; if depth == 0 { break } }
                k += 1
            }
            let body = String(chars[(j + 1)..<min(k, chars.count)])
            i = k + 1
            if ["comment", "string", "preamble"].contains(lowered) { continue }
            guard let comma = body.firstIndex(of: ",") else { continue }
            let key = body[..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { continue }
            let fields = String(body[body.index(after: comma)...])
            out.append(BibEntry(key: key,
                                title: cleanBib(field("title", in: fields)),
                                author: shortAuthors(cleanBib(field("author", in: fields))),
                                year: cleanBib(field("year", in: fields))))
        }
        return out
    }

    private static func field(_ name: String, in fields: String) -> String {
        guard let r = fields.range(of: #"(?i)\b\#(name)\s*=\s*"#, options: .regularExpression) else { return "" }
        let rest = Array(fields[r.upperBound...])
        guard let first = rest.first else { return "" }
        if first == "{" || first == "\"" {
            let close: Character = first == "{" ? "}" : "\""
            var depth = 0, out = ""
            for (idx, c) in rest.enumerated() {
                if idx == 0 { if first == "{" { depth = 1 }; continue }
                if first == "{" {
                    if c == "{" { depth += 1 }
                    if c == "}" { depth -= 1; if depth == 0 { break } }
                } else if c == close { break }
                out.append(c)
            }
            return out
        }
        return String(rest.prefix { $0 != "," && $0 != "\n" })
    }

    private static func cleanBib(_ s: String) -> String {
        s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shortAuthors(_ s: String) -> String {
        let parts = s.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = parts.first else { return "" }
        let last = first.contains(",") ? String(first.split(separator: ",")[0]) : (first.split(separator: " ").last.map(String.init) ?? first)
        return parts.count > 2 ? "\(last) et al." : (parts.count == 2 ? "\(last) & \(lastName(parts[1]))" : last)
    }

    private static func lastName(_ s: String) -> String {
        s.contains(",") ? String(s.split(separator: ",")[0]) : (s.split(separator: " ").last.map(String.init) ?? s)
    }
}
