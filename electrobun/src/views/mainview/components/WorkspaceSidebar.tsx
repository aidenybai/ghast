import { useTabManagerStore } from "../store/tab-manager";
import { WorkspaceItem } from "./WorkspaceItem";

interface Props {
  width: number;
}

export function WorkspaceSidebar({ width }: Props) {
  const workspaces = useTabManagerStore((s) => s.workspaces);
  const selectedWorkspaceId = useTabManagerStore((s) => s.selectedWorkspaceId);
  const addWorkspace = useTabManagerStore((s) => s.addWorkspace);
  const selectWorkspace = useTabManagerStore((s) => s.selectWorkspace);
  const closeWorkspace = useTabManagerStore((s) => s.closeWorkspace);

  return (
    <div
      className="flex flex-col flex-shrink-0"
      style={{ width }}
    >
      <div className="h-2" />

      {/* + Workspace button */}
      <div className="px-2 pb-0.5">
        <button
          onClick={() => {
            const home = "/Users";
            addWorkspace(home);
          }}
          className="flex items-center gap-1 w-full px-2.5 py-2 rounded-md text-white/30 hover:bg-white/[0.03] transition-colors"
        >
          <svg
            className="w-2.5 h-2.5"
            fill="none"
            viewBox="0 0 12 12"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path d="M6 1v10M1 6h10" />
          </svg>
          <span className="text-[11px] font-medium">Workspace</span>
        </button>
      </div>

      {/* Workspace list */}
      <div className="flex-1 overflow-y-auto px-2">
        <div className="flex flex-col gap-1">
          {workspaces.map((ws) => (
            <WorkspaceItem
              key={ws.id}
              workspace={ws}
              isSelected={ws.id === selectedWorkspaceId}
              onSelect={() => selectWorkspace(ws.id)}
              onClose={() => closeWorkspace(ws.id)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
