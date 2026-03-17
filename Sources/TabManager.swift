import AppKit
import Combine
import Foundation

/// Manages workspaces (grouped by directory) and their tabs for a single window.
@MainActor
final class TabManager: ObservableObject {
    weak var window: NSWindow?

    @Published var workspaces: [Workspace] = []
    @Published var selectedWorkspaceId: UUID?
    @Published var isSidebarVisible: Bool = true

    /// Bumped to force SwiftUI re-render when nested workspace state changes.
    @Published private var changeToken: UInt = 0

    private var workspaceSubs: [UUID: AnyCancellable] = [:]

    var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceId else { return workspaces.first }
        return workspaces.first { $0.id == id }
    }

    /// Convenience: the currently selected tab in the active workspace.
    var selectedTab: Tab? { selectedWorkspace?.selectedTab }

    /// All tabs across all workspaces (for surface lookups).
    var tabs: [Tab] { workspaces.flatMap { $0.tabs } }

    private var focusObserver: Any?

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let workspace = addWorkspace(directory: homeDir)
        workspace.createTab()

        focusObserver = NotificationCenter.default.addObserver(
            forName: .terminalViewDidFocus, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let view = notification.object as? TerminalView else { return }
                let tabId = view.tabId
                // Find the workspace containing this tab and update selection
                for ws in self.workspaces {
                    if ws.tabs.contains(where: { $0.id == tabId }) {
                        if let layout = ws.splitLayout, layout.allTabIds.contains(tabId) {
                            // In split mode: just update selected tab, keep layout
                            ws.selectedTabId = tabId
                        }
                        break
                    }
                }
            }
        }
    }

    // MARK: - Workspace management

    @discardableResult
    private func addWorkspace(directory: String) -> Workspace {
        let ws = Workspace(directory: directory)
        workspaces.append(ws)
        observeWorkspace(ws)
        selectedWorkspaceId = ws.id
        return ws
    }

    private func observeWorkspace(_ ws: Workspace) {
        workspaceSubs[ws.id] = ws.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.changeToken &+= 1
            }
        }
    }

    @discardableResult
    func createWorkspace(directory: String) -> Workspace {
        addWorkspace(directory: directory)
    }

    func selectWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        selectedWorkspaceId = id
    }

    func closeWorkspace(_ id: UUID) {
        workspaceSubs.removeValue(forKey: id)
        workspaces.removeAll { $0.id == id }

        if selectedWorkspaceId == id {
            selectedWorkspaceId = workspaces.first?.id
        }

        if workspaces.isEmpty {
            window?.close()
        }
    }

    /// Find or create a workspace for the given directory, then switch to it.
    func handleDirectoryChange(tabId: UUID, directory: String) {
        let normalized = normalizePath(directory)

        // Find which workspace currently owns this tab
        guard let sourceWs = workspaces.first(where: { $0.tabs.contains(where: { $0.id == tabId }) }) else { return }

        // If the tab is already in a workspace with this directory, no-op
        if normalizePath(sourceWs.directory) == normalized { return }

        // If this is the only tab in the workspace, just update the workspace's directory
        // instead of creating a new empty workspace
        if sourceWs.tabs.count == 1 {
            // But only if no other workspace already owns this directory
            if workspaces.contains(where: { $0.id != sourceWs.id && normalizePath($0.directory) == normalized }) {
                // Another workspace exists for this dir — move the tab there
            } else {
                sourceWs.directory = normalized
                return
            }
        }

        // Find or create the target workspace
        let targetWs: Workspace
        if let existing = workspaces.first(where: { normalizePath($0.directory) == normalized }) {
            targetWs = existing
        } else {
            targetWs = Workspace(directory: normalized)
            workspaces.append(targetWs)
            observeWorkspace(targetWs)
        }

        // Move the tab from source to target
        guard let tab = sourceWs.tabs.first(where: { $0.id == tabId }) else { return }
        sourceWs.tabs.removeAll { $0.id == tabId }

        // Fix source workspace selection — the moved tab may have been selected
        if sourceWs.selectedTabId == tabId {
            sourceWs.selectedTabId = sourceWs.tabs.first?.id
        }

        targetWs.tabs.append(tab)
        targetWs.selectedTabId = tab.id

        // Switch to the target workspace
        selectedWorkspaceId = targetWs.id
    }

    // MARK: - Tab management (delegates to active workspace)

    @discardableResult
    func createTab() -> Tab {
        guard let ws = selectedWorkspace else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let ws = addWorkspace(directory: homeDir)
            return ws.createTab()
        }
        return ws.createTab()
    }

    func closeTab(_ id: UUID) {
        for ws in workspaces {
            if ws.closeTab(id) {
                // Workspace is now empty, remove it
                workspaceSubs.removeValue(forKey: ws.id)
                workspaces.removeAll { $0.id == ws.id }
                if selectedWorkspaceId == ws.id {
                    selectedWorkspaceId = workspaces.first?.id
                }
                break
            }
        }

        if workspaces.isEmpty {
            window?.close()
        }
    }

    func selectTab(_ id: UUID) {
        selectedWorkspace?.selectTab(id)
    }

    func selectNextTab() {
        selectedWorkspace?.selectNextTab()
    }

    func selectPreviousTab() {
        selectedWorkspace?.selectPreviousTab()
    }

    // MARK: - Helpers

    private func normalizePath(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        return (expanded as NSString).standardizingPath
    }
}
