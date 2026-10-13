import SwiftUI
import UniformTypeIdentifiers

struct ProjectSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var ws = ws
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                SidebarRow(icon: "chevron.left", title: "Home") { app.goHome() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ws.record.name)
                        .font(.serif(19))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                    Text(ws.mainFile.map { "Main file: \($0)" } ?? "No main file")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.mutedColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 10)
                ThemedSegmented(options: [(WorkspaceModel.SidebarTab.files, "Files"), (.outline, "Outline"), (.history, "History")],
                                selection: $ws.sidebarTab)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 8)

            Group {
                switch ws.sidebarTab {
                case .files: FileTreeView()
                case .outline: OutlineView()
                case .history: HistoryView()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            ProjectChatsSection()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
    }
}

private struct ProjectChatsSection: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ThemedDivider().padding(.bottom, 6).padding(.horizontal, -8)
            HStack {
                DisclosureRow(title: "Chats", expanded: $expanded)
                Button { ws.chat.newChat(); ws.chatVisible = true } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 12)).foregroundStyle(theme.secondaryColor)
                        .frame(width: 24, height: 24).hoverHighlight(radius: 6)
                }
                .buttonStyle(.plain)
                .help("New chat")
            }
            if expanded {
                let chats = Array(ws.chat.chats.prefix(5))
                if chats.isEmpty {
                    Text("Your chats will be listed here.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.mutedColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    ForEach(chats) { c in
                        SidebarRow(icon: "bubble.left", title: c.title, selected: c.id == ws.chat.activeChatID) {
                            ws.chat.select(chatID: c.id)
                            ws.chatVisible = true
                        }
                        .contextMenu {
                            Button("Delete chat", role: .destructive) { ws.chat.deleteChat(c.id) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Files

struct FileTreeView: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text("Files").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.mutedColor)
                Spacer()
                IconButton(systemName: "doc.badge.plus", help: "New file", size: 12) { ws.promptNewFile(in: nil) }
                IconButton(systemName: "folder.badge.plus", help: "New folder", size: 12) { ws.promptNewFolder(in: nil) }
                IconButton(systemName: "square.and.arrow.down", help: "Add files from Finder", size: 12) { pickFiles(into: nil) }
            }
            .padding(.leading, 20)
            .padding(.trailing, 10)
            .frame(height: 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(ws.tree) { node in FileNodeRow(node: node, depth: 0) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .background(dropTargeted ? theme.accentColor.opacity(0.08) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers) { urls in ws.addFiles(urls, to: nil) }
            return true
        }
    }

    private func pickFiles(into folder: String?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Add to project"
        if panel.runModal() == .OK { ws.addFiles(panel.urls, to: folder) }
    }
}

func askForName(title: String, placeholder: String, initial: String = "") -> String? {
    let alert = NSAlert()
    alert.messageText = title
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = placeholder
    field.stringValue = initial
    alert.accessoryView = field
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
    return name
}

func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for p in providers where p.canLoadObject(ofClass: URL.self) {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { MainActor.assumeIsolated { completion(urls) } }
}

private struct FileNodeRow: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let node: FileNode
    let depth: Int
    @State private var dropTargeted = false

    var body: some View {
        let expanded = ws.expandedFolders.contains(node.path)
        VStack(alignment: .leading, spacing: 1) {
            Button {
                if node.isDirectory {
                    withAnimation(.easeOut(duration: 0.12)) {
                        if expanded { ws.expandedFolders.remove(node.path) } else { ws.expandedFolders.insert(node.path) }
                    }
                } else {
                    ws.open(node.path)
                }
            } label: {
                HStack(spacing: 6) {
                    if node.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(theme.mutedColor)
                            .frame(width: 10)
                    } else {
                        Spacer().frame(width: 10)
                    }
                    Image(systemName: node.isDirectory ? (expanded ? "folder" : "folder") : node.kind.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(node.path == ws.mainFile ? theme.accentColor : theme.secondaryColor)
                        .frame(width: 16)
                    Text(node.name)
                        .font(.system(size: 13))
                        .foregroundStyle(ws.activePath == node.path ? theme.textColor : theme.secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if node.path == ws.mainFile {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(theme.accentColor)
                            .help("Main file")
                    }
                    Spacer(minLength: 0)
                    if ws.docs[node.path]?.isDirty == true {
                        Circle().fill(theme.secondaryColor).frame(width: 5, height: 5)
                    }
                }
                .padding(.leading, 8 + CGFloat(depth) * 14)
                .padding(.trailing, 8)
                .frame(height: 27)
                .contentShape(Rectangle())
                .hoverHighlight(selected: ws.activePath == node.path)
                .background(dropTargeted ? RoundedRectangle(cornerRadius: 7).fill(theme.accentColor.opacity(0.12)) : nil)
            }
            .buttonStyle(.plain)
            .contextMenu { menu }
            .onDrop(of: [.fileURL], isTargeted: node.isDirectory ? $dropTargeted : .constant(false)) { providers in
                guard node.isDirectory else { return false }
                loadURLs(providers) { urls in ws.addFiles(urls, to: node.path) }
                return true
            }
            if node.isDirectory && expanded {
                ForEach(node.children ?? []) { child in FileNodeRow(node: child, depth: depth + 1) }
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if node.isDirectory {
            Button("New File…") { ws.promptNewFile(in: node.path) }
            Button("New Folder…") { ws.promptNewFolder(in: node.path) }
            Divider()
        } else {
            Button("Open") { ws.open(node.path) }
            if node.kind == .tex { Button("Set as Main File") { ws.setMainFile(node.path) } }
            Button("Attach to Chat") {
                ws.chat.pendingAttachments.append(ws.url(for: node.path))
                ws.chatVisible = true
            }
            Divider()
        }
        Button("Rename…") {
            if let name = askForName(title: "Rename", placeholder: node.name, initial: node.name) { ws.rename(node.path, to: name) }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ws.url(for: node.path)]) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.path, forType: .string)
        }
        Divider()
        Button("Move to Trash", role: .destructive) { ws.trash(node.path) }
    }
}

// MARK: - Outline

struct OutlineView: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("File outline").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.mutedColor)
                Spacer()
                if !ws.outlineTree.isEmpty {
                    Button(collapsed.isEmpty ? "Collapse" : "Expand") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            if collapsed.isEmpty { collapsed = Set(allParents(ws.outlineTree)) } else { collapsed.removeAll() }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.mutedColor)
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .frame(height: 28)
            if ws.outlineTree.isEmpty {
                Text("Sections, subsections and chapters appear here as you write them.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.mutedColor)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(ws.outlineTree) { item in OutlineRow(item: item, collapsed: $collapsed) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: ws.activeOutlineID) {
                        if let id = ws.activeOutlineID { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
    }

    private func allParents(_ items: [OutlineItem]) -> [String] {
        items.flatMap { $0.children.isEmpty ? [] : [$0.id] + allParents($0.children) }
    }
}

private struct OutlineRow: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let item: OutlineItem
    @Binding var collapsed: Set<String>

    var body: some View {
        let isCollapsed = collapsed.contains(item.id)
        let active = ws.activeOutlineID == item.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if !item.children.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            if isCollapsed { collapsed.remove(item.id) } else { collapsed.insert(item.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                            .foregroundStyle(theme.secondaryColor)
                            .frame(width: 16, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 16)
                }
                Button { ws.jump(to: item) } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: item.level <= 1 ? .semibold : .regular))
                        .foregroundStyle(active ? theme.textColor : theme.secondaryColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .hoverHighlight(selected: active)
                }
                .buttonStyle(.plain)
                .help("\(item.file):\(item.line)")
            }
            .id(item.id)
            if !item.children.isEmpty && !isCollapsed {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(theme.borderColor).frame(width: 1).padding(.leading, 8).padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(item.children) { child in OutlineRow(item: child, collapsed: $collapsed) }
                    }
                    .padding(.leading, 6)
                }
            }
        }
    }
}
