import AppKit
import WebKit
import PDFKit
import SwiftUI

/// Developer-only remote control used for end-to-end testing. It's active only when the app
/// is launched with `--automation`. Commands arrive as distributed notifications named
/// `app.texora.debug` with a userInfo dictionary: {"cmd": "...", "arg": "...", "arg2": "..."}.
@MainActor
final class DebugAutomation {
    static var shared: DebugAutomation?
    /// Global frames of floating SwiftUI overlays, so snapshots can paint them above web content.
    static var overlayFrames: [String: CGRect] = [:]
    static var openSettings: (() -> Void)?
    private weak var model: AppModel?
    private var observer: NSObjectProtocol?

    static func startIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.arguments.contains("--automation"), shared == nil else { return }
        let a = DebugAutomation()
        a.model = model
        a.observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.texora.debug"), object: nil, queue: .main
        ) { note in
            let info = note.userInfo as? [String: Any] ?? [:]
            MainActor.assumeIsolated { a.handle(info) }
        }
        shared = a
        NSLog("Texora automation enabled")
    }

    private func handle(_ info: [String: Any]) {
        guard let model else { return }
        let cmd = info["cmd"] as? String ?? ""
        let arg = info["arg"] as? String ?? ""
        let arg2 = info["arg2"] as? String ?? ""
        switch cmd {
        case "snapshot":
            Task { await Self.snapshot(to: URL(fileURLWithPath: arg)) }
        case "open":
            model.handleOpen(url: URL(fileURLWithPath: arg))
        case "openProject":
            if let p = model.library.projects.first(where: { $0.name == arg || $0.path == arg }) { model.openProject(p.id) }
        case "route":
            if arg == "home" { model.goHome() } else if arg == "projects" { model.route = .projects }
        case "theme":
            if let t = Themes.byID(arg) { model.themes.mode = .fixed; model.themes.fixedThemeID = t.id }
        case "themeMode":
            model.themes.mode = arg == "auto" ? .auto : .fixed
        case "newProject":
            model.showNewProject = true
        case "createProject":
            if let t = ProjectTemplate.loadAll().first(where: { $0.id == arg2 }) ?? ProjectTemplate.loadAll().first {
                model.createProject(name: arg, template: t, prompt: info["prompt"] as? String)
            }
        case "showSettings":
            Self.openSettings?()
        case "closeWindows":
            for w in NSApp.windows where w.isVisible && w.title != "Texora" && !(w.className.contains("Popover")) { w.close() }
        case "model":
            model.settings.claudeModel = ClaudeModel(rawValue: arg) ?? .auto
        case "sidebar":
            model.sidebarVisible = arg != "hide"
        case "quit":
            NSApp.terminate(nil)
        default:
            model.workspace?.handleAutomation(cmd: cmd, arg: arg, arg2: arg2, info: info)
        }
    }

    /// Renders the main window, including web and PDF content, into a PNG. Sheets and popovers
    /// are written next to it as <name>-sheet.png / <name>-popover.png.
    static func snapshot(to url: URL) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) && $0.className != "_NSPopoverWindow" }) else { return }
        await render(window, to: url)
        let base = url.deletingPathExtension().path
        if let sheet = window.attachedSheet { await render(sheet, to: URL(fileURLWithPath: base + "-sheet.png")) }
        var n = 0
        for w in NSApp.windows where w.isVisible && w !== window && w !== window.attachedSheet && w.contentView != nil {
            n += 1
            await render(w, to: URL(fileURLWithPath: base + (w.className.contains("Popover") ? "-popover.png" : "-win\(n).png")))
        }
    }

    private static func render(_ window: NSWindow, to url: URL) async {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)

        // Web views render out of process, so paint their snapshots on top.
        var overlays: [(NSImage, NSRect)] = []
        for web in allSubviews(of: view).compactMap({ $0 as? WKWebView }) where !web.isHiddenOrHasHiddenAncestor {
            if let snap = try? await web.takeSnapshot(configuration: nil) {
                let r = web.convert(web.bounds, to: view)
                overlays.append((snap, r))
            }
        }
        // PDFKit draws pages in tiles that cacheDisplay misses; render them through a PDF context.
        for pdfView in allSubviews(of: view).compactMap({ $0 as? PDFView }) where !pdfView.isHiddenOrHasHiddenAncestor && pdfView.document != nil {
            let data = pdfView.dataWithPDF(inside: pdfView.bounds)
            if let img = NSImage(data: data) {
                overlays.append((img, pdfView.convert(pdfView.bounds, to: view)))
            }
        }
        let final = NSImage(size: bounds.size)
        final.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: bounds.size))
        for (img, r) in overlays {
            let flipped = view.isFlipped ? NSRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height) : r
            img.draw(in: flipped)
        }
        // Floating SwiftUI overlays (Ask popup, pills) sit above the web views: repaint them from the cached render.
        for (_, f) in overlayFrames where f.width > 0 && f.height > 0 {
            let r = NSRect(x: f.minX, y: bounds.height - f.maxY, width: f.width, height: f.height)
            image.draw(in: r, from: r, operation: .sourceOver, fraction: 1)
        }
        final.unlockFocus()
        if let tiff = final.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private static func allSubviews(of v: NSView) -> [NSView] {
        v.subviews + v.subviews.flatMap { allSubviews(of: $0) }
    }
}


private struct DebugOverlayFrame: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        if DebugAutomation.shared == nil {
            content
        } else {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { DebugAutomation.overlayFrames[key] = $0 }
                .onDisappear { DebugAutomation.overlayFrames[key] = nil }
        }
    }
}

extension View {
    /// Records this overlay's frame for automation snapshots (no-op unless launched with --automation).
    func debugOverlay(_ key: String) -> some View { modifier(DebugOverlayFrame(key: key)) }
}
