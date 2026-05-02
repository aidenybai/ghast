import SwiftUI
import AppKit

struct FileSearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let fileName: String
    let lineNumber: Int
    let lineText: String
}

@MainActor
class FileSearchEngine: ObservableObject {
    @Published var results: [FileSearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    private var searchTask: Task<Void, Never>?
    private let rgPath: String? = {
        let candidates = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }()

    func search(query: String, in directory: String) {
        searchTask?.cancel()
        results = []
        errorMessage = nil
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            isSearching = false
            return
        }
        guard rgPath != nil else {
            isSearching = false
            errorMessage = "Install ripgrep: brew install ripgrep"
            return
        }
        isSearching = true
        searchTask = Task {
            let found = await runRipgrep(query: query, directory: directory)
            if !Task.isCancelled {
                results = found
                isSearching = false
            }
        }
    }

    private func runRipgrep(query: String, directory: String) async -> [FileSearchResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let rgPath = self.rgPath else {
                    continuation.resume(returning: [])
                    return
                }
                print("[FileSearch] Searching for '\(query)' in '\(directory)'")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: rgPath)
                process.arguments = [
                    "--line-number", "--no-heading", "--color=never",
                    "--smart-case", "--max-count=5", "--max-filesize=1M",
                    "--glob=!.git", "--glob=!node_modules", "--glob=!*.lock",
                    query, directory
                ]
                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe
                var parsed: [FileSearchResult] = []
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    
                    if !errorOutput.isEmpty {
                        print("[FileSearch] ripgrep error: \(errorOutput)")
                    }
                    print("[FileSearch] Found \(output.components(separatedBy: "\n").filter { !$0.isEmpty }.count) lines")
                    
                    for line in output.components(separatedBy: "\n").prefix(200) {
                        guard !line.isEmpty else { continue }
                        let parts = line.components(separatedBy: ":")
                        guard parts.count >= 3, let lineNum = Int(parts[1]) else { continue }
                        let filePath = parts[0]
                        let lineText = parts[2...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                        let relPath = filePath.hasPrefix(directory) ? String(filePath.dropFirst(directory.count + 1)) : filePath
                        parsed.append(FileSearchResult(filePath: relPath, fileName: fileName, lineNumber: lineNum, lineText: lineText))
                    }
                } catch {
                    print("[FileSearch] Failed to run ripgrep: \(error)")
                }
                continuation.resume(returning: parsed)
            }
        }
    }
}

struct FileSearchView: View {
    @ObservedObject var tabManager: TabManager
    @Binding var isVisible: Bool
    @StateObject private var engine = FileSearchEngine()
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private var currentDirectory: String {
        // Use the selected tab's current directory (tracked via PWD action from shell)
        if let tab = tabManager.selectedTab, let cwd = tab.currentDirectory {
            print("[FileSearch] Using tab currentDirectory: \(cwd)")
            return cwd
        }
        // Fallback to workspace directory
        let fallback = tabManager.selectedWorkspace?.directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        print("[FileSearch] Using fallback directory: \(fallback)")
        return fallback
    }

    private func openFile(_ result: FileSearchResult) {
        let fullPath = currentDirectory + "/" + result.filePath
        NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
        isVisible = false
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isVisible else { return event }
            switch event.keyCode {
            case 53:
                isVisible = false
                return nil
            case 125:
                if !engine.results.isEmpty {
                    selectedIndex = min(selectedIndex + 1, engine.results.count - 1)
                }
                return nil
            case 126:
                if !engine.results.isEmpty {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
                return nil
            case 36, 76:
                if !engine.results.isEmpty {
                    openFile(engine.results[min(selectedIndex, engine.results.count - 1)])
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { isVisible = false }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: engine.isSearching ? "hourglass" : "doc.text.magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14))
                    TextField("Search in files...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                        .focused($isSearchFocused)
                        .onChange(of: query) { newVal in
                            selectedIndex = 0
                            engine.search(query: newVal, in: currentDirectory)
                        }
                        .onSubmit {
                            if !engine.results.isEmpty {
                                openFile(engine.results[min(selectedIndex, engine.results.count - 1)])
                            }
                        }
                    if !query.isEmpty {
                        Text("\(engine.results.count) results")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Text("in \(currentDirectory)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                Divider().opacity(0.15)
                if query.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.15))
                        Text("Type to search across files")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(height: 100)
                } else if engine.results.isEmpty && !engine.isSearching {
                    VStack(spacing: 6) {
                        Image(systemName: engine.errorMessage == nil ? "magnifyingglass" : "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.15))
                        Text(engine.errorMessage ?? "No results for \"\(query)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(height: 100)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, result in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(result.fileName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.9))
                                            Text(":\(result.lineNumber)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.blue.opacity(0.8))
                                        }
                                        Text(result.filePath)
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.35))
                                        Text(result.lineText)
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.55))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(index == selectedIndex ? 0.5 : 0.0))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(index == selectedIndex ? Color.white.opacity(0.08) : Color.clear))
                                .contentShape(Rectangle())
                                .onTapGesture { openFile(result) }
                                .onHover { if $0 { selectedIndex = index } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 380)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.98)))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            )
            .frame(width: 520)
            .onAppear {
                installKeyMonitor()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
            .onDisappear {
                removeKeyMonitor()
            }
        }
    }
}
