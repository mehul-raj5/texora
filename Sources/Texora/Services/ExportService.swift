import Foundation

struct ExportOptions {
    var includePDF = true
    var includeBbl = false
    var includeChatAttachments = false
}

enum ExportService {
    static let auxExtensions: Set<String> = [
        "aux", "log", "synctex", "fdb_latexmk", "fls", "out", "toc", "lof", "lot", "blg", "bcf",
        "xdv", "nav", "snm", "vrb", "idx", "ilg", "ind", "pdfsync", "run.xml",
    ]

    /// Files that go into a project export (relative paths): everything in the project (sources,
    /// figures, data, any other files and folders) except build output, macOS junk and chat attachments.
    /// Aux-type files are only treated as build by-products when they sit next to a .tex file with the
    /// same name (main.aux beside main.tex), so data files like results.log are kept.
    static func exportFiles(root: URL, options: ExportOptions) -> [String] {
        let all = ProjectImporter.listFiles(in: root, limit: 100_000)
        let texBases = Set(all.filter { $0.lowercased().hasSuffix(".tex") }.map { ($0 as NSString).deletingPathExtension })
        return all.filter { rel in
            let lower = rel.lowercased()
            if !options.includeChatAttachments && (rel.hasPrefix("chatattachments/") || rel == "chatattachments") { return false }
            if (rel as NSString).lastPathComponent.hasPrefix("._") { return false }
            var base = (rel as NSString).deletingPathExtension
            var ext = (lower as NSString).pathExtension
            if lower.hasSuffix(".synctex.gz") { base = (base as NSString).deletingPathExtension; ext = "synctex" }
            if lower.hasSuffix(".run.xml") { base = (base as NSString).deletingPathExtension; ext = "run.xml" }
            if auxExtensions.contains(ext) && texBases.contains(base) { return false }
            return true
        }
    }

    /// Folders to recreate in the export, so empty folders are kept too.
    static func exportFolders(root: URL, options: ExportOptions) -> [String] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [String] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in en {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = url.lastPathComponent
            if ProjectImporter.ignoredNames.contains(name) || name.hasPrefix(".") || (!options.includeChatAttachments && name == "chatattachments" && url.deletingLastPathComponent().standardizedFileURL.path == rootPath) {
                en.skipDescendants(); continue
            }
            var rel = url.standardizedFileURL.path
            if rel.hasPrefix(rootPath + "/") { rel.removeFirst(rootPath.count + 1) }
            out.append(rel)
        }
        return out
    }

    /// True if any .tex file points into chatattachments/ (then excluding it would break the export).
    static func texReferencesChatAttachments(root: URL) -> Bool {
        for rel in ProjectImporter.listFiles(in: root, extensions: ["tex"]) {
            if let text = try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8),
               text.contains("chatattachments/") { return true }
        }
        return false
    }

    /// Writes a ZIP of the whole project. The archive contains one folder named after the project.
    static func exportZip(root: URL, projectName: String, mainFile: String?, to destination: URL, options: ExportOptions) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("texora-export-\(UUID().uuidString)", isDirectory: true)
        let folderName = projectName.replacingOccurrences(of: "/", with: "-")
        let top = staging.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: top, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for folder in exportFolders(root: root, options: options) {
            try fm.createDirectory(at: top.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for rel in exportFiles(root: root, options: options) {
            let src = root.appendingPathComponent(rel)
            let dst = top.appendingPathComponent(rel)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dst)
        }
        if let main = mainFile {
            let job = ((main as NSString).deletingPathExtension as NSString).lastPathComponent
            let mainDir = (main as NSString).deletingLastPathComponent
            if options.includePDF {
                let pdf = root.appendingPathComponent(".build/\(job).pdf")
                if fm.fileExists(atPath: pdf.path) {
                    let dst = top.appendingPathComponent(mainDir).appendingPathComponent("\(job).pdf")
                    try? fm.removeItem(at: dst)
                    try fm.copyItem(at: pdf, to: dst)
                }
            }
            if options.includeBbl {
                let bbl = root.appendingPathComponent(".build/\(job).bbl")
                if fm.fileExists(atPath: bbl.path) {
                    let dst = top.appendingPathComponent(mainDir).appendingPathComponent("\(job).bbl")
                    try? fm.removeItem(at: dst)
                    try fm.copyItem(at: bbl, to: dst)
                }
            }
        }
        try? fm.removeItem(at: destination)
        let r = ProcessRunner.runSync("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", top.path, destination.path])
        if !r.ok {
            throw NSError(domain: "Texora", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't create the ZIP. \(r.stderr)"])
        }
    }
}
