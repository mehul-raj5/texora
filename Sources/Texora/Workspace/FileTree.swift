import Foundation

struct FileNode: Identifiable, Hashable {
    let path: String          // relative to project root
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
    var id: String { path }

    var kind: FileKind { FileKind(path: path, isDirectory: isDirectory) }
}

enum FileKind {
    case folder, tex, bib, style, image, pdf, data, code, text, other

    init(path: String, isDirectory: Bool) {
        if isDirectory { self = .folder; return }
        switch (path as NSString).pathExtension.lowercased() {
        case "tex", "ltx", "latex": self = .tex
        case "bib", "bst": self = .bib
        case "cls", "sty", "def", "cfg", "clo": self = .style
        case "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "eps", "svg", "webp", "heic": self = .image
        case "pdf": self = .pdf
        case "csv", "tsv", "json", "dat", "xlsx", "xls", "parquet", "npy": self = .data
        case "py", "r", "m", "jl", "sh", "js", "lua", "ipynb", "c", "cpp", "h": self = .code
        case "txt", "md", "markdown", "log", "yml", "yaml", "toml", "latexmkrc", "rst", "org", "bbl": self = .text
        default:
            self = (path as NSString).lastPathComponent == ".latexmkrc" ? .text : .other
        }
    }

    var icon: String {
        switch self {
        case .folder: return "folder"
        case .tex: return "doc.plaintext"
        case .bib: return "books.vertical"
        case .style: return "paintbrush"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .data: return "tablecells"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .other: return "doc"
        }
    }

    /// Files Texora opens in the code editor.
    var isEditableText: Bool {
        switch self {
        case .tex, .bib, .style, .code, .text: return true
        case .data: return true
        default: return false
        }
    }
}

enum FileTreeBuilder {
    static let skipped: Set<String> = [".build", ".git", "__MACOSX", ".DS_Store", "node_modules", ".texora", ".Trash"]

    static func build(root: URL) -> [FileNode] {
        children(of: root, relative: "", depth: 0)
    }

    private static func children(of dir: URL, relative: String, depth: Int) -> [FileNode] {
        guard depth < 12,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return [] }
        var nodes: [FileNode] = []
        for url in items {
            let name = url.lastPathComponent
            if skipped.contains(name) || name.hasPrefix(".texora") { continue }
            if name.hasPrefix(".") && name != ".latexmkrc" { continue }
            let rel = relative.isEmpty ? name : "\(relative)/\(name)"
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                nodes.append(FileNode(path: rel, name: name, isDirectory: true,
                                      children: children(of: url, relative: rel, depth: depth + 1)))
            } else {
                nodes.append(FileNode(path: rel, name: name, isDirectory: false, children: nil))
            }
        }
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func flatten(_ nodes: [FileNode]) -> [String] {
        nodes.flatMap { n -> [String] in n.isDirectory ? flatten(n.children ?? []) : [n.path] }
    }
}
