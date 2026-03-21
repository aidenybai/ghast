import AppKit
import SwiftUI

/// Main window content: sidebar + tab bar + terminal.
struct ContentView: View {
    @ObservedObject var tabManager: TabManager
    @State private var sidebarWidth: CGFloat = 180

    private var bgColor: Color { Color(nsColor: GhosttyManager.shared.backgroundColor) }

    var body: some View {
        HStack(spacing: 0) {
            if tabManager.isSidebarVisible {
                WorkspaceSidebar(tabManager: tabManager)
                    .frame(width: sidebarWidth)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    .onHover { h in
                        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                sidebarWidth = min(max(sidebarWidth + value.translation.width, 120), 400)
                            }
                    )
            }

            VStack(spacing: 0) {
                TabBar(tabManager: tabManager)
                if let tab = tabManager.selectedTab, tab.isSearching {
                    SearchBarView(tab: tab)
                }
                TerminalContainerView(tabManager: tabManager)
            }
        }
        .background(bgColor)
    }

}

// MARK: - Search bar

struct SearchBarView: View {
    @ObservedObject var tab: Tab

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))

            Text(tab.searchNeedle.isEmpty ? "Search" : tab.searchNeedle)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)

            Spacer()

            if tab.searchTotal > 0 {
                Text("\(tab.searchSelected)/\(tab.searchTotal)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            } else if tab.isSearching {
                Text("No results")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
    }
}

struct WorkspaceSidebar: View {
    @ObservedObject var tabManager: TabManager

    private var bgColor: Color { Color(nsColor: GhosttyManager.shared.backgroundColor) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)

            // + Workspace at top
            Button(action: {
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let ws = tabManager.createWorkspace(directory: homeDir)
                ws.createTab()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("Workspace")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(tabManager.workspaces) { workspace in
                        WorkspaceItemView(
                            workspace: workspace,
                            isSelected: workspace.id == tabManager.selectedWorkspaceId,
                            onSelect: { tabManager.selectWorkspace(workspace.id) },
                            onClose: { tabManager.closeWorkspace(workspace.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(bgColor)
    }
}

struct WorkspaceItemView: View {
    @ObservedObject var workspace: Workspace
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    /// The selected tab's title, used for the subtitle line.
    private var activeTabTitle: String {
        workspace.selectedTab?.title ?? ""
    }

    /// Short directory path for display (e.g. "~/Projects/ghast").
    private var directoryLabel: String {
        let dir = workspace.selectedTab?.currentDirectory ?? workspace.directory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            let rel = String(dir.dropFirst(home.count))
            return rel.isEmpty ? "~" : "~" + rel
        }
        return dir
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        workspace.customName = trimmed.isEmpty ? nil : trimmed
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Workspace name", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .focused($isTextFieldFocused)
                        .onSubmit { commitEdit() }
                        .onExitCommand { cancelEdit() }
                } else {
                    Text(workspace.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.5))
                }

                Text(directoryLabel)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? .white.opacity(0.4) : .white.opacity(0.2))
            }

            Spacer()

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("\(workspace.tabs.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.06) : isHovering ? Color.white.opacity(0.03) : Color.clear)
        )
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            editText = workspace.customName ?? workspace.displayName
            isEditing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
        }
        .onTapGesture(count: 1) {
            if isEditing {
                commitEdit()
            } else {
                onSelect()
            }
        }
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @ObservedObject var tabManager: TabManager

    private var bgColor: Color { Color(nsColor: GhosttyManager.shared.backgroundColor) }

    var body: some View {
        ZStack {
            // Tabs fill the entire width
            if let ws = tabManager.selectedWorkspace {
                TabListView(workspace: ws, tabManager: tabManager)
            }

            // Buttons overlay on left and right edges
            HStack(spacing: 0) {
                // Sidebar toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        tabManager.isSidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(tabManager.isSidebarVisible ? 0.6 : 0.3))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(bgColor)

                Spacer()

                // Split button
                Button(action: {
                    if let ws = tabManager.selectedWorkspace, let tab = ws.selectedTab {
                        ws.createSplitTab(nextTo: tab.id, direction: .horizontal)
                    }
                }) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(bgColor)

                // New tab button
                Button(action: {
                    tabManager.selectedWorkspace?.createTab()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(bgColor)
            }
        }
        .frame(height: 36)
        .background(bgColor)
    }
}

struct TabListView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var tabManager: TabManager
    @State private var draggedTabId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                TabItemView(
                    tab: tab,
                    index: index,
                    isSelected: tab.id == workspace.selectedTabId,
                    isOnly: workspace.tabs.count == 1,
                    onClose: { tabManager.closeTab(tab.id) }
                )
                .onTapGesture { workspace.selectTab(tab.id) }
                .onDrag {
                    draggedTabId = tab.id
                    return NSItemProvider(object: tab.id.uuidString as NSString)
                } preview: {
                    Text(tab.title.isEmpty ? "Terminal" : tab.title)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(4)
                }
                .onDrop(of: [.text], delegate: TabDropDelegate(
                    targetId: tab.id,
                    workspace: workspace,
                    draggedTabId: $draggedTabId
                ))

                // Separator between tabs
                if index < workspace.tabs.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 14)
                }
            }
        }
    }
}

struct TabItemView: View {
    @ObservedObject var tab: Tab
    let index: Int
    let isSelected: Bool
    let isOnly: Bool
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if isHovering && !isOnly {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(tab.title.isEmpty ? "Terminal" : tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.4))

            if index < 9 {
                Text("\u{2318}\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.white.opacity(0.06) : isHovering ? Color.white.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Tab drag & drop

// MARK: - Split drop target

struct SplitDropTargetView<Content: View>: View {
    @ObservedObject var tabManager: TabManager
    let content: () -> Content
    @State private var dropEdge: Edge?

    init(tabManager: TabManager, @ViewBuilder content: @escaping () -> Content) {
        self.tabManager = tabManager
        self.content = content
    }

    var body: some View {
        content()
            .overlay(
                GeometryReader { geo in
                    // Drop zone overlay — only visible when dragging
                    if let edge = dropEdge {
                        dropHighlight(edge: edge, size: geo.size)
                    }

                    // Invisible drop target
                    Color.clear
                        .contentShape(Rectangle())
                        .onDrop(of: [.text], delegate: SplitDropDelegate(
                            tabManager: tabManager,
                            size: geo.size,
                            dropEdge: $dropEdge
                        ))
                }
            )
    }

    @ViewBuilder
    private func dropHighlight(edge: Edge, size: CGSize) -> some View {
        let halfW = size.width / 2
        let halfH = size.height / 2
        switch edge {
        case .leading:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: halfW, height: size.height)
                .position(x: halfW / 2, y: size.height / 2)
        case .trailing:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: halfW, height: size.height)
                .position(x: size.width - halfW / 2, y: size.height / 2)
        case .top:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: size.width, height: halfH)
                .position(x: size.width / 2, y: halfH / 2)
        case .bottom:
            Rectangle().fill(Color.blue.opacity(0.15))
                .frame(width: size.width, height: halfH)
                .position(x: size.width / 2, y: size.height - halfH / 2)
        }
    }
}

struct SplitDropDelegate: DropDelegate {
    let tabManager: TabManager
    let size: CGSize
    @Binding var dropEdge: Edge?

    private func edgeForLocation(_ location: CGPoint) -> Edge {
        let relX = location.x / size.width
        let relY = location.y / size.height
        // Check which edge is closest
        let distances: [(Edge, CGFloat)] = [
            (.leading, relX),
            (.trailing, 1 - relX),
            (.top, relY),
            (.bottom, 1 - relY),
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropEdge = edgeForLocation(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropEdge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        dropEdge = nil
        guard let ws = tabManager.selectedWorkspace,
              let currentTab = ws.selectedTab else { return false }

        // Get the dropped tab ID from the drag data
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidString = string as? String,
                  let droppedTabId = UUID(uuidString: uuidString) else { return }

            DispatchQueue.main.async {
                // Don't split with self
                guard droppedTabId != currentTab.id else { return }
                // Must be a tab in this workspace
                guard ws.tabs.contains(where: { $0.id == droppedTabId }) else { return }

                let edge = self.edgeForLocation(info.location)
                let direction: SplitNode.SplitDirection = (edge == .leading || edge == .trailing) ? .horizontal : .vertical

                // Create split layout
                if let layout = ws.splitLayout {
                    // Already split — add to the tree next to the current tab
                    if !layout.allTabIds.contains(droppedTabId) {
                        layout.splitTab(currentTab.id, with: droppedTabId, direction: direction)
                    }
                } else {
                    let root = SplitNode(tabId: currentTab.id)
                    if edge == .leading || edge == .top {
                        // Dropped tab goes first
                        root.splitTab(currentTab.id, with: droppedTabId, direction: direction)
                        // Swap: we need dropped tab on the left/top
                        // Actually splitTab puts droppedTabId as second, so for leading/top we swap
                        if case .split(let dir, let first, let second, let ratio) = root.content {
                            root.content = .split(direction: dir, first: second, second: first, ratio: 1 - ratio)
                        }
                    } else {
                        root.splitTab(currentTab.id, with: droppedTabId, direction: direction)
                    }
                    ws.splitLayout = root
                }
                ws.selectedTabId = droppedTabId
            }
        }
        return true
    }
}

struct TabDropDelegate: DropDelegate {
    let targetId: UUID
    let workspace: Workspace
    @Binding var draggedTabId: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedTabId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedTabId, draggedId != targetId else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            workspace.moveTab(from: draggedId, to: targetId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Terminal container

struct TerminalContainerView: NSViewRepresentable {
    @ObservedObject var tabManager: TabManager

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let ws = tabManager.selectedWorkspace,
              let selectedTab = tabManager.selectedTab else {
            container.subviews.forEach { $0.isHidden = true }
            return
        }

        let tabLookup: (UUID) -> Tab? = { id in ws.tabs.first { $0.id == id } }

        // Clean up stale tab IDs from split layout
        if let layout = ws.splitLayout {
            let tabIds = Set(ws.tabs.map { $0.id })
            for splitTabId in layout.allTabIds where !tabIds.contains(splitTabId) {
                layout.removeTab(splitTabId)
            }
            if layout.allTabIds.count <= 1 {
                ws.splitLayout = nil
            }
        }

        // ZOOM MODE: show a single pane fullscreen while preserving the split tree
        if let zoomedId = ws.zoomedTabId,
           let layout = ws.splitLayout,
           layout.allTabIds.contains(zoomedId),
           let zoomedTab = tabLookup(zoomedId) {
            for subview in container.subviews where subview is SplitContainerView {
                subview.isHidden = true
            }
            let terminalView = zoomedTab.makeTerminalView(frame: container.bounds)
            if terminalView.superview is SplitContainerView {
                terminalView.removeFromSuperview()
            }
            if terminalView.superview !== container {
                terminalView.removeFromSuperview()
                terminalView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(terminalView)
                NSLayoutConstraint.activate([
                    terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                    terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }
            for subview in container.subviews where subview is TerminalView {
                subview.isHidden = (subview !== terminalView)
            }
            terminalView.isHidden = false
            if let surface = terminalView.surface {
                ghostty_surface_refresh(surface)
            }
            terminalView.needsDisplay = true
            DispatchQueue.main.async { zoomedTab.focus() }
            return
        }

        if let layout = ws.splitLayout,
           layout.allTabIds.count > 1,
           layout.allTabIds.contains(selectedTab.id) {
            // Split mode: show multiple tabs via SplitContainerView
            let splitContainer: SplitContainerView
            if let existing = container.subviews.compactMap({ $0 as? SplitContainerView }).first {
                splitContainer = existing
            } else {
                splitContainer = SplitContainerView(frame: container.bounds)
                splitContainer.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(splitContainer)
                NSLayoutConstraint.activate([
                    splitContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    splitContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    splitContainer.topAnchor.constraint(equalTo: container.topAnchor),
                    splitContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }

            splitContainer.isHidden = false
            splitContainer.update(with: layout, tabLookup: tabLookup)

            // Refresh visible surfaces
            for tabId in layout.allTabIds {
                if let tab = tabLookup(tabId), let tv = tab.terminalView, let surface = tv.surface {
                    ghostty_surface_refresh(surface)
                    tv.needsDisplay = true
                }
            }
        } else {
            // Single tab mode — hide split container but don't remove it
            for subview in container.subviews where subview is SplitContainerView {
                subview.isHidden = true
            }

            let terminalView = selectedTab.makeTerminalView(frame: container.bounds)

            if terminalView.superview is SplitContainerView {
                // Move out of the split container back to the main container
                terminalView.removeFromSuperview()
            }

            if terminalView.superview !== container {
                terminalView.removeFromSuperview()
                terminalView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(terminalView)
                NSLayoutConstraint.activate([
                    terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                    terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }

            // Hide other direct terminal views
            for subview in container.subviews where subview is TerminalView {
                subview.isHidden = (subview !== terminalView)
            }
            terminalView.isHidden = false

            if let surface = terminalView.surface {
                ghostty_surface_refresh(surface)
            }
            terminalView.needsDisplay = true

            DispatchQueue.main.async {
                selectedTab.focus()
            }
        }
    }
}
