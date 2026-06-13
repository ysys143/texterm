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

    // MARK: - Output -> xterm.js

    func writeOutput(_ data: Data) {
        // base64 keeps the byte stream intact across the JS string bridge,
        // avoiding any UTF-8/UTF-16 reinterpretation of control bytes.
        let b64 = data.base64EncodedString()
        evaluateJavaScript("writeOutput('\(b64)')", completionHandler: nil)
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
