import AppKit
import Foundation

/// Callback context attached to each Ghostty surface. Passed through C callbacks
/// as an opaque `void*` so we can route events back to the correct Swift objects.
final class SurfaceCallbackContext {
    weak var view: TerminalView?
    let surfaceId: UUID
    let tabId: UUID

    var surface: ghostty_surface_t? { view?.surface }

    init(view: TerminalView, surfaceId: UUID, tabId: UUID) {
        self.view = view
        self.surfaceId = surfaceId
        self.tabId = tabId
    }
}

/// Singleton managing the Ghostty library lifecycle.
/// Initializes libghostty, creates the app-level handle, and provides runtime callbacks.
@MainActor
final class GhosttyManager {
    static let shared = GhosttyManager()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    /// Terminal background color read from Ghostty config.
    private(set) var backgroundColor: NSColor = .black
    private(set) var backgroundOpacity: Double = 1.0

    private init() {
        initialize()
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Initialization

    private func initialize() {
        // Remove NO_COLOR if present
        if getenv("NO_COLOR") != nil { unsetenv("NO_COLOR") }

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            print("Failed to initialize ghostty: \(result)")
            return
        }

        guard let cfg = ghostty_config_new() else {
            print("Failed to create ghostty config")
            return
        }

        ghostty_config_load_default_files(cfg)
        ghostty_config_load_recursive_files(cfg)
        ghostty_config_finalize(cfg)

        var rt = ghostty_runtime_config_s()
        rt.userdata = nil
        rt.supports_selection_clipboard = true
        rt.wakeup_cb = { _ in
            DispatchQueue.main.async { GhosttyManager.shared.tick() }
        }
        rt.action_cb = { app, target, action in
            return GhosttyManager.shared.handleAction(target: target, action: action)
        }
        rt.read_clipboard_cb = { userdata, location, state in
            GhosttyManager.readClipboard(userdata: userdata, location: location, state: state)
        }
        rt.confirm_read_clipboard_cb = { userdata, content, state, _ in
            guard let content, let userdata else { return }
            let ctx = Unmanaged<SurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = ctx.surface else { return }
            ghostty_surface_complete_clipboard_request(surface, content, state, true)
        }
        rt.write_clipboard_cb = { _, location, content, len, _ in
            GhosttyManager.writeClipboard(location: location, content: content, len: len)
        }
        rt.close_surface_cb = { userdata, _ in
            GhosttyManager.closeSurface(userdata: userdata)
        }

        if let created = ghostty_app_new(&rt, cfg) {
            self.app = created
            self.config = cfg
        } else {
            // Fallback: try with empty config
            ghostty_config_free(cfg)
            guard let fallback = ghostty_config_new() else { return }
            ghostty_config_finalize(fallback)
            guard let created = ghostty_app_new(&rt, fallback) else {
                ghostty_config_free(fallback)
                print("Failed to create ghostty app")
                return
            }
            self.app = created
            self.config = fallback
        }

        if let app {
            ghostty_app_set_focus(app, NSApp.isActive)
        }

        loadBackgroundColor()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard let app = GhosttyManager.shared.app else { return }
                ghostty_app_set_focus(app, true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard let app = GhosttyManager.shared.app else { return }
                ghostty_app_set_focus(app, false)
            }
        }
    }

    // MARK: - Config helpers

    private func loadBackgroundColor() {
        guard let config else { return }

        var color = ghostty_config_color_s()
        let bgKey = "background"
        if ghostty_config_get(config, &color, bgKey, UInt(bgKey.lengthOfBytes(using: .utf8))) {
            backgroundColor = NSColor(
                red: CGFloat(color.r) / 255,
                green: CGFloat(color.g) / 255,
                blue: CGFloat(color.b) / 255,
                alpha: 1.0
            )
        }

        var opacity = 1.0
        let opacityKey = "background-opacity"
        if ghostty_config_get(config, &opacity, opacityKey, UInt(opacityKey.lengthOfBytes(using: .utf8))) {
            backgroundOpacity = opacity
        }
    }

    // MARK: - Action handling

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_NEW_WINDOW:
            AppDelegate.shared?.createNewWindow()
            return true

        case GHOSTTY_ACTION_NEW_TAB:
            if let surface = targetSurface(target),
               let tabMgr = tabManagerForSurface(surface) {
                if let ws = tabMgr.selectedWorkspace {
                    ws.createTab()
                } else {
                    tabMgr.createTab()
                }
            }
            return true

        case GHOSTTY_ACTION_CLOSE_TAB:
            if let surface = targetSurface(target),
               let (tabMgr, tab) = tabAndManagerForSurface(surface) {
                tabMgr.closeTab(tab.id)
            }
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            if let surface = targetSurface(target),
               let (tabMgr, _) = tabAndManagerForSurface(surface) {
                tabMgr.window?.close()
            }
            return true

        case GHOSTTY_ACTION_SET_TITLE:
            if let surface = targetSurface(target) {
                let title = action.action.set_title.title.flatMap { String(cString: $0) } ?? ""
                DispatchQueue.main.async {
                    if let (_, tab) = self.tabAndManagerForSurface(surface) {
                        tab.title = title
                        // Track directory from title for workspace display
                        if let dir = Self.directoryFromTitle(title) {
                            tab.currentDirectory = dir
                        }
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_QUIT:
            NSApp.terminate(nil)
            return true

        case GHOSTTY_ACTION_GOTO_TAB:
            if let surface = targetSurface(target),
               let tabMgr = tabManagerForSurface(surface),
               let ws = tabMgr.selectedWorkspace {
                let goto = action.action.goto_tab
                switch goto {
                case GHOSTTY_GOTO_TAB_PREVIOUS:
                    ws.selectPreviousTab()
                case GHOSTTY_GOTO_TAB_NEXT:
                    ws.selectNextTab()
                case GHOSTTY_GOTO_TAB_LAST:
                    if let last = ws.tabs.last {
                        ws.selectTab(last.id)
                    }
                default:
                    let index = Int(goto.rawValue) - 1
                    if index >= 0 && index < ws.tabs.count {
                        ws.selectTab(ws.tabs[index].id)
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            if let surface = targetSurface(target) {
                let pwd = action.action.pwd.pwd.flatMap { String(cString: $0) } ?? ""
                if !pwd.isEmpty {
                    DispatchQueue.main.async {
                        if let (_, tab) = self.tabAndManagerForSurface(surface) {
                            tab.currentDirectory = pwd
                        }
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_NEW_SPLIT:
            if let surface = targetSurface(target),
               let (tabMgr, tab) = tabAndManagerForSurface(surface),
               let ws = tabMgr.selectedWorkspace {
                let ghosttyDir = action.action.new_split
                let direction: SplitNode.SplitDirection = (ghosttyDir == GHOSTTY_SPLIT_DIRECTION_DOWN || ghosttyDir == GHOSTTY_SPLIT_DIRECTION_UP) ? .vertical : .horizontal
                ws.createSplitTab(nextTo: tab.id, direction: direction)
            }
            return true

        case GHOSTTY_ACTION_GOTO_SPLIT:
            if let surface = targetSurface(target),
               let (tabMgr, _) = tabAndManagerForSurface(surface),
               let ws = tabMgr.selectedWorkspace,
               let layout = ws.splitLayout {
                let tabIds = layout.allTabIds
                guard tabIds.count > 1, let currentId = ws.selectedTabId,
                      let index = tabIds.firstIndex(of: currentId) else { return true }
                let gotoDir = action.action.goto_split
                let nextId: UUID
                if gotoDir == GHOSTTY_GOTO_SPLIT_PREVIOUS {
                    nextId = tabIds[(index - 1 + tabIds.count) % tabIds.count]
                } else {
                    nextId = tabIds[(index + 1) % tabIds.count]
                }
                ws.selectedTabId = nextId
                ws.tabs.first { $0.id == nextId }?.focus()
            }
            return true

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            return true

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            return true

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            return true

        case GHOSTTY_ACTION_RENDER:
            // No-op: Ghostty handles rendering via Metal
            return true

        default:
            return false
        }
    }

    // MARK: - Title parsing

    /// Extract a directory path from a terminal title like "~/Desktop - fish" or "/usr/local - bash".
    private static func directoryFromTitle(_ title: String) -> String? {
        // Fish/zsh typically set title to "~/path - shell" or "/path - shell"
        let candidate: String
        if let dashRange = title.range(of: " - ", options: .backwards) {
            candidate = String(title[title.startIndex..<dashRange.lowerBound])
        } else {
            candidate = title
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Expand ~ to home directory
        let expanded = NSString(string: trimmed).expandingTildeInPath

        // Verify it looks like a path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            return expanded
        }
        return nil
    }

    // MARK: - Target resolution

    private func targetSurface(_ target: ghostty_target_s) -> ghostty_surface_t? {
        switch target.tag {
        case GHOSTTY_TARGET_SURFACE:
            return target.target.surface
        case GHOSTTY_TARGET_APP:
            // Return the focused surface
            return AppDelegate.shared?.focusedTabManager?.selectedTab?.terminalView?.surface
        default:
            return nil
        }
    }

    private func tabManagerForSurface(_ surface: ghostty_surface_t) -> TabManager? {
        AppDelegate.shared?.tabManagers.first { mgr in
            mgr.tabs.contains { $0.terminalView?.surface == surface }
        }
    }

    private func tabAndManagerForSurface(_ surface: ghostty_surface_t) -> (TabManager, Tab)? {
        for mgr in AppDelegate.shared?.tabManagers ?? [] {
            if let tab = mgr.tabs.first(where: { $0.terminalView?.surface == surface }) {
                return (mgr, tab)
            }
        }
        return nil
    }

    // MARK: - Clipboard callbacks (static, called from C)

    private static func readClipboard(
        userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let userdata else { return }
        let ctx = Unmanaged<SurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = ctx.surface else { return }

        let pasteboard: NSPasteboard? = (location == GHOSTTY_CLIPBOARD_STANDARD) ? .general : nil
        let value = pasteboard?.string(forType: .string) ?? ""
        value.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
    }

    private static func writeClipboard(
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int
    ) {
        guard let content, len > 0 else { return }
        let buffer = UnsafeBufferPointer(start: content, count: len)

        var text: String?
        for item in buffer {
            guard let dataPtr = item.data else { continue }
            let value = String(cString: dataPtr)
            if let mimePtr = item.mime {
                let mime = String(cString: mimePtr)
                if mime.hasPrefix("text/plain") {
                    text = value
                    break
                }
            }
            if text == nil { text = value }
        }

        guard let text, location == GHOSTTY_CLIPBOARD_STANDARD else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func closeSurface(userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let ctx = Unmanaged<SurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
        let tabId = ctx.tabId

        DispatchQueue.main.async {
            guard let delegate = AppDelegate.shared else { return }
            for mgr in delegate.tabManagers {
                if mgr.tabs.contains(where: { $0.id == tabId }) {
                    mgr.closeTab(tabId)
                    return
                }
            }
        }
    }
}
