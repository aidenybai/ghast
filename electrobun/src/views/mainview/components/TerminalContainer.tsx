import { useTabManagerStore } from "../store/tab-manager";
import { allTabIds } from "../lib/split-node";
import { SplitContainer } from "./SplitContainer";
import { TerminalPane } from "./TerminalPane";

export function TerminalContainer() {
  const workspace = useTabManagerStore((s) => s.getSelectedWorkspace());
  if (!workspace) return null;

  const { splitLayout, selectedTabId, tabs } = workspace;

  const inSplitMode =
    splitLayout != null &&
    allTabIds(splitLayout).length > 1 &&
    selectedTabId != null &&
    allTabIds(splitLayout).includes(selectedTabId);

  if (inSplitMode && splitLayout) {
    return (
      <div className="flex-1 min-h-0">
        <SplitContainer node={splitLayout} tabs={tabs} />
      </div>
    );
  }

  const selectedTab =
    tabs.find((t) => t.id === selectedTabId) ?? tabs[0];

  if (!selectedTab) return null;

  return (
    <div className="flex-1 min-h-0">
      <TerminalPane tabData={selectedTab} />
    </div>
  );
}
