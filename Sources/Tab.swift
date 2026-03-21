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
