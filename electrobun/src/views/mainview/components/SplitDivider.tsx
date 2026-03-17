import { useRef, useCallback } from "react";
import type { SplitDirection } from "../../../shared/types";
import { useTabManagerStore } from "../store/tab-manager";

interface Props {
  direction: SplitDirection;
  nodeId: string;
}

export function SplitDivider({ direction, nodeId }: Props) {
  const setSplitRatio = useTabManagerStore((s) => s.setSplitRatio);
  const isHorizontal = direction === "horizontal";
  const dragStartRatio = useRef(0.5);
  const dragStartPos = useRef(0);
  const parentSize = useRef(0);

  const onMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      const parentEl = (e.currentTarget as HTMLElement).parentElement;
      if (!parentEl) return;

      const parentRect = parentEl.getBoundingClientRect();
      parentSize.current = isHorizontal ? parentRect.width : parentRect.height;
      dragStartPos.current = isHorizontal ? e.clientX : e.clientY;

      // Read current ratio from the first child's computed size
      const firstChild = parentEl.children[0] as HTMLElement;
      if (firstChild) {
        const firstSize = isHorizontal
          ? firstChild.getBoundingClientRect().width
          : firstChild.getBoundingClientRect().height;
        // Account for divider width (9px)
        dragStartRatio.current = firstSize / (parentSize.current - 9);
      }

      const onMouseMove = (ev: MouseEvent) => {
        const delta =
          (isHorizontal ? ev.clientX : ev.clientY) - dragStartPos.current;
        const total = parentSize.current;
        if (total <= 0) return;
        const newRatio = dragStartRatio.current + delta / total;
        setSplitRatio(nodeId, newRatio);
      };

      const onMouseUp = () => {
        document.removeEventListener("mousemove", onMouseMove);
        document.removeEventListener("mouseup", onMouseUp);
        document.body.style.cursor = "";
      };

      document.addEventListener("mousemove", onMouseMove);
      document.addEventListener("mouseup", onMouseUp);
      document.body.style.cursor = isHorizontal ? "col-resize" : "row-resize";
    },
    [isHorizontal, nodeId, setSplitRatio]
  );

  return (
    <div
      className={`flex items-center justify-center flex-shrink-0 ${
        isHorizontal
          ? "w-[9px] cursor-col-resize py-0"
          : "h-[9px] cursor-row-resize px-0"
      }`}
      onMouseDown={onMouseDown}
    >
      <div
        className={
          isHorizontal
            ? "w-px h-full bg-white/[0.08]"
            : "h-px w-full bg-white/[0.08]"
        }
      />
    </div>
  );
}
