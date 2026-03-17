import { useEffect, useRef } from "react";
import type { TabData } from "../../../shared/types";
import { useTabManagerStore } from "../store/tab-manager";
import { terminalRegistry } from "../lib/terminal-registry";

const PTY_WS_URL = "ws://localhost:7681";

interface Props {
  tabData: TabData;
}

export function TerminalPane({ tabData }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const selectTab = useTabManagerStore((s) => s.selectTab);
  const updateTabTitle = useTabManagerStore((s) => s.updateTabTitle);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    let disposed = false;
    let ws: WebSocket | null = null;

    const setup = async () => {
      const { init, Terminal, FitAddon } = await import("ghostty-web");
      await init();

      if (disposed) return;

      // Check if terminal already exists for this tab
      let term = terminalRegistry.get(tabData.id);
      if (!term) {
        term = new Terminal({
          fontSize: 14,
          fontFamily:
            'ui-monospace, "SF Mono", Menlo, Monaco, "Cascadia Code", "Courier New", monospace',
          cursorBlink: true,
          cursorStyle: "block",
          theme: {
            background: "#1e1e2e",
            foreground: "#cdd6f4",
            cursor: "#f5e0dc",
            selectionBackground: "#585b70",
            selectionForeground: "#cdd6f4",
            black: "#45475a",
            red: "#f38ba8",
            green: "#a6e3a1",
            yellow: "#f9e2af",
            blue: "#89b4fa",
            magenta: "#f5c2e7",
            cyan: "#94e2d5",
            white: "#bac2de",
            brightBlack: "#585b70",
            brightRed: "#f38ba8",
            brightGreen: "#a6e3a1",
            brightYellow: "#f9e2af",
            brightBlue: "#89b4fa",
            brightMagenta: "#f5c2e7",
            brightCyan: "#94e2d5",
            brightWhite: "#a6adc8",
          },
          scrollback: 10000,
        });
        terminalRegistry.set(tabData.id, term);
      }

      term.open(container);

      const fitAddon = new FitAddon();
      term.loadAddon(fitAddon);
      fitAddon.fit();

      // Observe container resize
      const observer = new ResizeObserver(() => {
        if (disposed) return;
        fitAddon.fit();
        // Notify PTY of new size
        if (ws?.readyState === WebSocket.OPEN) {
          const dims = fitAddon.proposeDimensions();
          if (dims) {
            ws.send(JSON.stringify({ type: "resize", cols: dims.cols, rows: dims.rows }));
          }
        }
      });
      observer.observe(container);

      // Handle title changes
      term.onTitleChange((title: string) => {
        if (!disposed) updateTabTitle(tabData.id, title);
      });

      // Connect to PTY server
      ws = new WebSocket(PTY_WS_URL);

      ws.onopen = () => {
        const dims = fitAddon.proposeDimensions();
        ws!.send(
          JSON.stringify({
            type: "init",
            cols: dims?.cols ?? 80,
            rows: dims?.rows ?? 24,
            cwd: tabData.initialWorkingDirectory || tabData.currentDirectory,
          })
        );
      };

      ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.type === "data") {
          term!.write(msg.data);
        } else if (msg.type === "exit") {
          if (!disposed) {
            useTabManagerStore.getState().closeTab(tabData.id);
          }
        }
      };

      // User input -> PTY
      term.onData((data: string) => {
        if (ws?.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: "data", data }));
        }
      });

      return () => {
        observer.disconnect();
      };
    };

    const cleanupPromise = setup();

    return () => {
      disposed = true;
      ws?.close();
      cleanupPromise.then((cleanup) => cleanup?.());
    };
  }, [tabData.id]);

  return (
    <div
      ref={containerRef}
      className="w-full h-full terminal-pane"
      onMouseDown={() => selectTab(tabData.id)}
    />
  );
}
