import SwiftUI

struct QuickSwitcherItem: Identifiable {
    let id: UUID
    let workspaceId: UUID
    let tabId: UUID?
    let title: String
    let subtitle: String
    let isWorkspace: Bool
}

struct QuickSwitcherView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var isVisible: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private var items: [QuickSwitcherItem] {
        let all = tabManager.workspaces.flatMap { ws -> [QuickSwitcherItem] in
            var result: [QuickSwitcherItem] = []
            result.append(QuickSwitcherItem(
                id: ws.id, workspaceId: ws.id, tabId: nil,
                title: ws.displayName, subtitle: ws.directory, isWorkspace: true
            ))
            for tab in ws.tabs {
                result.append(QuickSwitcherItem(
                    id: tab.id, workspaceId: ws.id, tabId: tab.id,
                    title: tab.displayName.isEmpty ? "Terminal" : tab.displayName,
                    subtitle: ws.displayName, isWorkspace: false
                ))
            }
            return result
        }
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
    }

    private func select(_ item: QuickSwitcherItem) {
        tabManager.selectWorkspace(item.workspaceId)
        if let tabId = item.tabId { tabManager.selectTab(tabId) }
        isVisible = false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isVisible = false }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14))
                    TextField("Jump to workspace or tab...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                        .focused($isSearchFocused)
                        .onSubmit {
                            if !items.isEmpty {
                                select(items[min(selectedIndex, items.count - 1)])
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().opacity(0.15)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isWorkspace ? "folder" : "terminal")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                    Text(item.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(index == selectedIndex ? Color.white.opacity(0.1) : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { select(item) }
                            .onHover { if $0 { selectedIndex = index } }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.98)))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            )
            .frame(width: 420)
            .onAppear { isSearchFocused = true; selectedIndex = 0 }
            .onChange(of: query) { _ in selectedIndex = 0 }
        }
        .onKeyPress(.escape) { isVisible = false; return .handled }
        .onKeyPress(.downArrow) { if !items.isEmpty { selectedIndex = min(selectedIndex + 1, items.count - 1) }; return .handled }
        .onKeyPress(.upArrow) { selectedIndex = max(selectedIndex - 1, 0); return .handled }
    }
}
