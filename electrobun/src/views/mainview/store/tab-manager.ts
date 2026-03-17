import { create } from "zustand";
import type { TabData, WorkspaceData, SplitDirection } from "../../../shared/types";
import {
  createLeaf,
  splitTab,
  removeTab,
  allTabIds,
  setRatio as setRatioFn,
} from "../lib/split-node";

function uuid(): string {
  return crypto.randomUUID();
}

function normalizePath(path: string): string {
  return path.replace(/\/+$/, "") || "/";
}

function createTab(workingDirectory: string | null): TabData {
  return {
    id: uuid(),
    title: "Terminal",
    currentDirectory: workingDirectory,
    initialWorkingDirectory: workingDirectory,
  };
}

function createWorkspace(directory: string): WorkspaceData {
  return {
    id: uuid(),
    directory,
    tabs: [],
    selectedTabId: null,
    splitLayout: null,
  };
}

export interface TabManagerState {
  workspaces: WorkspaceData[];
  selectedWorkspaceId: string | null;
  isSidebarVisible: boolean;

  // Getters
  getSelectedWorkspace: () => WorkspaceData | undefined;
  getSelectedTab: () => TabData | undefined;

  // Workspace actions
  addWorkspace: (directory: string) => WorkspaceData;
  selectWorkspace: (id: string) => void;
  closeWorkspace: (id: string) => void;
  handleDirectoryChange: (tabId: string, directory: string) => void;

  // Tab actions
  createTab: () => TabData;
  closeTab: (id: string) => void;
  selectTab: (id: string) => void;
  selectTabByIndex: (index: number) => void;
  moveTab: (fromId: string, toId: string) => void;
  selectNextTab: () => void;
  selectPreviousTab: () => void;
  updateTabTitle: (tabId: string, title: string) => void;
  updateTabDirectory: (tabId: string, directory: string) => void;

  // Split actions
  createSplitTab: (
    nextToTabId: string,
    direction: SplitDirection
  ) => TabData | null;
  setSplitRatio: (nodeId: string, ratio: number) => void;
  selectNextPane: () => void;
  selectPreviousPane: () => void;

  // UI
  toggleSidebar: () => void;
}

const HOME_DIR =
  typeof process !== "undefined"
    ? process.env.HOME || "/Users"
    : "/Users";

export const useTabManagerStore = create<TabManagerState>((set, get) => {
  // Initialize with one workspace + one tab
  const initialWs = createWorkspace(HOME_DIR);
  const initialTab = createTab(HOME_DIR);
  initialWs.tabs.push(initialTab);
  initialWs.selectedTabId = initialTab.id;

  return {
    workspaces: [initialWs],
    selectedWorkspaceId: initialWs.id,
    isSidebarVisible: true,

    getSelectedWorkspace: () => {
      const { workspaces, selectedWorkspaceId } = get();
      if (!selectedWorkspaceId) return workspaces[0];
      return workspaces.find((w) => w.id === selectedWorkspaceId) ?? workspaces[0];
    },

    getSelectedTab: () => {
      const ws = get().getSelectedWorkspace();
      if (!ws) return undefined;
      if (!ws.selectedTabId) return ws.tabs[0];
      return ws.tabs.find((t) => t.id === ws.selectedTabId) ?? ws.tabs[0];
    },

    addWorkspace: (directory: string) => {
      const ws = createWorkspace(directory);
      const tab = createTab(directory);
      ws.tabs.push(tab);
      ws.selectedTabId = tab.id;
      set((s) => ({
        workspaces: [...s.workspaces, ws],
        selectedWorkspaceId: ws.id,
      }));
      return ws;
    },

    selectWorkspace: (id: string) => {
      if (get().workspaces.some((w) => w.id === id)) {
        set({ selectedWorkspaceId: id });
      }
    },

    closeWorkspace: (id: string) => {
      set((s) => {
        const next = s.workspaces.filter((w) => w.id !== id);
        return {
          workspaces: next,
          selectedWorkspaceId:
            s.selectedWorkspaceId === id
              ? next[0]?.id ?? null
              : s.selectedWorkspaceId,
        };
      });
    },

    handleDirectoryChange: (tabId: string, directory: string) => {
      const normalized = normalizePath(directory);
      set((s) => {
        const workspaces = s.workspaces.map((w) => ({ ...w, tabs: [...w.tabs] }));
        const sourceWs = workspaces.find((w) =>
          w.tabs.some((t) => t.id === tabId)
        );
        if (!sourceWs) return s;
        if (normalizePath(sourceWs.directory) === normalized) return s;

        // Single-tab workspace: just update its directory if no other workspace owns it
        if (sourceWs.tabs.length === 1) {
          const otherOwns = workspaces.some(
            (w) => w.id !== sourceWs.id && normalizePath(w.directory) === normalized
          );
          if (!otherOwns) {
            sourceWs.directory = normalized;
            return { workspaces };
          }
        }

        // Find or create target workspace
        let targetWs = workspaces.find(
          (w) => normalizePath(w.directory) === normalized
        );
        if (!targetWs) {
          targetWs = createWorkspace(normalized);
          workspaces.push(targetWs);
        }

        // Move tab
        const tab = sourceWs.tabs.find((t) => t.id === tabId);
        if (!tab) return s;
        sourceWs.tabs = sourceWs.tabs.filter((t) => t.id !== tabId);
        if (sourceWs.selectedTabId === tabId) {
          sourceWs.selectedTabId = sourceWs.tabs[0]?.id ?? null;
        }
        targetWs.tabs = [...targetWs.tabs, tab];
        targetWs.selectedTabId = tab.id;

        return { workspaces, selectedWorkspaceId: targetWs.id };
      });
    },

    createTab: () => {
      const ws = get().getSelectedWorkspace();
      const cwd =
        get().getSelectedTab()?.currentDirectory ?? ws?.directory ?? HOME_DIR;
      const tab = createTab(cwd);

      if (!ws) {
        // Create new workspace
        const newWs = createWorkspace(HOME_DIR);
        newWs.tabs.push(tab);
        newWs.selectedTabId = tab.id;
        set((s) => ({
          workspaces: [...s.workspaces, newWs],
          selectedWorkspaceId: newWs.id,
        }));
      } else {
        set((s) => ({
          workspaces: s.workspaces.map((w) =>
            w.id === ws.id
              ? { ...w, tabs: [...w.tabs, tab], selectedTabId: tab.id }
              : w
          ),
        }));
      }
      return tab;
    },

    closeTab: (id: string) => {
      set((s) => {
        let workspaces = s.workspaces.map((w) => ({ ...w, tabs: [...w.tabs], splitLayout: w.splitLayout }));
        let selectedWorkspaceId = s.selectedWorkspaceId;

        for (const ws of workspaces) {
          const tabIndex = ws.tabs.findIndex((t) => t.id === id);
          if (tabIndex === -1) continue;

          ws.tabs.splice(tabIndex, 1);

          // Remove from split layout
          if (ws.splitLayout) {
            ws.splitLayout = removeTab(ws.splitLayout, id);
            if (ws.splitLayout && allTabIds(ws.splitLayout).length <= 1) {
              ws.splitLayout = null;
            }
          }

          if (ws.tabs.length === 0) {
            // Workspace is empty, remove it
            workspaces = workspaces.filter((w) => w.id !== ws.id);
            if (selectedWorkspaceId === ws.id) {
              selectedWorkspaceId = workspaces[0]?.id ?? null;
            }
          } else if (ws.selectedTabId === id) {
            if (ws.splitLayout) {
              const visible = allTabIds(ws.splitLayout);
              ws.selectedTabId = visible[0] ?? ws.tabs[0]?.id ?? null;
            } else {
              const newIndex = Math.min(tabIndex, ws.tabs.length - 1);
              ws.selectedTabId = ws.tabs[newIndex]?.id ?? null;
            }
          }
          break;
        }

        return { workspaces, selectedWorkspaceId };
      });
    },

    selectTab: (id: string) => {
      set((s) => ({
        workspaces: s.workspaces.map((w) =>
          w.tabs.some((t) => t.id === id) ? { ...w, selectedTabId: id } : w
        ),
      }));
    },

    selectTabByIndex: (index: number) => {
      const ws = get().getSelectedWorkspace();
      if (!ws) return;
      if (index === -1) {
        // Last tab (Cmd+9)
        const last = ws.tabs[ws.tabs.length - 1];
        if (last) get().selectTab(last.id);
      } else if (index >= 0 && index < ws.tabs.length) {
        get().selectTab(ws.tabs[index].id);
      }
    },

    moveTab: (fromId: string, toId: string) => {
      set((s) => ({
        workspaces: s.workspaces.map((w) => {
          const fromIdx = w.tabs.findIndex((t) => t.id === fromId);
          const toIdx = w.tabs.findIndex((t) => t.id === toId);
          if (fromIdx === -1 || toIdx === -1 || fromIdx === toIdx) return w;
          const tabs = [...w.tabs];
          const [moved] = tabs.splice(fromIdx, 1);
          tabs.splice(toIdx, 0, moved);
          return { ...w, tabs };
        }),
      }));
    },

    selectNextTab: () => {
      const ws = get().getSelectedWorkspace();
      if (!ws || ws.tabs.length <= 1) return;
      const idx = ws.tabs.findIndex((t) => t.id === ws.selectedTabId);
      if (idx === -1) return;
      const next = (idx + 1) % ws.tabs.length;
      get().selectTab(ws.tabs[next].id);
    },

    selectPreviousTab: () => {
      const ws = get().getSelectedWorkspace();
      if (!ws || ws.tabs.length <= 1) return;
      const idx = ws.tabs.findIndex((t) => t.id === ws.selectedTabId);
      if (idx === -1) return;
      const prev = (idx - 1 + ws.tabs.length) % ws.tabs.length;
      get().selectTab(ws.tabs[prev].id);
    },

    updateTabTitle: (tabId: string, title: string) => {
      set((s) => ({
        workspaces: s.workspaces.map((w) => ({
          ...w,
          tabs: w.tabs.map((t) => (t.id === tabId ? { ...t, title } : t)),
        })),
      }));
    },

    updateTabDirectory: (tabId: string, directory: string) => {
      set((s) => ({
        workspaces: s.workspaces.map((w) => ({
          ...w,
          tabs: w.tabs.map((t) =>
            t.id === tabId ? { ...t, currentDirectory: directory } : t
          ),
        })),
      }));
    },

    createSplitTab: (nextToTabId: string, direction: SplitDirection) => {
      const ws = get().getSelectedWorkspace();
      if (!ws) return null;
      const tab = createTab(ws.directory);

      set((s) => ({
        workspaces: s.workspaces.map((w) => {
          if (w.id !== ws.id) return w;
          const newTabs = [...w.tabs, tab];
          let layout = w.splitLayout;
          if (layout) {
            layout = splitTab(layout, nextToTabId, tab.id, direction);
          } else {
            const root = createLeaf(nextToTabId);
            layout = splitTab(root, nextToTabId, tab.id, direction);
          }
          return { ...w, tabs: newTabs, selectedTabId: tab.id, splitLayout: layout };
        }),
      }));
      return tab;
    },

    setSplitRatio: (nodeId: string, ratio: number) => {
      set((s) => ({
        workspaces: s.workspaces.map((w) =>
          w.splitLayout
            ? { ...w, splitLayout: setRatioFn(w.splitLayout, nodeId, ratio) }
            : w
        ),
      }));
    },

    selectNextPane: () => {
      const ws = get().getSelectedWorkspace();
      if (!ws?.splitLayout) return;
      const ids = allTabIds(ws.splitLayout);
      if (ids.length <= 1 || !ws.selectedTabId) return;
      const idx = ids.indexOf(ws.selectedTabId);
      const nextId = ids[(idx + 1) % ids.length];
      get().selectTab(nextId);
    },

    selectPreviousPane: () => {
      const ws = get().getSelectedWorkspace();
      if (!ws?.splitLayout) return;
      const ids = allTabIds(ws.splitLayout);
      if (ids.length <= 1 || !ws.selectedTabId) return;
      const idx = ids.indexOf(ws.selectedTabId);
      const prevId = ids[(idx - 1 + ids.length) % ids.length];
      get().selectTab(prevId);
    },

    toggleSidebar: () => {
      set((s) => ({ isSidebarVisible: !s.isSidebarVisible }));
    },
  };
});
