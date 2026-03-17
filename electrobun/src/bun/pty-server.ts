import { WebSocketServer, WebSocket } from "ws";
import * as pty from "node-pty";

const PORT = 7681;
const wss = new WebSocketServer({ port: PORT });

console.log(`PTY server listening on ws://localhost:${PORT}`);

wss.on("connection", (ws: WebSocket) => {
  const shell = process.env.SHELL || "/bin/zsh";
  const home = process.env.HOME || "/Users";

  let cols = 80;
  let rows = 24;
  let cwd = home;

  // Wait for init message with size and cwd before spawning
  let ptyProcess: pty.IPty | null = null;

  const spawn = () => {
    ptyProcess = pty.spawn(shell, ["-l"], {
      name: "xterm-256color",
      cols,
      rows,
      cwd,
      env: {
        ...process.env,
        TERM: "xterm-256color",
        TERM_PROGRAM: "ghast",
        COLORTERM: "truecolor",
      } as Record<string, string>,
    });

    ptyProcess.onData((data: string) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "data", data }));
      }
    });

    ptyProcess.onExit(({ exitCode }) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "exit", exitCode }));
      }
    });
  };

  ws.on("message", (raw: Buffer | string) => {
    const msg = JSON.parse(raw.toString());

    switch (msg.type) {
      case "init":
        cols = msg.cols || 80;
        rows = msg.rows || 24;
        cwd = msg.cwd || home;
        if (!ptyProcess) spawn();
        break;

      case "data":
        ptyProcess?.write(msg.data);
        break;

      case "resize":
        if (msg.cols && msg.rows) {
          cols = msg.cols;
          rows = msg.rows;
          ptyProcess?.resize(msg.cols, msg.rows);
        }
        break;
    }
  });

  ws.on("close", () => {
    ptyProcess?.kill();
  });

  ws.on("error", () => {
    ptyProcess?.kill();
  });
});
