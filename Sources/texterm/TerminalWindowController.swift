import AppKit

// Owns one window and the tree of terminal panes inside it. Leaves are
// TerminalViewControllers (one WebView + one PTY each); internal nodes are
// NSSplitViews. Handles split, close-pane, and tab creation. New top-level
// windows are made by AppDelegate (which retains every controller).
final class TerminalWindowController: NSWindowController, NSWindowDelegate {

    private var panes: [TerminalViewController] = []
    private weak var lastActive: TerminalViewController?
    var onClose: ((TerminalWindowController) -> Void)?

    convenience init() {
        // No .fullSizeContentView: the content view sits *below* the titlebar, so
        // AppKit shrinks it automatically when the native tab bar appears -- the
        // terminal never overlaps the tabs/titlebar (no fixed top-padding hack).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "texterm"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x1e/255.0, green: 0x1e/255.0, blue: 0x2e/255.0, alpha: 1)
        // Same identifier -> windows can be merged into native tabs; preferred ->
        // Cmd-T / the "+" button create tabs rather than separate windows.
        window.tabbingIdentifier = "texterm"
        window.tabbingMode = .preferred
        self.init(window: window)
        window.delegate = self

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 820))
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        let first = makePane()
        place(first.view, filling: root)
        panes = [first]
        lastActive = first
    }

    // MARK: - Panes

    private func makePane() -> TerminalViewController {
        let vc = TerminalViewController()
        _ = vc.view                       // force loadView -> viewDidLoad -> PTY start
        vc.onShellExit = { [weak self, weak vc] in
            guard let self = self, let vc = vc else { return }
            DispatchQueue.main.async { self.closePane(vc) }
        }
        return vc
    }

    private func place(_ v: NSView, filling parent: NSView) {
        v.frame = parent.bounds
        v.autoresizingMask = [.width, .height]
        parent.addSubview(v)
    }

    // The pane that owns the current first responder (walk up from it to a
    // TerminalWebView), falling back to the last one we focused.
    private func activePane() -> TerminalViewController? {
        var node = window?.firstResponder as? NSView
        while let n = node {
            if let web = n as? TerminalWebView,
               let vc = panes.first(where: { $0.termView === web }) {
                lastActive = vc
                return vc
            }
            node = n.superview
        }
        return lastActive ?? panes.first
    }

    private func focus(_ vc: TerminalViewController) {
        lastActive = vc
        window?.makeFirstResponder(vc.termView)
    }

    // MARK: - Split  (Cmd-D: side by side, Cmd-Shift-D: top/bottom — iTerm2 layout)

    @objc func splitPaneVertically(_ sender: Any?)   { split(sideBySide: true) }
    @objc func splitPaneHorizontally(_ sender: Any?) { split(sideBySide: false) }

    private func split(sideBySide: Bool) {
        guard let active = activePane(), let parent = active.view.superview else { return }
        let activeView = active.view
        let newPane = makePane()

        let sv = NSSplitView(frame: activeView.frame)
        sv.isVertical = sideBySide        // vertical divider => panes left/right
        sv.dividerStyle = .thin

        // Insert the split where the active view currently sits, then move the
        // active view + the new pane into it.
        if let parentSplit = parent as? NSSplitView {
            let idx = parentSplit.arrangedSubviews.firstIndex(of: activeView) ?? 0
            activeView.removeFromSuperview()
            parentSplit.insertArrangedSubview(sv, at: idx)
        } else {
            activeView.removeFromSuperview()
            place(sv, filling: parent)
        }
        sv.addArrangedSubview(activeView)
        sv.addArrangedSubview(newPane.view)

        panes.append(newPane)
        // Equalize once the split has a size.
        DispatchQueue.main.async {
            let total = sideBySide ? sv.bounds.width : sv.bounds.height
            if total > 0 { sv.setPosition(total / 2, ofDividerAt: 0) }
            self.focus(newPane)
        }
    }

    // MARK: - Close pane  (Cmd-W)

    @objc func closeCurrentPane(_ sender: Any?) {
        guard let active = activePane() else { window?.performClose(sender); return }
        closePane(active)
    }

    private func closePane(_ vc: TerminalViewController) {
        guard let idx = panes.firstIndex(where: { $0 === vc }) else { return }
        guard let parent = vc.view.superview as? NSSplitView else {
            // Root pane -> nothing to collapse; close the window/tab.
            window?.performClose(nil)
            return
        }
        vc.shutdown()
        vc.view.removeFromSuperview()
        panes.remove(at: idx)
        if lastActive === vc { lastActive = nil }

        // A split with one child left is pointless -> hoist the survivor up.
        if split(parent, hasArrangedCount: 1), let survivor = parent.arrangedSubviews.first {
            survivor.removeFromSuperview()
            if let grandparent = parent.superview as? NSSplitView {
                let i = grandparent.arrangedSubviews.firstIndex(of: parent) ?? 0
                parent.removeFromSuperview()
                grandparent.insertArrangedSubview(survivor, at: i)
            } else if let grandparent = parent.superview {
                parent.removeFromSuperview()
                place(survivor, filling: grandparent)
            }
        }
        if let next = panes.first { focus(next) }
    }

    private func split(_ sv: NSSplitView, hasArrangedCount n: Int) -> Bool {
        sv.arrangedSubviews.count == n
    }

    // MARK: - Tabs  (Cmd-T / native "+" button)

    @objc override func newWindowForTab(_ sender: Any?) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        let wc = app.makeWindowController()
        if let newWindow = wc.window {
            window?.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
            updateTabShortcutLabels()
        }
    }

    // Show "Cmd-1 / Cmd-2 ..." on each tab -- its position is the Cmd-N that
    // selects it. Refreshed whenever the tab set or order changes.
    private func updateTabShortcutLabels() {
        guard let windows = window?.tabGroup?.windows else { return }
        for (i, w) in windows.enumerated() {
            if i < 9 {
                let label = NSTextField(labelWithString: "\u{2318}\(i + 1)")
                label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                label.textColor = .secondaryLabelColor
                label.sizeToFit()
                w.tab.accessoryView = label
            } else {
                w.tab.accessoryView = nil
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateTabShortcutLabels()
    }

    // MARK: - Focus navigation

    // Cmd-] / Cmd-[ : cycle split panes within this window (tab).
    @objc func focusNextPane(_ sender: Any?)     { cyclePane(+1) }
    @objc func focusPreviousPane(_ sender: Any?) { cyclePane(-1) }

    private func cyclePane(_ delta: Int) {
        guard panes.count > 1 else { return }
        let idx = activePane().flatMap { a in panes.firstIndex(where: { $0 === a }) } ?? 0
        focus(panes[(idx + delta + panes.count) % panes.count])
    }

    // Cmd-1 ... Cmd-9 : select the Nth tab (menu item tag is the 1-based number).
    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        guard let group = window?.tabGroup else { return }
        let n = sender.tag
        guard n >= 1, n <= group.windows.count else { return }
        let target = group.windows[n - 1]
        group.selectedWindow = target
        target.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window lifecycle

    func windowWillClose(_ notification: Notification) {
        panes.forEach { $0.shutdown() }   // break WebView cycles
        panes.removeAll()                 // release VCs -> PTY deinit kills shells
        // Synchronous: the main queue stops being serviced once the last window
        // closes (app enters its terminate sequence), so a deferred block would
        // never run. The window survives this call (NSApp retains it through close).
        onClose?(self)
    }
}
