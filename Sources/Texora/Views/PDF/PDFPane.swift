import SwiftUI
import PDFKit

/// PDFView subclass: ⌘-click jumps to the source line.
final class TexoraPDFView: PDFView {
    var onCommandClick: ((PDFPage, CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let p = convert(event.locationInWindow, from: nil)
            if let page = page(for: p, nearest: true) {
                onCommandClick?(page, convert(p, to: page))
            }
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onMouseUp?()
    }
}

/// Drives the PDF view: reloads without losing your place, highlights SyncTeX hits,
/// and reports text selections for "Ask Claude".
@MainActor
final class PDFController {
    weak var view: TexoraPDFView?
    var onInverseSync: ((Int, CGPoint) -> Void)?
    var onSelection: ((PDFSelectionInfo?) -> Void)?
    private var loadedVersion = -1
    private var loadedURL: URL?
    private var highlightAnnotation: PDFAnnotation?
    private var selectionTask: Task<Void, Never>?
    var accentColor: NSColor = .systemPurple

    func attach(_ v: TexoraPDFView) {
        view = v
        v.onCommandClick = { [weak self] page, point in
            guard let self, let doc = page.document else { return }
            let idx = doc.index(for: page)
            let box = page.bounds(for: .mediaBox)
            self.onInverseSync?(idx, CGPoint(x: point.x - box.minX, y: box.maxY - point.y))
        }
        v.onMouseUp = { [weak self] in self?.reportSelectionSoon() }
        NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: v, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportSelectionSoon() }
        }
    }

    func load(url: URL?, version: Int) {
        guard let v = view else { return }
        guard let url else { v.document = nil; loadedURL = nil; loadedVersion = -1; return }
        guard version != loadedVersion || url != loadedURL else { return }
        guard let doc = PDFDocument(url: url) else { return }
        let hadDoc = v.document != nil
        let dest = v.currentDestination
        let oldIndex = dest?.page.flatMap { v.document?.index(for: $0) }
        let scale = v.scaleFactor
        let autoScales = v.autoScales
        v.document = doc
        loadedURL = url
        loadedVersion = version
        highlightAnnotation = nil
        if hadDoc {
            if !autoScales { v.scaleFactor = scale } else { v.autoScales = true }
            if let idx = oldIndex, idx < doc.pageCount, let page = doc.page(at: idx), let p = dest?.point {
                v.go(to: PDFDestination(page: page, at: p))
            }
        } else {
            v.autoScales = true
        }
    }

    /// Scrolls to and briefly highlights a rect given in top-left page coordinates.
    func highlight(page index: Int, rect: CGRect) {
        guard let v = view, let doc = v.document, let page = doc.page(at: index) else { return }
        let box = page.bounds(for: .mediaBox)
        let r = CGRect(x: box.minX + rect.minX - 3, y: box.maxY - rect.maxY - 2, width: max(rect.width, 30) + 6, height: rect.height + 4)
        if let old = highlightAnnotation { old.page?.removeAnnotation(old) }
        let ann = PDFAnnotation(bounds: r, forType: .highlight, withProperties: nil)
        ann.color = accentColor.withAlphaComponent(0.35)
        page.addAnnotation(ann)
        highlightAnnotation = ann
        v.go(to: r.insetBy(dx: 0, dy: -120), on: page)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.highlightAnnotation === ann else { return }
            ann.page?.removeAnnotation(ann)
            self.highlightAnnotation = nil
        }
    }

    func zoom(_ delta: Int) {
        guard let v = view else { return }
        if delta == 0 { v.autoScales = true; return }
        v.autoScales = false
        v.scaleFactor = max(0.25, min(5, v.scaleFactor * (delta > 0 ? 1.15 : 1 / 1.15)))
    }

    private func reportSelectionSoon() {
        selectionTask?.cancel()
        selectionTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reportSelection()
        }
    }

    private func reportSelection() {
        guard let v = view, let sel = v.currentSelection, let text = sel.string,
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              let page = sel.pages.first, let doc = v.document else {
            onSelection?(nil)
            return
        }
        let bounds = sel.bounds(for: page)
        let inView = v.convert(bounds, from: page)
        let topLeft = CGRect(x: inView.minX, y: v.bounds.height - inView.maxY, width: inView.width, height: inView.height)
        let firstLine = sel.selectionsByLine().first?.bounds(for: page) ?? bounds
        let box = page.bounds(for: .mediaBox)
        let point = CGPoint(x: firstLine.minX - box.minX + 2, y: box.maxY - firstLine.midY)
        onSelection?(PDFSelectionInfo(text: text, page: doc.index(for: page), rectInView: topLeft, pagePoint: point))
    }

    func clearSelection() {
        view?.clearSelection()
        onSelection?(nil)
    }
}

struct PDFKitView: NSViewRepresentable {
    let controller: PDFController
    var background: NSColor
    var darkMode: Bool

    func makeNSView(context: Context) -> TexoraPDFView {
        let v = TexoraPDFView()
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.displaysPageBreaks = true
        v.pageBreakMargins = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        v.autoScales = true
        v.backgroundColor = background
        v.pageShadowsEnabled = true
        controller.attach(v)
        return v
    }

    func updateNSView(_ v: TexoraPDFView, context: Context) {
        v.backgroundColor = background
        applyDarkMode(v)
    }

    private func applyDarkMode(_ v: TexoraPDFView) {
        guard let doc = v.documentView else { return }
        doc.wantsLayer = true
        if darkMode {
            let invert = CIFilter(name: "CIColorInvert")!
            let hue = CIFilter(name: "CIHueAdjust")!
            hue.setValue(Float.pi, forKey: kCIInputAngleKey)
            doc.contentFilters = [invert, hue]
        } else if !doc.contentFilters.isEmpty {
            doc.contentFilters = []
        }
    }
}

struct PDFPane: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        let compiler = ws.compiler
        ZStack(alignment: .topLeading) {
            PDFKitView(controller: ws.pdf, background: NSColor(hex: theme.sidebar), darkMode: settings.pdfDarkMode && theme.isDark)
                .onAppear { ws.pdf.load(url: compiler.pdfURL, version: compiler.pdfVersion) }
                .onChange(of: compiler.pdfVersion) { ws.pdf.load(url: compiler.pdfURL, version: compiler.pdfVersion) }
                .onChange(of: theme.accent) { ws.pdf.accentColor = NSColor(hex: theme.accent) }

            if compiler.pdfURL == nil {
                PDFEmptyState()
            }

            if let sel = ws.pdfSelection, ws.ask == nil {
                AskPill { ws.askFromPDF(sel) }
                    .debugOverlay("pdfPill")
                    .position(x: min(max(sel.rectInView.midX, 90), 2000), y: sel.rectInView.maxY + 22)
                    .transition(.opacity)
            }

            if let ask = ws.ask, ask.source == .pdf {
                AskClaudeOverlay(request: ask)
            }
        }
        .overlay(alignment: .bottomTrailing) { PDFControls() }
        .overlay(alignment: .top) { CompileBanner() }
        .background(theme.sidebarColor)
        .clipped()
    }
}

private struct PDFEmptyState: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(theme.mutedColor)
            if ws.compiler.status == .running {
                Text("Compiling…").font(.system(size: 13)).foregroundStyle(theme.secondaryColor)
            } else if ws.compiler.status == .unavailable {
                Text(ws.compiler.detail ?? "No LaTeX engine found.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else if ws.compiler.status == .failed {
                Text("The document has errors, so there's no PDF yet.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryColor)
                HStack(spacing: 8) {
                    PillButton(title: "Show issues", systemImage: "exclamationmark.triangle") { ws.issuesVisible = true }
                    PillButton(title: "Fix with Claude", systemImage: "sparkles", prominent: true) {
                        ws.chatVisible = true
                        ws.chat.send(text: ws.fixErrorsPrompt())
                    }
                }
            } else {
                Text("The PDF appears here after you compile.")
                    .font(.system(size: 13)).foregroundStyle(theme.secondaryColor)
                PillButton(title: "Recompile", systemImage: "arrow.clockwise") { ws.compile(reason: .manual) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PDFControls: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        if ws.compiler.pdfURL != nil {
            HStack(spacing: 0) {
                IconButton(systemName: "minus.magnifyingglass", help: "Zoom out", size: 12) { ws.pdf.zoom(-1) }
                IconButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Fit width", size: 11) { ws.pdf.zoom(0) }
                IconButton(systemName: "plus.magnifyingglass", help: "Zoom in", size: 12) { ws.pdf.zoom(1) }
            }
            .padding(3)
            .background(Capsule().fill(theme.elevatedColor.opacity(0.95)))
            .overlay(Capsule().stroke(theme.borderColor, lineWidth: 1))
            .padding(14)
        }
    }
}

/// Thin status line over the PDF while compiling or when the build failed.
struct CompileBanner: View {
    @Environment(WorkspaceModel.self) private var ws
    @Environment(\.theme) private var theme

    var body: some View {
        let c = ws.compiler
        Group {
            if c.status == .running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(c.detail ?? "Compiling…").font(.system(size: 12))
                }
                .foregroundStyle(theme.secondaryColor)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(theme.elevatedColor))
                .overlay(Capsule().stroke(theme.borderColor, lineWidth: 1))
                .padding(.top, 10)
                .transition(.opacity)
            } else if c.status == .failed, c.pdfURL != nil {
                Button { ws.issuesVisible = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                        Text("\(c.errors.count) error\(c.errors.count == 1 ? "" : "s") · showing the last good PDF")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(theme.dangerColor)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(theme.elevatedColor))
                    .overlay(Capsule().stroke(theme.dangerColor.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .animation(.easeOut(duration: 0.15), value: c.status)
    }
}
