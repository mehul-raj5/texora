import SwiftUI

/// The strip along the top of the content area: sidebar toggle, breadcrumb, actions, theme.
/// It doubles as the window's drag handle, since the title bar is hidden.
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "sidebar.left", help: "Toggle sidebar (⌘B)") {
                model.sidebarVisible.toggle()
            }
            breadcrumb
            Spacer(minLength: 12)
            if case .project = model.route, let ws = model.workspace {
                WorkspaceToolbar().environment(ws)
            }
            ThemeButton()
        }
        .padding(.leading, model.sidebarVisible ? 10 : 78)
        .padding(.trailing, 10)
        .frame(height: 44)
        .background(theme.bgColor)
        .gesture(WindowDragGesture())
        .overlay(alignment: .bottom) {
            if case .project = model.route { ThemedDivider() }
        }
    }

    @ViewBuilder
    private var breadcrumb: some View {
        HStack(spacing: 6) {
            switch model.route {
            case .home:
                crumb("Home", current: true)
            case .projects:
                crumb("Home") { model.goHome() }
                chevron
                crumb("Projects", current: true)
            case .project:
                crumb("Home") { model.goHome() }
                chevron
                if let ws = model.workspace {
                    crumb(ws.record.name, current: ws.activePath == nil)
                    if let file = ws.activePath {
                        chevron
                        crumb(file, current: true)
                    }
                }
            }
        }
        .lineLimit(1)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.mutedColor)
    }

    private func crumb(_ title: String, current: Bool = false, action: (() -> Void)? = nil) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    Text(title).foregroundStyle(theme.secondaryColor)
                }
                .buttonStyle(.plain)
            } else {
                Text(title).foregroundStyle(current ? theme.textColor : theme.secondaryColor)
            }
        }
        .font(.system(size: 13, weight: current ? .medium : .regular))
    }
}
