import AppKit
import Foundation

/// A workspace groups tabs by working directory.
@MainActor
final class Workspace: Identifiable, ObservableObject {
    let id: UUID
    @Published var directory: String
    @Published var customName: String?
    @Published var tabs: [Tab] = []
    @Published var selectedTabId: UUID?

    /// The split layout tree. Each leaf references a tab ID.
    /// When nil or a single leaf, the selected tab fills the whole area.
    @Published var splitLayout: SplitNode?

    var selectedTab: Tab? {
        guard let id = selectedTabId else { return tabs.first }
        return tabs.first { $0.id == id }
    }

    /// Display name: custom name if set, otherwise last path component of the directory.
    var displayName: String {
        if let custom = customName, !custom.isEmpty {
            return custom
        }
        let name = (directory as NSString).lastPathComponent
        return name.isEmpty ? "~" : name
    }

    init(directory: String) {
        self.id = UUID()
        self.directory = directory
    }

    @discardableResult
    func createTab() -> Tab {
        // Inherit working directory from the current tab if available
        let dir = selectedTab?.currentDirectory ?? directory
        let tab = Tab(workingDirectory: dir)
        tabs.append(tab)
        selectedTabId = tab.id
        return tab
    }

    /// Create a new tab split next to the given tab.
    @discardableResult
    func createSplitTab(nextTo tabId: UUID, direction: SplitNode.SplitDirection) -> Tab {
        let tab = Tab(workingDirectory: directory)
        tabs.append(tab)

        if let layout = splitLayout {
            // Add to existing split tree
            layout.splitTab(tabId, with: tab.id, direction: direction)
        } else {
            // First split: create a new tree with the source and new tab
            let root = SplitNode(tabId: tabId)
            root.splitTab(tabId, with: tab.id, direction: direction)
            splitLayout = root
        }

        selectedTabId = tab.id
        return tab
    }

    func closeTab(_ id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: index)

        // Remove from split layout
        if let layout = splitLayout {
            layout.removeTab(id)
            let remaining = layout.allTabIds
            if remaining.count <= 1 {
                // Back to single pane
                splitLayout = nil
            }
        }

        if tabs.isEmpty {
            return true // workspace is now empty
        } else if selectedTabId == id {
            if let layout = splitLayout, let firstVisible = layout.allTabIds.first {
                selectedTabId = firstVisible
            } else {
                let newIndex = min(index, tabs.count - 1)
                selectedTabId = tabs[newIndex].id
            }
        }
        return false
    }

    func moveTab(from sourceId: UUID, to targetId: UUID) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == sourceId }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetId }),
              fromIndex != toIndex else { return }
        tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabId = id
        // Split layout is preserved — the view layer decides whether to
        // show split or single-tab based on whether selectedTab is in the layout.
    }

    func selectNextTab() {
        guard tabs.count > 1, let currentId = selectedTabId,
              let index = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let next = (index + 1) % tabs.count
        selectedTabId = tabs[next].id
    }

    func selectPreviousTab() {
        guard tabs.count > 1, let currentId = selectedTabId,
              let index = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let prev = (index - 1 + tabs.count) % tabs.count
        selectedTabId = tabs[prev].id
    }
}
