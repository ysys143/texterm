import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // Retains every open window controller; entries are dropped on window close.
    private var controllers: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let wc = makeWindowController()
        wc.window?.center()
        wc.window?.makeKeyAndOrderFront(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Create + retain a window controller (window is created but not shown).
    @discardableResult
    func makeWindowController() -> TerminalWindowController {
        let wc = TerminalWindowController()
        // Drop our strong ref so the (closed) window deallocates and leaves
        // NSApp.windows -- then the standard applicationShouldTerminateAfterLast-
        // WindowClosed path quits the app. (Calling NSApp.terminate() synchronously
        // from windowWillClose re-enters the close and intermittently deadlocks.)
        wc.onClose = { [weak self] c in
            self?.controllers.removeAll { $0 === c }
        }
        controllers.append(wc)
        return wc
    }

    // MARK: - Actions

    @objc func newTerminalWindow(_ sender: Any?) {
        let wc = makeWindowController()
        if let w = wc.window {
            // Cascade so a new window doesn't land exactly on the previous one.
            if let key = NSApp.keyWindow {
                w.setFrameTopLeftPoint(key.cascadeTopLeft(from: NSPoint(x: key.frame.minX, y: key.frame.maxY)))
            } else {
                w.center()
            }
            w.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let bar = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About texterm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit texterm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Shell menu: window / tab / close
        let shellItem = NSMenuItem()
        bar.addItem(shellItem)
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Window", action: #selector(newTerminalWindow(_:)), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "New Tab",    action: #selector(TerminalWindowController.newWindowForTab(_:)), keyEquivalent: "t")
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Close",      action: #selector(TerminalWindowController.closeCurrentPane(_:)), keyEquivalent: "w")
        shellItem.submenu = shellMenu

        // View menu: splits
        let viewItem = NSMenuItem()
        bar.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Split Right",  action: #selector(TerminalWindowController.splitPaneVertically(_:)),   keyEquivalent: "d")
        let down = NSMenuItem(title: "Split Down", action: #selector(TerminalWindowController.splitPaneHorizontally(_:)), keyEquivalent: "d")
        down.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(down)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Next Pane",     action: #selector(TerminalWindowController.focusNextPane(_:)),     keyEquivalent: "]")
        viewMenu.addItem(withTitle: "Previous Pane", action: #selector(TerminalWindowController.focusPreviousPane(_:)), keyEquivalent: "[")
        viewItem.submenu = viewMenu

        // Window menu: select tab by number (Cmd-1 ... Cmd-9)
        let windowItem = NSMenuItem()
        bar.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        for n in 1...9 {
            let it = NSMenuItem(title: "Select Tab \(n)",
                                action: #selector(TerminalWindowController.selectTabByNumber(_:)),
                                keyEquivalent: "\(n)")
            it.tag = n
            windowMenu.addItem(it)
        }
        windowItem.submenu = windowMenu

        // Edit menu (standard copy/paste key equivalents, dispatched down the chain)
        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy",  action: #selector(NSText.copy(_:)),  keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editItem.submenu = editMenu

        NSApp.mainMenu = bar
    }
}
