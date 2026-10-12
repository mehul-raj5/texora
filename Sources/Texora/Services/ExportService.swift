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

    /// Files that go into a project export (relative paths).
    static func exportFiles(root: URL, options: ExportOptions) -> [String] {
        ProjectImporter.listFiles(in: root, limit: 50_000).filter { rel in
            let lower = rel.lowercased()
            if lower.hasSuffix(".synctex.gz") || lower.hasSuffix(".run.xml") { return false }
            if auxExtensions.contains((lower as NSString).pathExtension) { return false }
            if !options.includeChatAttachments && (rel.hasPrefix("chatattachments/") || rel == "chatattachments") { return false }
            return true
        }
    }

    /// Writes a ZIP of the whole project. The archive contains one folder named after the project.
    static func exportZip(root: URL, projectName: String, mainFile: String?, to destination: URL, options: ExportOptions) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("texora-export-\(UUID().uuidString)", isDirectory: true)
        let folderName = projectName.replacingOccurrences(of: "/", with: "-")
        let top = staging.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: top, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

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
