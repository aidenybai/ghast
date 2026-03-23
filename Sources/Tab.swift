import AppKit
import Foundation

/// A single tab in a window. Each tab owns one terminal surface.
@MainActor
final class Tab: Identifiable, ObservableObject {
    let id: UUID
    @Published var title: String

    /// The current working directory as reported by the shell.
    var currentDirectory: String?

    /// Working directory to use when creating the terminal.
    var initialWorkingDirectory: String?

    // Search state (driven by Ghostty actions, displayed by SearchBarView)
    @Published var isSearching: Bool = false
    @Published var searchNeedle: String = ""
    @Published var searchTotal: Int = 0
    @Published var searchSelected: Int = 0

    /// The terminal view is created lazily when the tab becomes visible.
    private(set) var terminalView: TerminalView?

    /// Known shell names — if the title matches one of these, the tab is idle at a prompt.
    private static let shellNames: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh", "nu", "nushell", "elvish", "pwsh",
    ]

    /// Whether this tab appears to be running a command (not idle at the shell prompt).
    /// Inferred from the title: shells typically set the title to the running command,
    /// and reset it to the shell name (or path) when idle.
    var isRunningCommand: Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != "Terminal" else { return false }

        // Strip "~/path - shell" style titles down to just the shell part
        let shellPart: String
        if let dashRange = t.range(of: " - ", options: .backwards) {
            shellPart = String(t[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            shellPart = t
        }

        // Check the last path component (handles "/bin/zsh" etc.)
        let baseName = (shellPart as NSString).lastPathComponent.lowercased()
        return !Self.shellNames.contains(baseName)
    }

    init(id: UUID = UUID(), title: String = "Terminal", workingDirectory: String? = nil) {
        self.id = id
        self.title = title
        self.initialWorkingDirectory = workingDirectory
    }

    /// Creates and returns the terminal NSView for embedding in the window.
    func makeTerminalView(frame: NSRect) -> TerminalView {
        if let existing = terminalView { return existing }
        let view = TerminalView(frame: frame, tabId: id, workingDirectory: initialWorkingDirectory)
        terminalView = view
        return view
    }

    func focus() {
        guard let view = terminalView else { return }
        view.window?.makeFirstResponder(view)
    }
}
