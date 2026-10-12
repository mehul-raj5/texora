import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppModel {
    // MARK: Pickers

    func chooseZipToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a LaTeX project ZIP to import"
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url { importZip(url) }
    }

    func chooseFolderToOpen() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder that contains a LaTeX project"
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url { openFolder(url) }
    }

    // MARK: Import / open / create

    func importZip(_ zip: URL) {
        busyMessage = "Importing \(zip.lastPathComponent)…"
        let dest = settings.projectsFolderURL
        Task {
            let result: Result<URL, Error> = await Task.detached {
                do { return .success(try ProjectImporter.importZip(zip, into: dest)) } catch { return .failure(error) }
            }.value
            busyMessage = nil
            switch result {
            case .success(let root):
                let id = register(root: root, name: root.lastPathComponent)
                openProject(id)
            case .failure(let error):
                showError(error.localizedDescription)
            }
        }
    }

    func openFolder(_ url: URL) {
        let id = register(root: url, name: url.lastPathComponent)
        openProject(id)
    }

    func createProject(name: String, template: ProjectTemplate, prompt: String?) {
        do {
            let root = try ProjectImporter.create(from: template, name: name, in: settings.projectsFolderURL)
            let id = register(root: root, name: root.lastPathComponent, mainFile: template.mainFile)
            openProject(id)
            if let prompt, !prompt.isEmpty, let ws = workspace {
                ws.chatVisible = true
                ws.chat.send(text: "This is a brand-new project created from the “\(template.name)” template. Set it up for the following: \(prompt)\n\nWrite real starter content (title, sections, any packages needed) directly into the files.")
            }
        } catch {
            showError("Couldn't create the project. \(error.localizedDescription)")
        }
    }

    /// Adds a folder to the library (or finds it) and returns its id.
    @discardableResult
    func register(root: URL, name: String, mainFile: String? = nil) -> UUID {
        if let existing = library.project(atPath: root.path) { return existing.id }
        let main = mainFile ?? ProjectImporter.detectMainFiles(in: root).first
        let record = ProjectRecord(name: name, path: root.standardizedFileURL.path, mainFile: main)
        return library.addProject(record).id
    }

    // MARK: Drops and Finder "open"

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in self.handleOpen(url: url) }
            }
        }
        return handled
    }

    func handleOpen(url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            openFolder(url)
        } else if url.pathExtension.lowercased() == "zip" {
            importZip(url)
        } else if ["tex", "bib", "sty", "cls"].contains(url.pathExtension.lowercased()) {
            openFolder(url.deletingLastPathComponent())
        }
    }
}
