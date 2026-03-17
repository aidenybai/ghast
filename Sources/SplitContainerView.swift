import AppKit
import Foundation

/// NSView that renders a SplitNode layout tree, placing tab terminal views in each pane.
class SplitContainerView: NSView {
    private var currentLayout: SplitNode?
    private var dividerViews: [DividerView] = []
    private var tabLookup: ((UUID) -> Tab?)? = nil

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Update layout with the given split tree and a tab lookup closure.
    func update(with layout: SplitNode, tabLookup: @escaping (UUID) -> Tab?) {
        self.currentLayout = layout
        self.tabLookup = tabLookup

        dividerViews.forEach { $0.removeFromSuperview() }
        dividerViews.removeAll()

        // Collect active terminal views
        let activeTabIds = Set(layout.allTabIds)
        let activeViews = Set(activeTabIds.compactMap { id -> ObjectIdentifier? in
            guard let tab = tabLookup(id), let tv = tab.terminalView else { return nil }
            return ObjectIdentifier(tv)
        })

        // Hide stale terminal views
        for subview in subviews where subview is TerminalView {
            if !activeViews.contains(ObjectIdentifier(subview)) {
                subview.isHidden = true
            }
        }

        layoutNode(layout, in: bounds)
    }

    override func layout() {
        super.layout()
        guard let layout = currentLayout else { return }
        dividerViews.forEach { $0.removeFromSuperview() }
        dividerViews.removeAll()
        layoutNode(layout, in: bounds)
    }

    private func adoptTerminalView(_ terminalView: TerminalView, in rect: NSRect) {
        let needsReparent = terminalView.superview !== self
        if needsReparent {
            // Remove from old parent, clearing any auto-layout constraints
            terminalView.removeFromSuperview()
            terminalView.translatesAutoresizingMaskIntoConstraints = true
            addSubview(terminalView)
        }
        terminalView.frame = rect
        terminalView.isHidden = false

        if terminalView.surface == nil, window != nil {
            terminalView.createSurface()
        }
        terminalView.updateSurfaceSize()

        if let surface = terminalView.surface {
            ghostty_surface_refresh(surface)
        }
        terminalView.needsDisplay = true
    }

    private func layoutNode(_ node: SplitNode, in rect: NSRect) {
        switch node.content {
        case .tab(let tabId):
            guard let tab = tabLookup?(tabId) else { return }
            let terminalView = tab.makeTerminalView(frame: rect)
            adoptTerminalView(terminalView, in: rect)

        case .split(let direction, let first, let second, let ratio):
            let visualThickness: CGFloat = 1
            let hitAreaPadding: CGFloat = 4
            let totalDivider = visualThickness + hitAreaPadding * 2

            switch direction {
            case .horizontal:
                let firstWidth = (rect.width - totalDivider) * ratio
                let secondWidth = rect.width - totalDivider - firstWidth

                let firstRect = NSRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
                let dividerRect = NSRect(x: rect.minX + firstWidth, y: rect.minY, width: totalDivider, height: rect.height)
                let secondRect = NSRect(x: rect.minX + firstWidth + totalDivider, y: rect.minY, width: secondWidth, height: rect.height)

                layoutNode(first, in: firstRect)
                addDivider(in: dividerRect, direction: direction, node: node, parentRect: rect)
                layoutNode(second, in: secondRect)

            case .vertical:
                let firstHeight = (rect.height - totalDivider) * ratio
                let secondHeight = rect.height - totalDivider - firstHeight

                let firstRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
                let dividerRect = NSRect(x: rect.minX, y: rect.minY + firstHeight, width: rect.width, height: totalDivider)
                let secondRect = NSRect(x: rect.minX, y: rect.minY + firstHeight + totalDivider, width: rect.width, height: secondHeight)

                layoutNode(first, in: firstRect)
                addDivider(in: dividerRect, direction: direction, node: node, parentRect: rect)
                layoutNode(second, in: secondRect)
            }
        }
    }

    private func addDivider(in rect: NSRect, direction: SplitNode.SplitDirection, node: SplitNode, parentRect: NSRect) {
        let divider = DividerView(frame: rect)
        divider.splitDirection = direction
        divider.splitNode = node
        divider.containerView = self
        divider.parentRect = parentRect
        addSubview(divider)
        dividerViews.append(divider)
    }

    /// Draggable divider between split panes.
    class DividerView: NSView {
        var splitDirection: SplitNode.SplitDirection = .horizontal
        weak var splitNode: SplitNode?
        weak var containerView: SplitContainerView?
        var parentRect: NSRect = .zero
        private var dragStartRatio: CGFloat = 0.5
        private var dragStartPoint: NSPoint = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            // Draw only a thin line in the center of the hit area
            NSColor.white.withAlphaComponent(0.08).setFill()
            switch splitDirection {
            case .horizontal:
                let lineRect = NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
                lineRect.fill()
            case .vertical:
                let lineRect = NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
                lineRect.fill()
            }
        }

        override func resetCursorRects() {
            let cursor: NSCursor = splitDirection == .horizontal ? .resizeLeftRight : .resizeUpDown
            addCursorRect(bounds, cursor: cursor)
        }

        override func mouseDown(with event: NSEvent) {
            dragStartPoint = superview!.convert(event.locationInWindow, from: nil)
            if case .split(_, _, _, let ratio) = splitNode?.content {
                dragStartRatio = ratio
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let node = splitNode, let container = containerView, let layout = container.currentLayout else { return }
            let point = container.convert(event.locationInWindow, from: nil)

            let delta: CGFloat
            let totalSize: CGFloat

            switch splitDirection {
            case .horizontal:
                delta = point.x - dragStartPoint.x
                totalSize = parentRect.width
            case .vertical:
                delta = point.y - dragStartPoint.y
                totalSize = parentRect.height
            }

            guard totalSize > 0 else { return }
            let newRatio = dragStartRatio + delta / totalSize
            node.setRatio(newRatio)
            if let lookup = container.tabLookup {
                container.update(with: layout, tabLookup: lookup)
            }
        }
    }
}
