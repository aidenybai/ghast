import { useEffect } from "react";
import { useTabManagerStore } from "../store/tab-manager";

export function useKeyboardShortcuts() {
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;
      if (!meta) return;

      const store = useTabManagerStore.getState();

      // Cmd+T: New Tab
      if (e.key === "t" && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        store.createTab();
        return;
      }

      // Cmd+W: Close Tab
      if (e.key === "w" && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        const tab = store.getSelectedTab();
        if (tab) store.closeTab(tab.id);
        return;
      }

      // Cmd+D: Split Right
      if (e.key === "d" && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        const tab = store.getSelectedTab();
        if (tab) store.createSplitTab(tab.id, "horizontal");
        return;
      }

      // Cmd+Shift+D: Split Down
      if (e.key === "D" && e.shiftKey && !e.altKey) {
        e.preventDefault();
        const tab = store.getSelectedTab();
        if (tab) store.createSplitTab(tab.id, "vertical");
        return;
      }

      // Cmd+Shift+] or }: Next Tab
      if ((e.key === "]" || e.key === "}") && e.shiftKey && !e.altKey) {
        e.preventDefault();
        store.selectNextTab();
        return;
      }

      // Cmd+Shift+[ or {: Previous Tab
      if ((e.key === "[" || e.key === "{") && e.shiftKey && !e.altKey) {
        e.preventDefault();
        store.selectPreviousTab();
        return;
      }

      // Cmd+Option+]: Next Pane
      if (e.key === "]" && e.altKey && !e.shiftKey) {
        e.preventDefault();
        store.selectNextPane();
        return;
      }

      // Cmd+Option+[: Previous Pane
      if (e.key === "[" && e.altKey && !e.shiftKey) {
        e.preventDefault();
        store.selectPreviousPane();
        return;
      }

      // Cmd+1-9: Select Tab by index
      if (e.key >= "1" && e.key <= "9" && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        const index = e.key === "9" ? -1 : parseInt(e.key) - 1;
        store.selectTabByIndex(index);
        return;
      }

      // Cmd+\: Toggle Sidebar
      if (e.key === "\\" && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        store.toggleSidebar();
        return;
      }
    };

    window.addEventListener("keydown", handler, { capture: true });
    return () => window.removeEventListener("keydown", handler, { capture: true });
  }, []);
}
