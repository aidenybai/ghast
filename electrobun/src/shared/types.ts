export interface TabData {
  id: string;
  title: string;
  currentDirectory: string | null;
  initialWorkingDirectory: string | null;
}

export interface WorkspaceData {
  id: string;
  directory: string;
  tabs: TabData[];
  selectedTabId: string | null;
  splitLayout: SplitNodeData | null;
}

export type SplitDirection = "horizontal" | "vertical";

export type SplitNodeData =
  | { type: "tab"; id: string; tabId: string }
  | {
      type: "split";
      id: string;
      direction: SplitDirection;
      first: SplitNodeData;
      second: SplitNodeData;
      ratio: number;
    };
