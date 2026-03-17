import AppKit
import Foundation

/// A single tab in a window. Each tab owns one terminal surface.
@MainActor
final class Tab: Identifiable, ObservableObject {
    let id: UUID
    @Published var title: String

    /// The current working directory as reported by the shell.
    var currentDirectory: String?

    /// Whether this tab has received its first directory report.
    var hasReceivedInitialDirectory: Bool = false

    /// Working directory to use when creating the terminal.
    var initialWorkingDirectory: String?

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
