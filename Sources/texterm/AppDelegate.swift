import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "texterm"
        window.titlebarAppearsTransparent = true
        // Force dark chrome so the title text + traffic lights stay readable on
        // the dark terminal background (otherwise light-mode title text is dark-on-dark).
        window.appearance = NSAppearance(named: .darkAqua)
        // Match the xterm.js theme background (#1e1e2e) instead of pure black.
        window.backgroundColor = NSColor(red: 0x1e/255.0, green: 0x1e/255.0, blue: 0x2e/255.0, alpha: 1)
        window.center()
        window.setFrameAutosaveName("MainWindow")

        let vc = TerminalViewController()
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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

        // Edit menu (enables standard copy/paste key equivalents)
        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        // nil target -> dispatched down the responder chain. paste: is implemented
        // by KeyCaptureView; copy: falls through to the focused web selection.
        editMenu.addItem(withTitle: "Copy",  action: #selector(NSText.copy(_:)),  keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editItem.submenu = editMenu

        NSApp.mainMenu = bar
    }
}
