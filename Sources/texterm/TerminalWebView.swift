import AppKit
import WebKit

// Hosts xterm.js. xterm.js is a complete VT terminal emulator (the same core
// used by VS Code and Hyper): it handles cursor addressing, line editing,
// scrollback, selection, and IME via its own hidden textarea. We only bridge:
//   - keyboard/paste:  xterm.js onData  -> "pty" message    -> PTY
//   - resize:          xterm.js fit     -> "resize" message -> PTY winsize
//   - output:          PTY bytes        -> writeOutput(base64) -> term.write
class TerminalWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {

    var onInput:  ((String) -> Void)?
    var onResize: ((UInt16, UInt16) -> Void)?

    init(frame: CGRect) {
        let config = WKWebViewConfiguration()
        let ucc = config.userContentController
        // Placeholders replaced with self after super.init (can't pass self yet).
        ucc.add(_Noop(), name: "pty")
        ucc.add(_Noop(), name: "resize")
        ucc.add(_Noop(), name: "openURL")
        super.init(frame: frame, configuration: config)

        ucc.removeScriptMessageHandler(forName: "pty")
        ucc.removeScriptMessageHandler(forName: "resize")
        ucc.removeScriptMessageHandler(forName: "openURL")
        ucc.add(self, name: "pty")
        ucc.add(self, name: "resize")
        ucc.add(self, name: "openURL")

        navigationDelegate = self
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // A fresh WKWebView paints an opaque white (briefly gray) backdrop before
        // the page's first paint, which flashes when a new tab/window opens. Make
        // the WebView itself non-drawing so it's fully transparent during load and
        // the dark pane layer behind it shows through the whole time -- no flash.
        // (underPageBackgroundColor only covers the overscroll area, not this.)
        setValue(false, forKey: "drawsBackground")
        underPageBackgroundColor = NSColor(red: 0x1e/255.0, green: 0x1e/255.0, blue: 0x2e/255.0, alpha: 1)
        loadTerminal()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Page load

    private func loadTerminal() {
        guard let url = Bundle.main.url(forResource: "terminal", withExtension: "html"),
              let resources = Bundle.main.resourceURL
        else {
            loadHTMLString(
                "<body style='background:#1e1e2e;color:#cdd6f4;font-family:monospace'>" +
                "Run <b>make setup &amp;&amp; make run</b> to download assets and build.</body>",
                baseURL: nil
            )
            return
        }
        loadFileURL(url, allowingReadAccessTo: resources)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window?.makeFirstResponder(self)
    }

    // If WebKit's web-content process dies (OOM, a renderer crash), the WebView
    // goes permanently blank. Reload terminal.html so the terminal comes back. The
    // PTY (and shell) live in Swift and keep running, so input/output reconnect to
    // the fresh page automatically -- only the on-screen scrollback is lost.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("texterm: web content process terminated, reloading terminal")
        loadTerminal()
    }

    // MARK: - Output -> xterm.js

    // The userContentController retains its script message handlers strongly, and
    // this view owns that controller -> a retain cycle that keeps the WebView (and
    // its window) alive forever, so closing a window hangs instead of deallocating.
    // Call this before releasing the view to break the cycle and stop the process.
    func teardown() {
        configuration.userContentController.removeAllScriptMessageHandlers()
        navigationDelegate = nil
        stopLoading()
    }

    func writeOutput(_ data: Data) {
        // base64 keeps the byte stream intact across the JS string bridge,
        // avoiding any UTF-8/UTF-16 reinterpretation of control bytes.
        //
        // Pass the (large) payload as an *argument* rather than interpolating it
        // into the script source: evaluateJavaScript("writeOutput('<~85KB>')") makes
        // WebKit parse+compile a fresh multi-KB string literal on every chunk.
        // callAsyncJavaScript compiles the tiny body "writeOutput(b64)" once and
        // binds b64 as a value, so heavy output stops thrashing the JS compiler.
        let b64 = data.base64EncodedString()
        callAsyncJavaScript(
            "writeOutput(b64)",
            arguments: ["b64": b64],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    // MARK: - Messages from JS

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "pty":
            if let text = message.body as? String { onInput?(text) }
        case "resize":
            if let d = message.body as? [String: Any],
               let cols = d["cols"] as? Int, let rows = d["rows"] as? Int {
                onResize?(UInt16(cols), UInt16(rows))
            }
        case "openURL":
            if let s = message.body as? String { openURL(s) }
        default:
            break
        }
    }

    // Open a link clicked in the terminal. Restricted to web/mail schemes so a
    // program's output can't make texterm invoke arbitrary URL handlers.
    private func openURL(_ string: String) {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "mailto"
        else { return }
        NSWorkspace.shared.open(url)
    }
}

private class _Noop: NSObject, WKScriptMessageHandler {
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {}
}
