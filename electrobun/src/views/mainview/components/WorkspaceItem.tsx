import { useState } from "react";
import type { WorkspaceData } from "../../../shared/types";

interface Props {
  workspace: WorkspaceData;
  isSelected: boolean;
  onSelect: () => void;
  onClose: () => void;
}

function getDisplayName(directory: string): string {
  const parts = directory.split("/").filter(Boolean);
  return parts[parts.length - 1] || "~";
}

function getDirectoryLabel(workspace: WorkspaceData): string {
  const dir =
    workspace.tabs.find((t) => t.id === workspace.selectedTabId)
      ?.currentDirectory ?? workspace.directory;
  const home =
    typeof process !== "undefined" ? process.env.HOME || "/Users" : "/Users";
  if (dir.startsWith(home)) {
    const rel = dir.slice(home.length);
    return rel === "" ? "~" : "~" + rel;
  }
  return dir;
}

export function WorkspaceItem({
  workspace,
  isSelected,
  onSelect,
  onClose,
}: Props) {
  const [isHovering, setIsHovering] = useState(false);

  const bg = isSelected
    ? "bg-white/[0.06]"
    : isHovering
      ? "bg-white/[0.03]"
      : "";

  return (
    <div
      className={`flex items-center gap-2 px-2.5 py-2 rounded-md cursor-pointer ${bg}`}
      onClick={onSelect}
      onMouseEnter={() => setIsHovering(true)}
      onMouseLeave={() => setIsHovering(false)}
    >
      <div className="flex flex-col gap-0.5 min-w-0 flex-1">
        <span
          className={`text-[11px] font-medium truncate ${
            isSelected ? "text-white/90" : "text-white/50"
          }`}
        >
          {getDisplayName(workspace.directory)}
        </span>
        <span
          className={`text-[10px] truncate ${
            isSelected ? "text-white/40" : "text-white/20"
          }`}
        >
          {getDirectoryLabel(workspace)}
        </span>
      </div>

      {isHovering ? (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onClose();
          }}
          className="flex items-center justify-center w-4 h-4 flex-shrink-0"
        >
          <svg
            className="w-2 h-2 text-white/40"
            fill="none"
            viewBox="0 0 8 8"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path d="M1 1l6 6M7 1l-6 6" />
          </svg>
        </button>
      ) : (
        <span className="text-[10px] font-mono text-white/20 flex-shrink-0">
          {workspace.tabs.length}
        </span>
      )}
    </div>
  );
}
