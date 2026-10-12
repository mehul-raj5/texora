import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var prompt = ""
    @State private var dropTargeted = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(greeting)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.textColor)
                    .padding(.bottom, 28)

                inputBox
                    .padding(.bottom, 16)

                HStack(spacing: 10) {
                    PillButton(title: "New project", systemImage: "plus") { model.showNewProject = true }
                    PillButton(title: "Import ZIP", systemImage: "square.and.arrow.down") { model.chooseZipToImport() }
                    PillButton(title: "Open folder", systemImage: "folder") { model.chooseFolderToOpen() }
                }
                .padding(.bottom, 44)

                recent
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.top, 72)
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

    private var inputBox: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15))
                .foregroundStyle(theme.accentColor)
            TextField("", text: $prompt, prompt: Text("Describe a new paper, or drop a .zip here").foregroundStyle(theme.mutedColor))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(theme.textColor)
                .focused($inputFocused)
                .onSubmit(submit)
            Button(action: submit) {
                HStack(spacing: 6) {
                    Text("Create")
                    Image(systemName: "return")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryColor)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.elevatedColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surfaceColor))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(dropTargeted ? theme.accentColor : theme.borderColor.opacity(0.6), lineWidth: dropTargeted ? 1.5 : 1)
        )
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.textColor)
                Text("Create one from a template, import a ZIP from Overleaf, or open a folder.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.mutedColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            Text("Recent")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.mutedColor)
                .padding(.bottom, 8)
                .padding(.leading, 4)
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
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.surfaceColor))
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
            .frame(height: 52)
            .contentShape(Rectangle())
            .hoverHighlight(radius: 10)
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
                Text("Projects").font(.system(size: 26, weight: .bold)).foregroundStyle(theme.textColor)
                Spacer()
                PillButton(title: "New project", systemImage: "plus") { model.showNewProject = true }
            }
            .padding(.bottom, 18)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedColor)
                PlainField(placeholder: "Search projects", text: $query)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceColor))
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
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var filtered: [ProjectRecord] {
        let all = model.library.recentProjects
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}
