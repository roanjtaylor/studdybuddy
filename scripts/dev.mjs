// Starts `next dev` and opens the browser once the server is actually reachable.
// Next.js has no built-in "open browser on start" flag, so we wrap it here.
import { spawn } from "node:child_process";

const port = process.env.PORT || "3000";
const url = `http://localhost:${port}`;

const child = spawn("next", ["dev"], {
  stdio: "inherit",
  shell: true,
  env: process.env,
});

child.on("exit", (code) => process.exit(code ?? 0));

let opened = false;

function openBrowser() {
  if (opened) return;
  opened = true;

  const platform = process.platform;
  const cmd =
    platform === "win32" ? "cmd" : platform === "darwin" ? "open" : "xdg-open";
  const args =
    platform === "win32" ? ["/c", "start", "", url] : [url];

  spawn(cmd, args, { stdio: "ignore", shell: false, detached: true }).unref();
}

async function waitForServer() {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    try {
      await fetch(url, { method: "HEAD" });
      openBrowser();
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 400));
    }
  }
}

waitForServer();
