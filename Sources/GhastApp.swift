import AppKit
import SwiftUI

@main
struct GhastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.configureGhosttyEnvironment()
    }

    var body: some Scene {
        // Window creation is handled by AppDelegate.
        // We use a hidden settings scene to satisfy the App protocol.
        Settings { EmptyView() }
    }

    /// Set up environment variables needed by libghostty before initialization.
    private static func configureGhosttyEnvironment() {
        let fm = FileManager.default

        // GHOSTTY_RESOURCES_DIR: look in bundle first, then system Ghostty.app
        if getenv("GHOSTTY_RESOURCES_DIR") == nil {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("ghostty")
            let system = "/Applications/Ghostty.app/Contents/Resources/ghostty"

            if let bundled, fm.fileExists(atPath: bundled.path) {
                setenv("GHOSTTY_RESOURCES_DIR", bundled.path, 1)
            } else if fm.fileExists(atPath: system) {
                setenv("GHOSTTY_RESOURCES_DIR", system, 1)
            }
        }

        if getenv("TERM") == nil {
            setenv("TERM", "xterm-ghostty", 1)
        }

        if getenv("TERM_PROGRAM") == nil {
            setenv("TERM_PROGRAM", "ghostty", 1)
        }
    }
}
