import { useRef, useState } from "react";
import { useTabManagerStore } from "../store/tab-manager";
import { TabItem } from "./TabItem";

export function TabList() {
  const workspace = useTabManagerStore((s) => s.getSelectedWorkspace());
  const closeTab = useTabManagerStore((s) => s.closeTab);
  const selectTab = useTabManagerStore((s) => s.selectTab);
  const moveTab = useTabManagerStore((s) => s.moveTab);
  const [draggedTabId, setDraggedTabId] = useState<string | null>(null);

  if (!workspace) return null;

  return (
    <div className="flex h-full items-center">
      {workspace.tabs.map((tab, index) => (
        <div key={tab.id} className="flex items-center h-full flex-1 min-w-0">
          <TabItem
            tab={tab}
            index={index}
            isSelected={tab.id === workspace.selectedTabId}
            isOnly={workspace.tabs.length === 1}
            onSelect={() => selectTab(tab.id)}
            onClose={() => closeTab(tab.id)}
            onDragStart={() => setDraggedTabId(tab.id)}
            onDragEnd={() => setDraggedTabId(null)}
            onDragEnter={() => {
              if (draggedTabId && draggedTabId !== tab.id) {
                moveTab(draggedTabId, tab.id);
              }
            }}
          />
          {/* Separator */}
          {index < workspace.tabs.length - 1 && (
            <div className="w-px h-3.5 bg-white/[0.08] flex-shrink-0" />
          )}
        </div>
      ))}
    </div>
  );
}
