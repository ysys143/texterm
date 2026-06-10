import AppKit

class TerminalViewController: NSViewController {
    private var termView: TerminalWebView!
    private var pty: PTY!

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 820))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        termView = TerminalWebView(frame: view.bounds)
        termView.autoresizingMask = [.width, .height]
        view.addSubview(termView)

        pty = PTY()
        pty.onOutput = { [weak self] data in self?.termView.writeOutput(data) }
        pty.onExit   = { NSApplication.shared.terminate(nil) }

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
        view.window?.makeFirstResponder(termView)
    }
}
