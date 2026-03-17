import Foundation

/// Binary tree representing how tabs are arranged in a split layout.
/// Each leaf holds a tab ID; each branch splits two children side by side or stacked.
@MainActor
final class SplitNode: Identifiable, ObservableObject {
    let id: UUID

    enum Content {
        case tab(UUID)
        case split(direction: SplitDirection, first: SplitNode, second: SplitNode, ratio: CGFloat)
    }

    enum SplitDirection {
        case horizontal // side by side
        case vertical   // top and bottom
    }

    @Published var content: Content

    init(tabId: UUID) {
        self.id = UUID()
        self.content = .tab(tabId)
    }

    private init(direction: SplitDirection, first: SplitNode, second: SplitNode, ratio: CGFloat) {
        self.id = UUID()
        self.content = .split(direction: direction, first: first, second: second, ratio: ratio)
    }

    /// The tab ID if this is a leaf.
    var tabId: UUID? {
        if case .tab(let id) = content { return id }
        return nil
    }

    /// All tab IDs visible in this layout.
    var allTabIds: [UUID] {
        switch content {
        case .tab(let id):
            return [id]
        case .split(_, let first, let second, _):
            return first.allTabIds + second.allTabIds
        }
    }

    /// Find the leaf containing the given tab ID.
    func findLeaf(for targetId: UUID) -> SplitNode? {
        switch content {
        case .tab(let id):
            return id == targetId ? self : nil
        case .split(_, let first, let second, _):
            return first.findLeaf(for: targetId) ?? second.findLeaf(for: targetId)
        }
    }

    /// Split the leaf containing `tabId`, placing `newTabId` next to it.
    @discardableResult
    func splitTab(_ tabId: UUID, with newTabId: UUID, direction: SplitDirection) -> Bool {
        guard let leaf = findLeaf(for: tabId) else { return false }
        guard case .tab(_) = leaf.content else { return false }

        let firstChild = SplitNode(tabId: tabId)
        let secondChild = SplitNode(tabId: newTabId)

        leaf.content = .split(
            direction: direction,
            first: firstChild,
            second: secondChild,
            ratio: 0.5
        )
        return true
    }

    /// Remove a tab from the layout, collapsing its parent split.
    /// Returns true if found and removed.
    func removeTab(_ targetId: UUID) -> Bool {
        switch content {
        case .tab(_):
            return false // Can't remove self from self

        case .split(_, let first, let second, _):
            if case .tab(let id) = first.content, id == targetId {
                self.content = second.content
                return true
            }
            if case .tab(let id) = second.content, id == targetId {
                self.content = first.content
                return true
            }
            return first.removeTab(targetId) || second.removeTab(targetId)
        }
    }

    /// Update the split ratio.
    func setRatio(_ ratio: CGFloat) {
        if case .split(let dir, let first, let second, _) = content {
            content = .split(direction: dir, first: first, second: second, ratio: max(0.1, min(0.9, ratio)))
        }
    }

    // MARK: - Serialization

    final class Serialized: Codable {
        enum NodeType: String, Codable { case tab, split }
        let type: NodeType
        let tabId: String?
        let direction: String?
        let ratio: CGFloat?
        let first: Serialized?
        let second: Serialized?

        init(type: NodeType, tabId: String?, direction: String?, ratio: CGFloat?, first: Serialized?, second: Serialized?) {
            self.type = type; self.tabId = tabId; self.direction = direction
            self.ratio = ratio; self.first = first; self.second = second
        }
    }

    func serialize() -> Serialized {
        switch content {
        case .tab(let id):
            return Serialized(type: .tab, tabId: id.uuidString, direction: nil, ratio: nil, first: nil, second: nil)
        case .split(let dir, let first, let second, let ratio):
            return Serialized(
                type: .split,
                tabId: nil,
                direction: dir == .horizontal ? "horizontal" : "vertical",
                ratio: ratio,
                first: first.serialize(),
                second: second.serialize()
            )
        }
    }

    static func deserialize(_ s: Serialized) -> SplitNode? {
        switch s.type {
        case .tab:
            guard let idStr = s.tabId, let id = UUID(uuidString: idStr) else { return nil }
            return SplitNode(tabId: id)
        case .split:
            guard let dirStr = s.direction,
                  let first = s.first.flatMap({ deserialize($0) }),
                  let second = s.second.flatMap({ deserialize($0) }) else { return nil }
            let dir: SplitDirection = dirStr == "horizontal" ? .horizontal : .vertical
            let node = SplitNode(tabId: UUID()) // placeholder
            node.content = .split(direction: dir, first: first, second: second, ratio: s.ratio ?? 0.5)
            return node
        }
    }
}
