import Foundation

enum ImportError: LocalizedError {
    case notAZip
    case unsafeEntry(String)
    case containsSymlink(String)
    case tooManyEntries
    case extractFailed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notAZip: return "That file isn't a ZIP archive Texora can read."
        case .unsafeEntry(let e): return "The ZIP contains an unsafe path (\(e)), so it wasn't imported."
        case .containsSymlink(let e): return "The ZIP contains a symbolic link (\(e)), so it wasn't imported."
        case .tooManyEntries: return "The ZIP has too many files to be a LaTeX project."
        case .extractFailed(let m): return "Couldn't extract the ZIP. \(m)"
        case .empty: return "The ZIP is empty."
        }
    }
}

struct ProjectTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let mainFile: String
    let order: Int
    let url: URL

    static func loadAll() -> [ProjectTemplate] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: Paths.templatesDir, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir -> ProjectTemplate? in
            let meta = dir.appendingPathComponent("template.json")
            guard let data = try? Data(contentsOf: meta),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return ProjectTemplate(
                id: dir.lastPathComponent,
                name: j["name"] as? String ?? dir.lastPathComponent,
                summary: j["summary"] as? String ?? "",
                icon: j["icon"] as? String ?? "doc.text",
                mainFile: j["mainFile"] as? String ?? "main.tex",
                order: j["order"] as? Int ?? 99,
                url: dir)
        }
        .sorted { $0.order < $1.order }
    }
}

enum ProjectImporter {
    static let ignoredNames: Set<String> = [".DS_Store", "__MACOSX", ".build", ".git", "node_modules", ".texora"]

    // MARK: ZIP

    /// Validates entry names before anything is written: no absolute paths, no `..`, no symlinks.
    static func validateZip(_ zip: URL) throws {
        let list = ProcessRunner.runSync("/usr/bin/zipinfo", ["-l", zip.path])
        guard list.ok || list.status == 1 else { throw ImportError.notAZip }
        let names = ProcessRunner.runSync("/usr/bin/zipinfo", ["-1", zip.path])
        let entries = names.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if entries.isEmpty { throw ImportError.empty }
        if entries.count > 20000 { throw ImportError.tooManyEntries }
        for e in entries {
            if e.hasPrefix("/") || e.hasPrefix("\\") || e.contains("\\") { throw ImportError.unsafeEntry(e) }
            let comps = e.split(separator: "/")
            if comps.contains("..") { throw ImportError.unsafeEntry(e) }
        }
        // Long listing: permission strings starting with "l" are symbolic links.
        for line in list.stdout.split(separator: "\n") where line.hasPrefix("l") {
            let name = line.split(separator: " ", omittingEmptySubsequences: true).last.map(String.init) ?? String(line)
            throw ImportError.containsSymlink(name)
        }
    }

    /// Extracts a ZIP into a new folder inside `folder` and returns the project root.
    static func importZip(_ zip: URL, into folder: URL) throws -> URL {
        try validateZip(zip)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appendingPathComponent(".texora-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let r = ProcessRunner.runSync("/usr/bin/ditto", ["-x", "-k", "--norsrc", "--noextattr", "--noqtn", zip.path, staging.path])
        guard r.ok else { throw ImportError.extractFailed(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }

        cleanJunk(in: staging)

        // Unwrap a single top-level folder.
        var root = staging
        let top = (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { !$0.lastPathComponent.hasPrefix(".") } ?? []
        if top.count == 1, (try? top[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            root = top[0]
        }
        guard let contents = try? fm.contentsOfDirectory(atPath: root.path), !contents.isEmpty else { throw ImportError.empty }

        let baseName = root == staging ? zip.deletingPathExtension().lastPathComponent : root.lastPathComponent
        let dest = uniqueFolder(named: baseName, in: folder)
        try fm.moveItem(at: root, to: dest)
        return dest
    }

    /// Removes macOS junk and any symlinks that slipped through.
    static func cleanJunk(in dir: URL) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        var toRemove: [URL] = []
        for case let url as URL in en {
            let name = url.lastPathComponent
            if name == "__MACOSX" || name == ".DS_Store" || name.hasPrefix("._") {
                toRemove.append(url)
                if name == "__MACOSX" { en.skipDescendants() }
            } else if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                toRemove.append(url)
            }
        }
        for u in toRemove { try? fm.removeItem(at: u) }
    }

    // MARK: Templates

    static func create(from template: ProjectTemplate, name: String, in folder: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = uniqueFolder(named: name, in: folder)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: template.url, includingPropertiesForKeys: nil)
        for item in items where item.lastPathComponent != "template.json" {
            try fm.copyItem(at: item, to: dest.appendingPathComponent(item.lastPathComponent))
        }
        // Put the project name into the title placeholder.
        let main = dest.appendingPathComponent(template.mainFile)
        if var text = try? String(contentsOf: main, encoding: .utf8) {
            text = text.replacingOccurrences(of: "{{TITLE}}", with: latexEscape(name))
            try? text.write(to: main, atomically: true, encoding: .utf8)
        }
        return dest
    }

    static func latexEscape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&", "%", "$", "#", "_", "{", "}": out += "\\\(ch)"
            case "~": out += "\\textasciitilde{}"
            case "^": out += "\\textasciicircum{}"
            case "\\": out += "\\textbackslash{}"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: Helpers

    static func uniqueFolder(named raw: String, in folder: URL) -> URL {
        let cleaned = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Untitled" : cleaned
        var candidate = folder.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// All files under a project, relative paths, skipping build output and hidden folders.
    static func listFiles(in root: URL, extensions: Set<String>? = nil, limit: Int = 5000) -> [String] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsPackageDescendants]) else { return [] }
        var out: [String] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in en {
            let name = url.lastPathComponent
            if ignoredNames.contains(name) || (name.hasPrefix(".") && name != ".latexmkrc") {
                en.skipDescendants(); continue
            }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            if let exts = extensions, !exts.contains(url.pathExtension.lowercased()) { continue }
            var rel = url.standardizedFileURL.path
            if rel.hasPrefix(rootPath + "/") { rel.removeFirst(rootPath.count + 1) }
            out.append(rel)
            if out.count >= limit { break }
        }
        return out.sorted()
    }

    // MARK: Main file detection

    /// Ranks .tex files by how likely they are to be the root document. Best first.
    static func detectMainFiles(in root: URL) -> [String] {
        let texFiles = listFiles(in: root, extensions: ["tex", "ltx"])
        var scores: [String: Int] = [:]
        var magicRoots: [String] = []
        for rel in texFiles {
            let url = root.appendingPathComponent(rel)
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let data = (try? handle.read(upToCount: 96_000)) ?? Data()
            try? handle.close()
            let text = String(decoding: data, as: UTF8.self)
            var score = 0
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(4000)
            var hasClass = false, hasBegin = false
            for (i, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if i < 30, let m = magicRoot(line) {
                    let dir = (rel as NSString).deletingLastPathComponent
                    let target = ((dir as NSString).appendingPathComponent(m) as NSString).standardizingPath
                    magicRoots.append(target.hasSuffix(".tex") ? target : target + ".tex")
                }
                if line.hasPrefix("%") { continue }
                if line.contains("\\documentclass") { hasClass = true }
                if line.contains("\\begin{document}") { hasBegin = true }
            }
            if hasClass { score += 10 }
            if hasBegin { score += 10 }
            let base = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
            if ["main", "paper", "thesis", "root", "ms", "manuscript", "article", "report", "document"].contains(base) { score += 3 }
            if !rel.contains("/") { score += 2 }
            if score >= 10 { scores[rel] = score }
        }
        for m in magicRoots where texFiles.contains(m) { scores[m, default: 0] += 30 }
        return scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    static func magicRoot(_ line: String) -> String? {
        // % !TEX root = ../main.tex   (also accepts !TeX)
        let lower = line.lowercased()
        guard lower.hasPrefix("%"), lower.contains("!tex root") else { return nil }
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}
