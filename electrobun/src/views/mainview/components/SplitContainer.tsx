import type { SplitNodeData } from "../../../shared/types";
import type { TabData } from "../../../shared/types";
import { SplitDivider } from "./SplitDivider";
import { TerminalPane } from "./TerminalPane";

interface Props {
  node: SplitNodeData;
  tabs: TabData[];
}

export function SplitContainer({ node, tabs }: Props) {
  if (node.type === "tab") {
    const tab = tabs.find((t) => t.id === node.tabId);
    if (!tab) return null;
    return <TerminalPane tabData={tab} />;
  }

  const { direction, first, second, ratio, id: nodeId } = node;
  const isHorizontal = direction === "horizontal";

  return (
    <div
      className={`flex ${isHorizontal ? "flex-row" : "flex-col"} w-full h-full`}
    >
      <div
        style={{
          [isHorizontal ? "width" : "height"]: `calc(${ratio * 100}% - 4.5px)`,
        }}
        className="min-w-0 min-h-0"
      >
        <SplitContainer node={first} tabs={tabs} />
      </div>

      <SplitDivider direction={direction} nodeId={nodeId} />

      <div className="flex-1 min-w-0 min-h-0">
        <SplitContainer node={second} tabs={tabs} />
      </div>
    </div>
  );
}
