import Foundation

enum Paths {
    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Texora", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var libraryFile: URL { appSupport.appendingPathComponent("library.json") }

    static var chatsDir: URL { ensure(appSupport.appendingPathComponent("chats", isDirectory: true)) }

    static var historyDir: URL { ensure(appSupport.appendingPathComponent("history", isDirectory: true)) }

    /// Bundled resources (editor web bundle, templates). Inside the .app they live in Contents/Resources;
    /// when running with `swift run` they are read straight from the repo's Resources folder.
    static let resources: URL = {
        if let r = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: r.appendingPathComponent("editor/index.html").path) {
            return r
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() } // Support → Texora → Sources → repo
        return url.appendingPathComponent("Resources", isDirectory: true)
    }()

    static var editorDir: URL { resources.appendingPathComponent("editor", isDirectory: true) }
    static var templatesDir: URL { resources.appendingPathComponent("Templates", isDirectory: true) }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
