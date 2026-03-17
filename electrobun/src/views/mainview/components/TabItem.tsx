import { useState } from "react";
import type { TabData } from "../../../shared/types";

interface Props {
  tab: TabData;
  index: number;
  isSelected: boolean;
  isOnly: boolean;
  onSelect: () => void;
  onClose: () => void;
  onDragStart: () => void;
  onDragEnd: () => void;
  onDragEnter: () => void;
}

export function TabItem({
  tab,
  index,
  isSelected,
  isOnly,
  onSelect,
  onClose,
  onDragStart,
  onDragEnd,
  onDragEnter,
}: Props) {
  const [isHovering, setIsHovering] = useState(false);

  const bg = isSelected
    ? "bg-white/[0.06]"
    : isHovering
      ? "bg-white/[0.03]"
      : "";

  return (
    <div
      className={`flex items-center justify-center gap-1.5 px-3.5 py-2 flex-1 min-w-0 cursor-pointer ${bg}`}
      onClick={onSelect}
      onMouseEnter={() => setIsHovering(true)}
      onMouseLeave={() => setIsHovering(false)}
      draggable
      onDragStart={(e) => {
        e.dataTransfer.setData("text/plain", tab.id);
        e.dataTransfer.effectAllowed = "move";
        onDragStart();
      }}
      onDragEnd={onDragEnd}
      onDragEnter={(e) => {
        e.preventDefault();
        onDragEnter();
      }}
      onDragOver={(e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
      }}
    >
      {/* Close button */}
      {isHovering && !isOnly && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onClose();
          }}
          className="flex items-center justify-center w-3.5 h-3.5 flex-shrink-0"
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
      )}

      {/* Title */}
      <span
        className={`text-xs truncate ${
          isSelected ? "text-white/90" : "text-white/40"
        }`}
      >
        {tab.title || "Terminal"}
      </span>

      {/* Keyboard shortcut indicator */}
      {index < 9 && (
        <span className="text-[10px] font-mono text-white/20 flex-shrink-0">
          {"\u2318"}
          {index + 1}
        </span>
      )}
    </div>
  );
}
