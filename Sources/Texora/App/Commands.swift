import SwiftUI

struct TexoraCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { model.showNewProject = true }
                .keyboardShortcut("n")
            Button("Import ZIP…") { model.chooseZipToImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Open Folder…") { model.chooseFolderToOpen() }
                .keyboardShortcut("o")
            Divider()
            Button("Close Project") { model.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save and Recompile") { model.workspace?.compile(reason: .manual) }
                .keyboardShortcut("s")
                .disabled(model.workspace == nil)
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Export") {
                Button("Project as ZIP…") { model.workspace?.exportZip() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("PDF…") { model.workspace?.exportPDF() }
            }
            .disabled(model.workspace == nil)
        }
        CommandMenu("Project") {
            Button("Recompile") { model.workspace?.compile(reason: .manual) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.workspace == nil)
            Button("Ask Claude About Selection") { model.workspace?.askClaudeAboutSelection() }
                .keyboardShortcut("k")
                .disabled(model.workspace == nil)
            Button("Send Selection to Chat") { model.workspace?.sendSelectionToChat() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
            Divider()
            Button("Files") { model.workspace?.sidebarTab = .files }
                .keyboardShortcut("1")
            Button("Outline") { model.workspace?.sidebarTab = .outline }
                .keyboardShortcut("2")
            Button("History") { model.workspace?.sidebarTab = .history }
                .keyboardShortcut("3")
            Divider()
            Button("Code Only") { model.workspace?.layout = .code }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Code and PDF") { model.workspace?.layout = .split }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("PDF Only") { model.workspace?.layout = .pdf }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Divider()
            Button("Save Checkpoint…") { model.workspace?.promptCheckpoint() }
                .disabled(model.workspace == nil)
            Button("Reveal in Finder") {
                if let ws = model.workspace { NSWorkspace.shared.activateFileViewerSelecting([ws.root]) }
            }
            .disabled(model.workspace == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { model.sidebarVisible.toggle() }
                .keyboardShortcut("b")
            Button("Toggle Chat") { model.workspace?.chatVisible.toggle() }
                .keyboardShortcut("l")
                .disabled(model.workspace == nil)
            Button("Switch Light/Dark Theme") { model.themes.toggleLightDark() }
                .keyboardShortcut("t", modifiers: [.command, .control])
        }
    }
}
