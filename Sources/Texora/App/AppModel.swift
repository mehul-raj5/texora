import SwiftUI
import Observation

/// App-wide state: library, settings, theme, navigation and the open workspace.
@MainActor
@Observable
final class AppModel {
    enum Route: Hashable {
        case home
        case projects
        case project(UUID)
    }

    let settings = AppSettings()
    let themes = ThemeManager()
    let library = LibraryStore()
    let tools = ToolLocator()

    var route: Route = .home
    var sidebarVisible = true
    var showNewProject = false
    var newProjectPrompt: String = ""
    var errorMessage: String?
    var busyMessage: String?

    /// The project currently open in the workspace, if any.
    private(set) var workspace: WorkspaceModel?

    init() {}

    // MARK: Navigation

    func goHome() { route = .home }

    func openProject(_ id: UUID, chat: UUID? = nil) {
        guard let record = library.project(id) else { return }
        guard record.exists else {
            errorMessage = "“\(record.name)” isn't at \(record.path) any more. It may have been moved or deleted."
            return
        }
        library.update(id) { $0.lastOpened = Date() }
        if workspace?.projectID != id {
            workspace?.close()
            workspace = WorkspaceModel(record: record, app: self)
        }
        if let chat { workspace?.chat.select(chatID: chat) }
        route = .project(id)
    }

    func closeWorkspace() {
        workspace?.close()
        workspace = nil
        route = .home
    }

    func showError(_ message: String) { errorMessage = message }
}
