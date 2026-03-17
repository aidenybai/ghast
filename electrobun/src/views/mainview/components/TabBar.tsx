import { useTabManagerStore } from "../store/tab-manager";
import { TabList } from "./TabList";

export function TabBar() {
  const toggleSidebar = useTabManagerStore((s) => s.toggleSidebar);
  const isSidebarVisible = useTabManagerStore((s) => s.isSidebarVisible);
  const createTab = useTabManagerStore((s) => s.createTab);
  const createSplitTab = useTabManagerStore((s) => s.createSplitTab);
  const getSelectedTab = useTabManagerStore((s) => s.getSelectedTab);

  return (
    <div className="relative h-9 flex-shrink-0">
      {/* Tabs fill entire width */}
      <TabList />

      {/* Overlay buttons */}
      <div className="absolute inset-0 flex items-center pointer-events-none">
        {/* Sidebar toggle */}
        <button
          onClick={toggleSidebar}
          className="pointer-events-auto flex items-center justify-center w-8 h-8 bg-[#1e1e2e]"
        >
          <svg
            className={`w-3 h-3 ${isSidebarVisible ? "text-white/60" : "text-white/30"}`}
            fill="none"
            viewBox="0 0 16 16"
            stroke="currentColor"
            strokeWidth={1.5}
          >
            <rect x="1" y="2" width="14" height="12" rx="2" />
            <path d="M5.5 2v12" />
          </svg>
        </button>

        <div className="flex-1" />

        {/* Split button */}
        <button
          onClick={() => {
            const tab = getSelectedTab();
            if (tab) createSplitTab(tab.id, "horizontal");
          }}
          className="pointer-events-auto flex items-center justify-center w-8 h-8 bg-[#1e1e2e]"
        >
          <svg
            className="w-3 h-3 text-white/40"
            fill="none"
            viewBox="0 0 16 16"
            stroke="currentColor"
            strokeWidth={1.5}
          >
            <rect x="1" y="2" width="14" height="12" rx="2" />
            <path d="M8 2v12" />
          </svg>
        </button>

        {/* New tab button */}
        <button
          onClick={() => createTab()}
          className="pointer-events-auto flex items-center justify-center w-8 h-8 bg-[#1e1e2e]"
        >
          <svg
            className="w-3 h-3 text-white/40"
            fill="none"
            viewBox="0 0 12 12"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path d="M6 1v10M1 6h10" />
          </svg>
        </button>
      </div>
    </div>
  );
}
