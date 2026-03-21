import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    /// All tab managers (one per window).
    private(set) var tabManagers: [TabManager] = []

    /// The tab manager for the currently focused window.
    var focusedTabManager: TabManager? {
        guard let keyWindow = NSApp.keyWindow else { return tabManagers.first }
        return tabManagers.first { $0.window === keyWindow }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Force Ghostty initialization
        _ = GhosttyManager.shared

        createNewWindow()

        // Build main menu
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // App termination is gated by applicationShouldTerminate (quit confirmation dialog).
        true
    }

    // MARK: - Window management

    func createNewWindow() {
        let tabManager = TabManager()
        tabManagers.append(tabManager)

        let contentView = ContentView(tabManager: tabManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.title = "ghast"
        window.backgroundColor = GhosttyManager.shared.backgroundColor
        window.isOpaque = GhosttyManager.shared.backgroundOpacity >= 1.0
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.zoom(nil)

        tabManager.window = window
    }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ghast", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ghast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu (splits)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Split Right", action: #selector(splitRight(_:)), keyEquivalent: "d")
        viewMenu.addItem(withTitle: "Split Down", action: #selector(splitDown(_:)), keyEquivalent: "d")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Next Pane", action: #selector(nextPane(_:)), keyEquivalent: "]")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(withTitle: "Previous Pane", action: #selector(previousPane(_:)), keyEquivalent: "[")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Next Tab", action: #selector(nextTab(_:)), keyEquivalent: "}")
        windowMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(withTitle: "Previous Tab", action: #selector(previousTab(_:)), keyEquivalent: "{")
        windowMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(.separator())
        for i in 1...9 {
            windowMenu.addItem(withTitle: "Tab \(i)", action: #selector(selectTabByNumber(_:)), keyEquivalent: "\(i)")
            windowMenu.items.last?.tag = i
        }
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Edit menu (for Copy/Paste to work)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }

    // MARK: - Menu actions

    @objc private func newWindow(_ sender: Any?) {
        createNewWindow()
    }

    @objc private func newTab(_ sender: Any?) {
        focusedTabManager?.createTab()
    }

    @objc private func closeTab(_ sender: Any?) {
        guard let mgr = focusedTabManager, let tab = mgr.selectedTab else { return }
        mgr.closeTab(tab.id)
    }

    @objc private func nextTab(_ sender: Any?) {
        focusedTabManager?.selectNextTab()
    }

    @objc private func previousTab(_ sender: Any?) {
        focusedTabManager?.selectPreviousTab()
    }

    @objc private func splitRight(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let tab = ws.selectedTab else { return }
        ws.createSplitTab(nextTo: tab.id, direction: .horizontal)
    }

    @objc private func splitDown(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let tab = ws.selectedTab else { return }
        ws.createSplitTab(nextTo: tab.id, direction: .vertical)
    }

    @objc private func nextPane(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let layout = ws.splitLayout else { return }
        let tabIds = layout.allTabIds
        guard tabIds.count > 1, let currentId = ws.selectedTabId,
              let index = tabIds.firstIndex(of: currentId) else { return }
        let nextId = tabIds[(index + 1) % tabIds.count]
        ws.selectedTabId = nextId
        if let tab = ws.tabs.first(where: { $0.id == nextId }) {
            tab.focus()
        }
    }

    @objc private func previousPane(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let layout = ws.splitLayout else { return }
        let tabIds = layout.allTabIds
        guard tabIds.count > 1, let currentId = ws.selectedTabId,
              let index = tabIds.firstIndex(of: currentId) else { return }
        let prevId = tabIds[(index - 1 + tabIds.count) % tabIds.count]
        ws.selectedTabId = prevId
        if let tab = ws.tabs.first(where: { $0.id == prevId }) {
            tab.focus()
        }
    }

    @objc private func selectTabByNumber(_ sender: NSMenuItem) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace else { return }
        let index = sender.tag - 1
        if sender.tag == 9 {
            // Cmd+9 = last tab
            if let last = ws.tabs.last { ws.selectTab(last.id) }
        } else if index >= 0, index < ws.tabs.count {
            ws.selectTab(ws.tabs[index].id)
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let mgr = tabManagers.first(where: { $0.window === sender }),
              !mgr.tabs.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = "Close Window?"
        alert.informativeText = "All terminal sessions in this window will be terminated."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: sender) { response in
            if response == .alertFirstButtonReturn {
                // User confirmed — allow the close
                self.tabManagers.removeAll { $0.window === sender }
                sender.close()
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        tabManagers.removeAll { $0.window === window }
    }
}

// MARK: - App termination confirmation

extension AppDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let activeSessions = tabManagers.reduce(0) { $0 + $1.tabs.count }
        guard activeSessions > 0 else { return .terminateNow }

        guard let window = NSApp.keyWindow ?? tabManagers.first?.window else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit ghast?"
        alert.informativeText = activeSessions == 1
            ? "1 terminal session will be terminated."
            : "\(activeSessions) terminal sessions will be terminated."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { response in
            NSApp.reply(toApplicationShouldTerminate: response == .alertFirstButtonReturn)
        }
        return .terminateLater
    }
}
