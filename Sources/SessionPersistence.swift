import Foundation

// MARK: - Codable snapshots

struct TabSnapshot: Codable {
    let id: UUID
    let customName: String?
    let workingDirectory: String?
    let tmuxSessionName: String?
}

struct WorkspaceSnapshot: Codable {
    let id: UUID
    let directory: String
    let customName: String?
    let tabs: [TabSnapshot]
    let selectedTabId: UUID?
    let splitLayout: SplitNode.Serialized?
    let zoomedTabId: UUID?
}

struct SessionSnapshot: Codable {
    let workspaces: [WorkspaceSnapshot]
    let selectedWorkspaceId: UUID?
}

// MARK: - Persistence

@MainActor
struct SessionPersistence {
    private static var saveDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("ghast", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func saveURL(for windowId: UUID) -> URL {
        saveDir.appendingPathComponent("session_\(windowId.uuidString).json")
    }

    static func save(tabManager: TabManager) {
        let snapshot = SessionSnapshot(
            workspaces: tabManager.workspaces.map { ws in
                WorkspaceSnapshot(
                    id: ws.id,
                    directory: ws.directory,
                    customName: ws.customName,
                    tabs: ws.tabs.map { tab in
                        TabSnapshot(
                            id: tab.id,
                            customName: tab.customName,
                            workingDirectory: tab.currentDirectory ?? tab.initialWorkingDirectory,
                            tmuxSessionName: tab.tmuxSessionName
                        )
                    },
                    selectedTabId: ws.selectedTabId,
                    splitLayout: ws.splitLayout?.serialize(),
                    zoomedTabId: ws.zoomedTabId
                )
            },
            selectedWorkspaceId: tabManager.selectedWorkspaceId
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: saveURL(for: tabManager.windowId))
        }
    }

    static func load(for windowId: UUID) -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: saveURL(for: windowId)),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    /// ponytail: one-time fallback for legacy session.json (pre-multi-window).
    static func loadLegacy() -> SessionSnapshot? {
        let url = saveDir.appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    static func allWindowIds() -> [UUID] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: saveDir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("session_"), name.hasSuffix(".json") else { return nil }
            return UUID(uuidString: String(name.dropFirst("session_".count).dropLast(".json".count)))
        }
    }
}
