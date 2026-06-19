import SwiftUI
import AppKit

// MARK: - History loading

/// Cached for the lifetime of the app so repeated opens of History Search
/// don't re-read and re-parse the shell history file from disk each time.
private var cachedHistory: [String]?

private func loadHistory() -> [String] {
    if let cachedHistory { return cachedHistory }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let candidates = [
        "\(home)/.zsh_history",
        "\(home)/.bash_history",
        "\(home)/.history",
    ]
    for path in candidates {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { continue }

        var entries: [String] = []
        // zsh extended history format: ": timestamp:elapsed;command"
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix(": "), let semicolon = trimmed.range(of: ";") {
                let cmd = String(trimmed[semicolon.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !cmd.isEmpty { entries.append(cmd) }
            } else {
                entries.append(trimmed)
            }
        }
        if !entries.isEmpty {
            // Deduplicate preserving last occurrence, reverse so newest first
            var seen = Set<String>()
            var deduped: [String] = []
            for cmd in entries.reversed() {
                if seen.insert(cmd).inserted { deduped.append(cmd) }
            }
            cachedHistory = deduped
            return deduped
        }
    }
    cachedHistory = []
    return []
}

private func fuzzyMatch(_ query: String, in string: String) -> Bool {
    guard !query.isEmpty else { return true }
    let q = query.lowercased()
    let s = string.lowercased()
    var qi = q.startIndex
    for ch in s {
        if ch == q[qi] {
            qi = q.index(after: qi)
            if qi == q.endIndex { return true }
        }
    }
    return false
}

// MARK: - View

struct FileSearchView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var isVisible: Bool

    @State private var query = ""
    @State private var allHistory: [String] = []
    @State private var filtered: [String] = []
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private func runCommand(_ cmd: String, execute: Bool) {
        guard let tab = tabManager.selectedTab,
              let tv = tab.terminalView,
              let surface = tv.surface else { return }
        let text = execute ? cmd + "\n" : cmd
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
        isVisible = false
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isVisible else { return event }
            switch event.keyCode {
            case 53: // Esc
                isVisible = false
                return nil
            case 125: // Down
                if !filtered.isEmpty {
                    selectedIndex = min(selectedIndex + 1, filtered.count - 1)
                }
                return nil
            case 126: // Up
                if !filtered.isEmpty {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
                return nil
            case 36: // Enter — Cmd+Enter pastes without running, plain Enter runs
                if !filtered.isEmpty {
                    let cmd = filtered[min(selectedIndex, filtered.count - 1)]
                    runCommand(cmd, execute: !event.modifierFlags.contains(.command))
                }
                return nil
            case 76: // Numpad Enter — paste only
                if !filtered.isEmpty {
                    runCommand(filtered[min(selectedIndex, filtered.count - 1)], execute: false)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let km = keyMonitor { NSEvent.removeMonitor(km); keyMonitor = nil }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { isVisible = false }

            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14))
                    TextField("Search command history...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                        .focused($isSearchFocused)
                        .onChange(of: query) { val in
                            selectedIndex = 0
                            filtered = val.isEmpty ? allHistory : allHistory.filter { fuzzyMatch(val, in: $0) }
                        }
                        .onSubmit {
                            if !filtered.isEmpty {
                                runCommand(filtered[min(selectedIndex, filtered.count - 1)], execute: true)
                            }
                        }
                    if !query.isEmpty {
                        Text("\(filtered.count)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HStack {
                    Text("↵ run  ·  ⌘↵ paste  ·  esc close")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider().opacity(0.15)

                if filtered.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: query.isEmpty ? "clock" : "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.15))
                        Text(query.isEmpty ? "No history found" : "No matches for \"\(query)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(height: 100)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 1) {
                                ForEach(Array(filtered.prefix(200).enumerated()), id: \.offset) { index, cmd in
                                    HStack {
                                        Text(cmd)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(index == selectedIndex ? .white.opacity(0.95) : .white.opacity(0.55))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer()
                                        if index == selectedIndex {
                                            Text("↵")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.3))
                                        }
                                    }
                                    .id(index)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(index == selectedIndex ? Color.white.opacity(0.08) : Color.clear))
                                    .contentShape(Rectangle())
                                    .onTapGesture { runCommand(cmd, execute: true) }
                                    .onHover { if $0 { selectedIndex = index } }
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 380)
                        .onChange(of: selectedIndex) { idx in
                            withAnimation { proxy.scrollTo(idx, anchor: .center) }
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.98)))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            )
            .frame(width: 560)
            .onAppear {
                installKeyMonitor()
                DispatchQueue.global(qos: .userInitiated).async {
                    let history = loadHistory()
                    DispatchQueue.main.async {
                        allHistory = history
                        filtered = history
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isSearchFocused = true }
            }
            .onDisappear { removeKeyMonitor() }
        }
    }
}
