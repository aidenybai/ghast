import { useState, useCallback, useRef } from "react";
import { useTabManagerStore } from "../store/tab-manager";
import { WorkspaceSidebar } from "./WorkspaceSidebar";
import { TabBar } from "./TabBar";
import { TerminalContainer } from "./TerminalContainer";

export function Layout() {
  const isSidebarVisible = useTabManagerStore((s) => s.isSidebarVisible);
  const [sidebarWidth, setSidebarWidth] = useState(180);
  const dragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(0);

  const onDividerMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      dragging.current = true;
      startX.current = e.clientX;
      startWidth.current = sidebarWidth;

      const onMouseMove = (ev: MouseEvent) => {
        if (!dragging.current) return;
        const delta = ev.clientX - startX.current;
        setSidebarWidth(Math.min(Math.max(startWidth.current + delta, 120), 400));
      };

      const onMouseUp = () => {
        dragging.current = false;
        document.removeEventListener("mousemove", onMouseMove);
        document.removeEventListener("mouseup", onMouseUp);
        document.body.style.cursor = "";
      };

      document.addEventListener("mousemove", onMouseMove);
      document.addEventListener("mouseup", onMouseUp);
      document.body.style.cursor = "col-resize";
    },
    [sidebarWidth]
  );

  return (
    <div className="flex h-full">
      {isSidebarVisible && (
        <>
          <WorkspaceSidebar width={sidebarWidth} />
          {/* Resizable divider */}
          <div
            className="flex items-center cursor-col-resize px-[2px] flex-shrink-0"
            onMouseDown={onDividerMouseDown}
          >
            <div className="w-px h-full bg-white/[0.06]" />
          </div>
        </>
      )}
      <div className="flex flex-col flex-1 min-w-0">
        <TabBar />
        <TerminalContainer />
      </div>
    </div>
  );
}
