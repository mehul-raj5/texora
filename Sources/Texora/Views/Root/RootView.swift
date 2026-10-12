import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            if model.sidebarVisible {
                SidebarView()
                    .frame(width: 248)
                    .background(theme.sidebarColor)
                    .transition(.move(edge: .leading))
                ThemedDivider(vertical: true)
            }
            VStack(spacing: 0) {
                TopBar()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(theme.bgColor)
        }
        .background(theme.bgColor)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.18), value: model.sidebarVisible)
        .overlay(alignment: .bottom) { BusyToast() }
        .sheet(isPresented: $model.showNewProject) {
            NewProjectSheet()
                .environment(model)
                .environment(\.theme, theme)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            model.handleDrop(providers)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .home:
            HomeView()
        case .projects:
            ProjectsListView()
        case .project:
            if let ws = model.workspace {
                WorkspaceView()
                    .environment(ws)
                    .id(ws.projectID)
            } else {
                HomeView()
            }
        }
    }
}

/// Small floating status for long operations (importing, installing packages…).
struct BusyToast: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        if let msg = model.busyMessage {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(msg).font(.system(size: 13)).foregroundStyle(theme.textColor)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(theme.elevatedColor))
            .overlay(Capsule().stroke(theme.borderColor, lineWidth: 1))
            .padding(.bottom, 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
