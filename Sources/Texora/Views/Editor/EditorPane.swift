import SwiftUI
import PDFKit

/// Hosts the workspace's persistent CodeMirror web view.
struct CodeMirrorView: NSViewRepresentable {
    let bridge: EditorBridge

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Only adopt the web view if it isn't living in another (newer) container already.
        if bridge.webView.superview == nil || bridge.webView.window == nil { attach(to: container) }
    }

    private func attach(to container: NSView) {
        bridge.webView.removeFromSuperview()
        bridge.webView.frame = container.bounds
        bridge.webView.autoresizingMask = [.width, .height]
        container.addSubview(bridge.webView)
    }
}

struct EditorPane: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            EditorTabs()
            ZStack(alignment: .topLeading) {
                CodeMirrorView(bridge: ws.editor)
                    .opacity(ws.isActiveEditable ? 1 : 0)
                if !ws.isActiveEditable {
                    if let path = ws.activePath {
                        FilePreview(path: path)
                    } else {
                        EmptyEditor()
                    }
                }
                if let ask = ws.ask, ask.source == .editor {
                    AskClaudeOverlay(request: ask)
                }
            }
            .overlay(alignment: .top) { ConflictBanner() }
            if ws.issuesVisible {
                ThemedDivider()
                IssuesPanel().frame(height: 210)
            }
            ThemedDivider()
            StatusStrip()
        }
        .background(theme.bgColor)
    }
}

private struct EditorTabs: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ws.openTabs, id: \.self) { path in
                    EditorTab(path: path)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        .frame(height: 36)
        .background(theme.bgColor)
        .overlay(alignment: .bottom) { ThemedDivider() }
    }
}

private struct EditorTab: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let path: String
    @State private var hovering = false

    var body: some View {
        let active = ws.activePath == path
        let dirty = ws.docs[path]?.isDirty ?? false
        HStack(spacing: 6) {
            Image(systemName: FileKind(path: path, isDirectory: false).icon)
                .font(.system(size: 11))
                .foregroundStyle(active ? theme.accentColor : theme.mutedColor)
            Text((path as NSString).lastPathComponent)
                .font(.system(size: 12.5, weight: active ? .medium : .regular))
                .foregroundStyle(active ? theme.textColor : theme.secondaryColor)
                .lineLimit(1)
            ZStack {
                if dirty && !hovering {
                    Circle().fill(theme.secondaryColor).frame(width: 6, height: 6)
                } else {
                    Button { ws.closeTab(path) } label: {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(theme.mutedColor)
                            .frame(width: 16, height: 16)
                            .hoverHighlight(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering || active ? 1 : 0)
                }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 30)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7, style: .continuous)
                .fill(active ? theme.surfaceColor : (hovering ? theme.hoverColor : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { ws.open(path) }
        .onHover { hovering = $0 }
        .help(path)
        .contextMenu {
            Button("Close") { ws.closeTab(path) }
            Button("Close Others") { for t in ws.openTabs where t != path { ws.closeTab(t) } }
            Divider()
            if path.hasSuffix(".tex") { Button("Set as Main File") { ws.setMainFile(path) } }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ws.url(for: path)]) }
        }
    }
}

private struct ConflictBanner: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        if let path = ws.activePath, ws.docs[path]?.conflictDisk != nil {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warningColor)
                Text("\((path as NSString).lastPathComponent) changed on disk while you had unsaved edits.")
                    .font(.system(size: 12.5)).foregroundStyle(theme.textColor)
                Spacer()
                PillButton(title: "Keep mine") { ws.resolveConflict(path, keepMine: true) }
                PillButton(title: "Use the new version", prominent: true) { ws.resolveConflict(path, keepMine: false) }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(theme.elevatedColor)
            .overlay(alignment: .bottom) { ThemedDivider() }
        }
    }
}

private struct EmptyEditor: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.plaintext").font(.system(size: 30, weight: .light)).foregroundStyle(theme.mutedColor)
            Text("Open a file from the sidebar").font(.system(size: 13)).foregroundStyle(theme.secondaryColor)
            if let main = ws.mainFile {
                PillButton(title: "Open \((main as NSString).lastPathComponent)") { ws.open(main) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
    }
}

/// Preview for images, PDFs and other files that aren't edited as text.
private struct FilePreview: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let path: String

    var body: some View {
        let url = ws.url(for: path)
        let kind = FileKind(path: path, isDirectory: false)
        Group {
            if kind == .image, let img = NSImage(contentsOf: url) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 900)
                        .padding(24)
                }
            } else if kind == .pdf {
                SimplePDFView(url: url)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: kind.icon).font(.system(size: 30, weight: .light)).foregroundStyle(theme.mutedColor)
                    Text("\((path as NSString).lastPathComponent) can't be shown here.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryColor)
                    PillButton(title: "Open with default app") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
    }
}

private struct SimplePDFView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(url: url)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

private struct StatusStrip: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        let c = ws.compiler
        HStack(spacing: 12) {
            Button { ws.issuesVisible.toggle() } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.octagon").font(.system(size: 10.5))
                        Text("\(c.errors.count)")
                    }
                    .foregroundStyle(c.errors.isEmpty ? theme.mutedColor : theme.dangerColor)
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 10.5))
                        Text("\(c.warnings.count)")
                    }
                    .foregroundStyle(c.warnings.isEmpty ? theme.mutedColor : theme.warningColor)
                }
                .font(.system(size: 11.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show issues")

            Group {
                switch c.status {
                case .running: Text(c.detail ?? "Compiling…")
                case .succeeded: Text(c.lastDuration.map { String(format: "Compiled in %.1fs", $0) } ?? "Compiled")
                case .failed: Text("Compile failed")
                case .unavailable: Text("No LaTeX engine")
                case .idle: Text("")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(theme.mutedColor)
            .lineLimit(1)

            Spacer()
            if ws.isActiveEditable {
                Text("Ln \(ws.cursorLine)").font(.system(size: 11.5)).foregroundStyle(theme.mutedColor).monospacedDigit()
            }
            Menu {
                ForEach(TexEngine.allCases) { e in
                    Button { ws.setEngine(e) } label: {
                        if e == ws.engine { Label(e.label, systemImage: "checkmark") } else { Text(e.label) }
                    }
                }
            } label: {
                Text(c.engineLabel ?? ws.engine.label).font(.system(size: 11.5)).foregroundStyle(theme.mutedColor)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("LaTeX engine")
            Menu {
                ForEach(ws.files.filter { $0.hasSuffix(".tex") }, id: \.self) { f in
                    Button { ws.setMainFile(f) } label: {
                        if f == ws.mainFile { Label(f, systemImage: "checkmark") } else { Text(f) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 8))
                    Text(ws.mainFile ?? "No main file")
                }
                .font(.system(size: 11.5)).foregroundStyle(theme.mutedColor)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Main file (the one that gets compiled)")
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(theme.bgColor)
    }
}

struct IssuesPanel: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @State private var filter: Filter = .all
    @State private var showLog = false

    enum Filter: Hashable { case all, errors, warnings, badboxes }

    var body: some View {
        let c = ws.compiler
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Issues").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.textColor)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        filterChip(.all, "All", c.issues.count, theme.secondaryColor)
                        filterChip(.errors, "Errors", c.errors.count, theme.dangerColor)
                        filterChip(.warnings, "Warnings", c.warnings.count, theme.warningColor)
                        filterChip(.badboxes, "Boxes", c.badboxes.count, theme.mutedColor)
                    }
                }
                Spacer(minLength: 4)
                if !c.errors.isEmpty {
                    PillButton(title: "Fix", systemImage: "sparkles") {
                        ws.chatVisible = true
                        ws.chat.send(text: ws.fixErrorsPrompt())
                    }
                    .fixedSize()
                    .help("Ask Claude to fix the compile errors")
                }
                IconButton(systemName: "doc.text", help: "Raw log", size: 12, active: showLog) { showLog.toggle() }
                IconButton(systemName: "xmark", help: "Close", size: 11) { ws.issuesVisible = false }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            if showLog {
                ScrollView {
                    Text(c.log.isEmpty ? "No log yet." : c.log)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.secondaryColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            } else {
                let items = filtered(c.issues)
                if items.isEmpty {
                    Text(c.status == .running ? "Compiling…" : "No issues.")
                        .font(.system(size: 12.5)).foregroundStyle(theme.mutedColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(items) { issue in IssueRow(issue: issue) }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                    }
                }
            }
        }
        .background(theme.sidebarColor)
    }

    private func filterChip(_ f: Filter, _ label: String, _ count: Int, _ color: Color) -> some View {
        Button { filter = f } label: {
            HStack(spacing: 4) {
                Text(label)
                Text("\(count)").foregroundStyle(count > 0 ? color : theme.mutedColor)
            }
            .font(.system(size: 11.5, weight: filter == f ? .medium : .regular))
            .foregroundStyle(filter == f ? theme.textColor : theme.secondaryColor)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(filter == f ? theme.elevatedColor : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func filtered(_ all: [CompileIssue]) -> [CompileIssue] {
        switch filter {
        case .all: return all
        case .errors: return all.filter { $0.severity == .error }
        case .warnings: return all.filter { $0.severity == .warning }
        case .badboxes: return all.filter { $0.severity == .badbox }
        }
    }
}

private struct IssueRow: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    let issue: CompileIssue

    var body: some View {
        Button { ws.reveal(issue: issue) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color).frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.message).font(.system(size: 12.5)).foregroundStyle(theme.textColor).lineLimit(2)
                    if let d = issue.detail, issue.severity == .error {
                        Text(d).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.mutedColor).lineLimit(2)
                    }
                }
                Spacer()
                if let f = issue.file {
                    Text(issue.line.map { "\((f as NSString).lastPathComponent):\($0)" } ?? (f as NSString).lastPathComponent)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(theme.mutedColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .hoverHighlight(radius: 6)
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch issue.severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .badbox: return "rectangle.badge.xmark"
        }
    }

    private var color: Color {
        switch issue.severity {
        case .error: return theme.dangerColor
        case .warning: return theme.warningColor
        case .badbox: return theme.mutedColor
        }
    }
}
