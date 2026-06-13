import AppKit

class TerminalViewController: NSViewController {
    private(set) var termView: TerminalWebView!
    private var pty: PTY!

    /// Called when this pane's shell exits, so the container can close just this
    /// pane (split or tab) instead of terminating the whole app.
    var onShellExit: (() -> Void)?

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 820))
        v.wantsLayer = true
        // Match the terminal background (not black) so the pane shows no flash
        // behind the WebView while terminal.html loads.
        v.layer?.backgroundColor = NSColor(red: 0x1e/255.0, green: 0x1e/255.0, blue: 0x2e/255.0, alpha: 1).cgColor
        self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        termView = TerminalWebView(frame: view.bounds)
        termView.autoresizingMask = [.width, .height]
        view.addSubview(termView)

        pty = PTY()
        pty.onOutput = { [weak self] data in self?.termView.writeOutput(data) }
        pty.onExit   = { [weak self] in self?.onShellExit?() }

        // xterm.js computes cols/rows from its own layout (fit addon) and reports
        // them here, so the PTY winsize always matches what the user sees.
        termView.onInput  = { [weak self] text in self?.pty.write(text) }
        termView.onResize = { [weak self] cols, rows in self?.pty.resize(cols: cols, rows: rows) }

        do {
            try pty.start()
        } catch {
            NSLog("texterm: PTY start failed - %@", error.localizedDescription)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focus()
    }

    func focus() {
        view.window?.makeFirstResponder(termView)
    }

    /// Break the WebView retain cycle and stop the PTY (off the main thread) so this
    /// pane and its window can close without blocking.
    func shutdown() {
        termView.teardown()
        pty.stop()
    }
}
