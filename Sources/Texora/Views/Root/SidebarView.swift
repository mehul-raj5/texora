import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Room for the traffic lights; also lets you drag the window from here.
            Color.clear.frame(height: 48).contentShape(Rectangle()).gesture(WindowDragGesture())
            if case .project = model.route, let ws = model.workspace {
                ProjectSidebar().environment(ws)
            } else {
                HomeSidebar()
            }
            SettingsRow()
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
        }
    }
}

private struct SettingsRow: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        SidebarRow(icon: "slider.horizontal.3", title: "Settings") { openSettings() }
            .onAppear { DebugAutomation.openSettings = { openSettings() } }
    }
}

/// Sidebar when no project is open: Home, Projects, Chats, Collections.
struct HomeSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var newCollectionName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                NewChatRow {
                    model.goHome()
                    NotificationCenter.default.post(name: .focusHomeInput, object: nil)
                }
                .padding(.bottom, 4)
                SidebarRow(icon: "house", title: "Home", selected: model.route == .home) { model.goHome() }
                SidebarRow(icon: "doc.text", title: "Projects", count: model.library.projects.count,
                           selected: model.route == .projects) { model.route = .projects }

                SidebarSectionLabel(title: "Recents")
                let chats = Array(model.library.recentChats.prefix(12))
                if chats.isEmpty {
                    Text("Your chats will be listed here.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.mutedColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    ForEach(chats) { chat in
                        SidebarRow(icon: nil, title: chat.title) {
                            model.openProject(chat.projectID, chat: chat.id)
                        }
                        .help(model.library.project(chat.projectID)?.name ?? "")
                    }
                }

                SidebarSectionLabel(title: "Collections")
                if let name = newCollectionName {
                    HStack(spacing: 9) {
                        Image(systemName: "folder").font(.system(size: 13)).frame(width: 18).foregroundStyle(theme.secondaryColor)
                        PlainField(placeholder: "Collection name", text: Binding(get: { name }, set: { newCollectionName = $0 })) {
                            let trimmed = (newCollectionName ?? "").trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { _ = model.library.addCollection(named: trimmed) }
                            newCollectionName = nil
                        }
                        .onExitCommand { newCollectionName = nil }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 33)
                } else {
                    SidebarRow(icon: "plus", title: "New collection") { newCollectionName = "" }
                }
                ForEach(model.library.collections) { c in
                    CollectionRows(collection: c)
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.never)
    }
}

/// The primary sidebar action: an accent disc with a plus, like a "new chat" button.
private struct NewChatRow: View {
    @Environment(\.theme) private var theme
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.bgColor)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(theme.accentColor))
                    .frame(width: 20)
                Text("New chat")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(theme.textColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .fill(hovering ? theme.hoverColor : .clear))
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

struct DisclosureRow: View {
    @Environment(\.theme) private var theme
    var title: String
    @Binding var expanded: Bool

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(theme.secondaryColor)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(.plain)
    }
}

private struct CollectionRows: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var collection: CollectionRecord
    @State private var renaming: String?

    var body: some View {
        let projects = model.library.projects(in: collection.id)
        VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    model.library.collections = model.library.collections.map {
                        var c = $0; if c.id == collection.id { c.isExpanded.toggle() }; return c
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(collection.isExpanded ? 90 : 0))
                        .frame(width: 12)
                    Image(systemName: collection.isExpanded ? "folder" : "folder")
                        .font(.system(size: 13))
                    if let name = renaming {
                        PlainField(placeholder: "Name", text: Binding(get: { name }, set: { renaming = $0 })) {
                            let n = (renaming ?? "").trimmingCharacters(in: .whitespaces)
                            if !n.isEmpty {
                                model.library.collections = model.library.collections.map {
                                    var c = $0; if c.id == collection.id { c.name = n }; return c
                                }
                            }
                            renaming = nil
                        }
                    } else {
                        Text(collection.name).font(.system(size: 13)).lineLimit(1)
                    }
                    Spacer()
                    Text("\(projects.count)").font(.system(size: 12)).foregroundStyle(theme.mutedColor)
                }
                .foregroundStyle(theme.secondaryColor)
                .padding(.horizontal, 10)
                .frame(height: 33)
                .contentShape(Rectangle())
                .hoverHighlight()
            }
            .buttonStyle(.plain)
            .dropDestination(for: String.self) { items, _ in
                for item in items {
                    if let id = UUID(uuidString: item) { model.library.update(id) { $0.collectionID = collection.id } }
                }
                return true
            }
            .contextMenu {
                Button("Rename") { renaming = collection.name }
                Button("Delete collection", role: .destructive) { model.library.removeCollection(collection.id) }
            }
            if collection.isExpanded {
                ForEach(projects) { p in
                    SidebarRow(icon: "doc.text", title: p.name, indent: 22) { model.openProject(p.id) }
                        .draggable(p.id.uuidString)
                }
            }
        }
    }
}

extension Notification.Name {
    static let focusHomeInput = Notification.Name("texora.focusHomeInput")
}
