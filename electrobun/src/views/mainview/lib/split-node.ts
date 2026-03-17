import type { SplitNodeData, SplitDirection } from "../../../shared/types";

let _id = 0;
function uid(): string {
  return `sn-${++_id}-${Math.random().toString(36).slice(2, 8)}`;
}

export function createLeaf(tabId: string): SplitNodeData {
  return { type: "tab", id: uid(), tabId };
}

export function allTabIds(node: SplitNodeData): string[] {
  if (node.type === "tab") return [node.tabId];
  return [...allTabIds(node.first), ...allTabIds(node.second)];
}

export function findLeaf(
  node: SplitNodeData,
  tabId: string
): SplitNodeData | null {
  if (node.type === "tab") return node.tabId === tabId ? node : null;
  return findLeaf(node.first, tabId) ?? findLeaf(node.second, tabId);
}

/** Split the leaf containing `tabId`, placing `newTabId` beside it. Returns new tree. */
export function splitTab(
  node: SplitNodeData,
  tabId: string,
  newTabId: string,
  direction: SplitDirection
): SplitNodeData {
  if (node.type === "tab") {
    if (node.tabId === tabId) {
      return {
        type: "split",
        id: uid(),
        direction,
        first: createLeaf(tabId),
        second: createLeaf(newTabId),
        ratio: 0.5,
      };
    }
    return node;
  }

  const newFirst = splitTab(node.first, tabId, newTabId, direction);
  const newSecond = splitTab(node.second, tabId, newTabId, direction);
  if (newFirst === node.first && newSecond === node.second) return node;
  return { ...node, first: newFirst, second: newSecond };
}

/** Remove a tab from the tree, collapsing its parent split. Returns new tree or null if empty. */
export function removeTab(
  node: SplitNodeData,
  targetId: string
): SplitNodeData | null {
  if (node.type === "tab") {
    return node.tabId === targetId ? null : node;
  }

  // If one direct child is the target, return the other
  if (node.first.type === "tab" && node.first.tabId === targetId)
    return node.second;
  if (node.second.type === "tab" && node.second.tabId === targetId)
    return node.first;

  // Recurse
  const newFirst = removeTab(node.first, targetId);
  const newSecond = removeTab(node.second, targetId);

  if (newFirst === null) return newSecond;
  if (newSecond === null) return newFirst;
  if (newFirst === node.first && newSecond === node.second) return node;
  return { ...node, first: newFirst, second: newSecond };
}

/** Update the ratio of a specific split node. */
export function setRatio(
  node: SplitNodeData,
  nodeId: string,
  ratio: number
): SplitNodeData {
  const clamped = Math.max(0.1, Math.min(0.9, ratio));
  if (node.type === "tab") return node;
  if (node.id === nodeId) return { ...node, ratio: clamped };
  const newFirst = setRatio(node.first, nodeId, clamped);
  const newSecond = setRatio(node.second, nodeId, clamped);
  if (newFirst === node.first && newSecond === node.second) return node;
  return { ...node, first: newFirst, second: newSecond };
}
