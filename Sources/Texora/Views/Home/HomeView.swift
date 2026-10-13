import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var prompt = ""
    @State private var dropTargeted = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                    Text(greeting)
                        .font(.serif(40))
                        .foregroundStyle(theme.textColor)
                }
                .padding(.bottom, 32)

                composer
                    .padding(.bottom, 18)

                HStack(spacing: 8) {
                    PillButton(title: "New project", systemImage: "plus") { model.showNewProject = true }
                    PillButton(title: "Import ZIP", systemImage: "square.and.arrow.down") { model.chooseZipToImport() }
                    PillButton(title: "Open folder", systemImage: "folder") { model.chooseFolderToOpen() }
                }
                .padding(.bottom, 52)

                recent
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 40)
            .padding(.top, 110)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .onReceive(NotificationCenter.default.publisher(for: .focusHomeInput)) { _ in inputFocused = true }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// A tall, rounded composer card: text on top, tools on the left, send on the right.
    private var composer: some View {
        let empty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $prompt,
                      prompt: Text("Describe a new paper, or drop a .zip here").foregroundStyle(theme.mutedColor),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(theme.textColor)
                .lineLimit(2...8)
                .focused($inputFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                        prompt += "\n"
                        return .handled
                    }
                    submit()
                    return .handled
                }
            HStack(spacing: 6) {
                Menu {
                    Button("New project…") { model.showNewProject = true }
                    Button("Import ZIP…") { model.chooseZipToImport() }
                    Button("Open folder…") { model.chooseFolderToOpen() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.secondaryColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(theme.borderColor, lineWidth: 1))
                .help("Start from a template, a ZIP or a folder")
                Spacer()
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(empty ? theme.mutedColor : theme.bgColor)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(empty ? theme.surfaceColor : theme.accentColor))
                }
                .buttonStyle(.plain)
                .help("Create a project from this description (↩)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: Metrics.composerRadius, style: .continuous).fill(theme.elevatedColor))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.composerRadius, style: .continuous)
                .stroke(dropTargeted ? theme.accentColor : (inputFocused ? theme.accentColor.opacity(0.45) : theme.borderColor),
                        lineWidth: dropTargeted ? 1.5 : 1)
        )
        .softShadow()
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in model.handleDrop(providers) }
    }

    private func submit() {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        model.newProjectPrompt = p
        model.showNewProject = true
        prompt = ""
    }

    @ViewBuilder
    private var recent: some View {
        let projects = Array(model.library.recentProjects.prefix(8))
        if projects.isEmpty {
            VStack(spacing: 6) {
                Text("Start your first project")
                    .font(.serif(18))
                    .foregroundStyle(theme.textColor)
                Text("Create one from a template, import a ZIP from Overleaf, or open a folder.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.mutedColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            Text("Recents")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.mutedColor)
                .padding(.bottom, 8)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                ForEach(projects) { p in ProjectRow(project: p) }
            }
        }
    }
}

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var project: ProjectRecord

    var body: some View {
        Button { model.openProject(project.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.surfaceColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(theme.textColor)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.mutedColor).lineLimit(1)
                }
                Spacer()
                Text("Edited \(project.lastOpened.relativeDescription)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.mutedColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 56)
            .contentShape(Rectangle())
            .hoverHighlight(radius: 12)
        }
        .buttonStyle(.plain)
        .draggable(project.id.uuidString)
        .contextMenu { ProjectContextMenu(project: project) }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let c = project.collectionID, let col = model.library.collections.first(where: { $0.id == c }) { parts.append(col.name) }
        if !project.exists { parts.append("Missing on disk") } else { parts.append((project.path as NSString).abbreviatingWithTildeInPath) }
        return parts.joined(separator: " · ")
    }
}

struct ProjectContextMenu: View {
    @Environment(AppModel.self) private var model
    var project: ProjectRecord

    var body: some View {
        Button("Open") { model.openProject(project.id) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
        Menu("Move to collection") {
            Button("None") { model.library.update(project.id) { $0.collectionID = nil } }
            ForEach(model.library.collections) { c in
                Button(c.name) { model.library.update(project.id) { $0.collectionID = c.id } }
            }
        }
        Divider()
        Button("Remove from Texora") { model.library.removeProject(project.id) }
    }
}

struct ProjectsListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects").font(.serif(30)).foregroundStyle(theme.textColor)
                Spacer()
                PillButton(title: "New project", systemImage: "plus") { model.showNewProject = true }
            }
            .padding(.bottom, 18)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedColor)
                PlainField(placeholder: "Search projects", text: $query)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surfaceColor))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.borderColor, lineWidth: 1))
            .padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(filtered) { p in ProjectRow(project: p) }
                }
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, 48)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var filtered: [ProjectRecord] {
        let all = model.library.recentProjects
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}
