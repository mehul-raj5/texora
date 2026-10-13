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

    /// Both panes stay alive in every layout; only their widths change. Recreating them on each
    /// switch left the PDF view empty and could detach the editor's web view (black panes).
    private var center: some View {
        @Bindable var ws = ws
        return GeometryReader { geo in
            let w = geo.size.width
            let editorW: CGFloat = {
                switch ws.layout {
                case .code: return w
                case .pdf: return 0
                case .split: return max(260, min(w - 260 - DragHandle.width, w * ws.splitFraction))
                }
            }()
            let pdfW = ws.layout == .split ? max(0, w - editorW - DragHandle.width) : (ws.layout == .pdf ? w : 0)
            HStack(spacing: 0) {
                EditorPane()
                    .frame(width: editorW)
                    .opacity(editorW > 0 ? 1 : 0)
                    .allowsHitTesting(editorW > 0)
                    .clipped()
                if ws.layout == .split {
                    SplitHandle(fraction: $ws.splitFraction, totalWidth: w)
                }
                PDFPane()
                    .frame(width: pdfW)
                    .opacity(pdfW > 0 ? 1 : 0)
                    .allowsHitTesting(pdfW > 0)
                    .clipped()
            }
        }
    }
}

/// A real (not overlaid) drag handle, so web/PDF views beside it can't swallow the clicks.
/// Drags are measured in global coordinates, which stay stable while the handle itself moves.
struct DragHandle: View {
    @Environment(\.theme) private var theme
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void = {}
    @State private var hovering = false
    @State private var dragging = false
    static let width: CGFloat = 10

    var body: some View {
        ZStack {
            Rectangle().fill(theme.bgColor)
            Rectangle().fill(theme.borderColor).frame(width: 1)
            Capsule()
                .fill(dragging ? theme.accentColor : theme.mutedColor.opacity(0.8))
                .frame(width: 4, height: 36)
                .opacity(hovering || dragging ? 1 : 0)
        }
        .frame(width: Self.width)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    if !dragging { dragging = true; onBegan() }
                    onChanged(v.translation.width)
                }
                .onEnded { _ in dragging = false; onEnded() }
        )
    }
}

/// Divider between the editor and the PDF.
struct SplitHandle: View {
    @Binding var fraction: CGFloat
    let totalWidth: CGFloat
    @State private var start: CGFloat = 0.5

    var body: some View {
        DragHandle(onBegan: { start = fraction }, onChanged: { dx in
            fraction = min(0.8, max(0.2, start + dx / max(totalWidth, 1)))
        })
        .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { fraction = 0.5 } }
        .help("Drag to resize · double-click to reset")
    }
}

/// Divider that resizes a side panel (e.g. the chat).
struct ResizeHandle: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var invert = false
    @State private var start: CGFloat = 0

    var body: some View {
        DragHandle(onBegan: { start = value }, onChanged: { dx in
            value = min(range.upperBound, max(range.lowerBound, start + (invert ? -dx : dx)))
        })
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
                .frame(width: 176)
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
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.surfaceColor))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).stroke(theme.borderColor, lineWidth: 1))
            .help("Export the project (⇧⌘E)")
            IconButton(systemName: "sparkles", help: "Chat with Claude (⌘L)", active: ws.chatVisible) { ws.chatVisible.toggle() }
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
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.accentColor.opacity(hovering ? 0.88 : 1)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .help("Save and recompile (⌘S)")
    }
}
