import SwiftUI

struct WorkspaceView: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var ws = ws
        HStack(spacing: 0) {
            center
                .frame(maxWidth: .infinity)
            if ws.chatVisible {
                ResizeHandle(value: $ws.chatWidth, range: 300...640, invert: true)
                ChatPanel()
                    .frame(width: ws.chatWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.18), value: ws.chatVisible)
        .animation(.easeOut(duration: 0.18), value: ws.layout)
        .sheet(isPresented: $ws.showExport) {
            ExportSheet().environment(ws).environment(\.theme, theme)
        }
        .sheet(item: $ws.diffEntry) { entry in
            DiffView(entry: entry).environment(ws).environment(\.theme, theme)
        }
        .onChange(of: theme) { ws.editor.setTheme(theme); ws.pdf.accentColor = NSColor(hex: theme.accent) }
        .onChange(of: settings.editorFontSize) { pushOptions() }
        .onChange(of: settings.lineWrap) { pushOptions() }
        .onChange(of: settings.vimMode) { pushOptions() }
        .onAppear { ws.pdf.accentColor = NSColor(hex: theme.accent) }
    }

    private func pushOptions() {
        ws.editor.setOptions(["fontSize": settings.editorFontSize, "wrap": settings.lineWrap, "vim": settings.vimMode])
    }

    @ViewBuilder
    private var center: some View {
        @Bindable var ws = ws
        switch ws.layout {
        case .code:
            EditorPane()
        case .pdf:
            PDFPane()
        case .split:
            GeometryReader { geo in
                HStack(spacing: 0) {
                    EditorPane()
                        .frame(width: max(260, min(geo.size.width - 260, geo.size.width * ws.splitFraction)))
                    SplitHandle(fraction: $ws.splitFraction, totalWidth: geo.size.width)
                    PDFPane()
                }
            }
        }
    }
}

/// Draggable divider between the editor and the PDF.
struct SplitHandle: View {
    @Environment(\.theme) private var theme
    @Binding var fraction: CGFloat
    let totalWidth: CGFloat
    @State private var start: CGFloat?

    var body: some View {
        ThemedDivider(vertical: true)
            .overlay(
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                if start == nil { start = fraction }
                                fraction = min(0.8, max(0.2, (start ?? 0.5) + v.translation.width / max(totalWidth, 1)))
                            }
                            .onEnded { _ in start = nil }
                    )
            )
    }
}

/// Draggable divider that resizes a side panel (e.g. the chat).
struct ResizeHandle: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var invert = false
    @State private var start: CGFloat?

    var body: some View {
        ThemedDivider(vertical: true)
            .overlay(
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                if start == nil { start = value }
                                let delta = invert ? -v.translation.width : v.translation.width
                                value = min(range.upperBound, max(range.lowerBound, (start ?? value) + delta))
                            }
                            .onEnded { _ in start = nil }
                    )
            )
    }
}

/// Project actions in the top bar: layout, recompile, export, chat.
struct WorkspaceToolbar: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var ws = ws
        HStack(spacing: 8) {
            ThemedSegmented(options: [(WorkspaceModel.Layout.code, "Code"), (.split, "Split"), (.pdf, "PDF")], selection: $ws.layout)
                .frame(width: 168)
                .help("Layout (⌥⌘1, ⌥⌘2, ⌥⌘3)")
            RecompileButton()
            Menu {
                Button("Project as ZIP…") { ws.exportZip() }
                Button("PDF…") { ws.exportPDF() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .medium))
                    Text("Export").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.textColor)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surfaceColor))
            .help("Export the project (⇧⌘E)")
            IconButton(systemName: "sparkles", help: "Chat with Claude (⌥⌘C)", active: ws.chatVisible) { ws.chatVisible.toggle() }
        }
    }
}

private struct RecompileButton: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let c = ws.compiler
        Button { ws.compile(reason: .manual) } label: {
            HStack(spacing: 6) {
                if c.status == .running {
                    ProgressView().controlSize(.mini).frame(width: 12)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                }
                Text("Recompile").font(.system(size: 13, weight: .medium))
                if !c.errors.isEmpty && c.status != .running {
                    Text("\(c.errors.count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(theme.dangerColor))
                }
            }
            .foregroundStyle(theme.bgColor)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.accentColor.opacity(hovering ? 0.88 : 1)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .help("Recompile (⌘B)")
    }
}
