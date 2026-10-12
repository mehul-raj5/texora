import AppKit
import WebKit

/// Swift side of the CodeMirror editor. Owns one WKWebView per workspace (kept alive while the
/// workspace is open, so each file's undo history survives layout changes).
@MainActor
final class EditorBridge: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var isReady = false
    private var pending: [String] = []
    var onMessage: (([String: Any]) -> Void)?

    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var bridge: EditorBridge?
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            MainActor.assumeIsolated { bridge?.onMessage?(body) }
        }
    }

    override init() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let handler = WeakHandler()
        controller.add(handler, name: "texora")
        config.userContentController = controller
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        handler.bridge = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        if ProcessInfo.processInfo.arguments.contains("--automation") { webView.isInspectable = true }
        let index = Paths.editorDir.appendingPathComponent("index.html")
        webView.loadFileURL(index, allowingReadAccessTo: Paths.editorDir)
    }

    func markReady() {
        isReady = true
        let queued = pending
        pending.removeAll()
        for js in queued { webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    // Block navigations away from the editor page (e.g. a file dropped onto the web view).
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .other, action.request.url?.lastPathComponent == "index.html" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The page posts "ready" after init; init is requested by the workspace.
        onMessage?(["type": "loaded"])
    }

    // MARK: Calls

    func call(_ function: String, _ args: [Any?]) {
        let normalized: [Any] = args.map { $0 ?? NSNull() }
        guard let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.texora && window.texora.\(function).apply(window.texora, \(json));"
        if isReady || function == "init" {
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            pending.append(js)
        }
    }

    func evaluate(_ js: String) async -> Any? {
        guard isReady else { return nil }
        return try? await webView.evaluateJavaScript(js)
    }

    func initialize(theme: Theme, fontSize: Double, wrap: Bool, vim: Bool) {
        call("init", [["fontSize": fontSize, "wrap": wrap, "vim": vim, "dark": theme.isDark]])
        setTheme(theme)
    }

    func open(path: String, text: String?, line: Int? = nil) { call("open", [path, text, line]) }
    func setText(path: String, text: String, flash: Bool) { call("setText", [path, text, flash]) }
    func close(path: String) { call("close", [path]) }
    func rename(from: String, to: String) { call("rename", [from, to]) }
    func reveal(from: Int, to: Int? = nil, select: Bool = false) { call("reveal", [from, to ?? from, select]) }
    func flash(from: Int, to: Int) { call("flash", [from, to]) }
    func setTheme(_ theme: Theme) { call("setTheme", [theme.cssVariables, theme.isDark]) }
    func setOptions(_ opts: [String: Any]) { call("setOptions", [opts]) }
    func setCompletions(_ data: [String: Any]) { call("setCompletions", [data]) }
    func setDiagnostics(path: String, _ diags: [[String: Any]]) { call("setDiagnostics", [path, diags]) }
    func setReadOnly(_ ro: Bool) { call("setReadOnly", [ro]) }
    func insert(_ text: String) { call("insert", [text]) }
    func focus() { call("focus", []) }
    func hidePill() { call("hidePill", []) }

    /// Returns {path: text} for every document edited since the last collect.
    func collect() async -> [String: String] {
        (await evaluate("window.texora.collect()") as? [String: String]) ?? [:]
    }

    func selection() async -> [String: Any]? {
        await evaluate("window.texora.selection()") as? [String: Any]
    }
}
